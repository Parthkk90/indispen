import Fastify from 'fastify'
import cors from '@fastify/cors'
import { z } from 'zod'
import { encodeAbiParameters, isAddress, isHex, type Address, type Hex } from 'viem'
import { DEMO_DISCLAIMER } from '@aquaindex/shared'
import { client, addr, D, ser } from './chain'
import { prisma } from './db'
import { indexOverview, listIndices } from './nav-engine'
import { rebalanceView } from './rebalance-engine'
import { parseStrategy, quoteStrategy, navReference } from './pricing-engine'
import { startIndexer } from './indexer'
import { aquaAbi, aquaIndexStrategyManagerAbi, erc20Abiish, indexShareAbi } from './abis-local'

const app = Fastify({ logger: { level: 'info' } })
await app.register(cors, { origin: true })

app.setErrorHandler((err: Error & { statusCode?: number }, _req, reply) => {
  reply.status(err.statusCode ?? 500).send({ error: err.message.split('\n')[0] })
})

const addrSchema = z.string().refine((s) => isAddress(s), 'invalid address')
const hashSchema = z.string().refine((s) => isHex(s) && s.length === 66, 'invalid bytes32')

app.get('/health', async () => {
  const block = await client.getBlockNumber()
  const st = await prisma.indexerState.findUnique({ where: { id: 'main' } })
  return { ok: true, chainId: client.chain.id, head: block.toString(), indexedTo: st?.lastBlock.toString() ?? null }
})

app.get('/api/deployment', async () => ({ ...D, disclaimer: DEMO_DISCLAIMER, onChainSource: 'all values below are read live from Sepolia; nothing here is simulated' }))

app.get('/api/indices', async () => ser(await listIndices()))

app.get('/api/indices/:id', async (req) => {
  const id = z.coerce.number().int().positive().parse((req.params as { id: string }).id)
  return ser(await indexOverview(id))
})

app.get('/api/indices/:id/nav-history', async (req) => {
  const id = z.coerce.number().int().positive().parse((req.params as { id: string }).id)
  const pts = await prisma.navPoint.findMany({ where: { indexId: id }, orderBy: { blockNumber: 'asc' } })
  return ser(pts.map((p) => ({ epoch: p.epoch, navPerShare: p.navPerShare, totalNav: p.totalNav, supply: p.supply, timestamp: p.timestamp, txHash: p.txHash })))
})

app.get('/api/indices/:id/rebalance', async (req) => {
  const id = z.coerce.number().int().positive().parse((req.params as { id: string }).id)
  return rebalanceView(id)
})

app.get('/api/indices/:id/activity', async (req) => {
  const id = z.coerce.number().int().positive().parse((req.params as { id: string }).id)
  const evs = await prisma.chainEvent.findMany({ where: { indexId: id }, orderBy: { blockNumber: 'desc' }, take: 100 })
  return ser(evs)
})

app.get('/api/portfolio/:address', async (req) => {
  const user = addrSchema.parse((req.params as { address: string }).address) as Address
  const indices = await listIndices()
  const positions = await Promise.all(
    indices.map(async (ix) => {
      const bal = await client.readContract({ address: ix.share as Address, abi: indexShareAbi, functionName: 'balanceOf', args: [user] })
      const nps = ix.nav ? BigInt(ix.nav.navPerShare) : 0n
      const value = (bal * nps) / 10n ** 18n
      const sub = await prisma.chainEvent.findMany({ where: { kind: 'Subscribed', actor: user.toLowerCase(), indexId: ix.indexId } })
      const subLc = await prisma.chainEvent.findMany({ where: { kind: 'Subscribed', indexId: ix.indexId } })
      const mine = [...sub, ...subLc.filter((e) => String(e.actor).toLowerCase() === user.toLowerCase())]
      const uniq = new Map(mine.map((e) => [e.id, e]))
      let invested = 0n
      for (const e of uniq.values()) invested += BigInt((e.data as { amountIn: string }).amountIn)
      return { indexId: ix.indexId, symbol: ix.symbol, shares: bal.toString(), navPerShare: nps.toString(), value: value.toString(), investedUsdc: invested.toString() }
    })
  )
  const usdcBal = await client.readContract({ address: addr('usdc'), abi: erc20Abiish, functionName: 'balanceOf', args: [user] })
  const events = await prisma.chainEvent.findMany({ where: { actor: { in: [user, user.toLowerCase()] } }, orderBy: { blockNumber: 'desc' }, take: 100 })
  return ser({ address: user, usdc: usdcBal, positions, activity: events })
})

app.get('/api/strategies', async (req) => {
  const qs = z.object({ maker: addrSchema.optional() }).parse(req.query)
  const rows = await prisma.strategy.findMany({ orderBy: { blockNumber: 'desc' }, take: 200 })
  const items = []
  for (const r of rows) {
    if (qs.maker && r.maker.toLowerCase() !== qs.maker.toLowerCase()) continue
    const p = parseStrategy(r.orderData as Hex)
    let balances: { tokenA: string; tokenB: string } | null = null
    try {
      const [a, b] = await Promise.all([
        client.readContract({ address: addr('aqua'), abi: aquaAbi, functionName: 'rawBalances', args: [r.maker as Address, addr('router'), r.hash as Hex, p.tokenA] }),
        client.readContract({ address: addr('aqua'), abi: aquaAbi, functionName: 'rawBalances', args: [r.maker as Address, addr('router'), r.hash as Hex, p.tokenB] })
      ])
      balances = { tokenA: a[0].toString(), tokenB: b[0].toString() }
    } catch {
      /* ignore */
    }
    const trades = await prisma.trade.count({ where: { strategyHash: r.hash } })
    items.push({
      hash: r.hash,
      orderData: r.orderData,
      maker: r.maker,
      shippedAt: r.shippedAt,
      shippedTx: r.shippedTx,
      docked: r.docked,
      tokenA: p.tokenA,
      tokenB: p.tokenB,
      isIndexStrategy: p.isIndexStrategy,
      instructions: p.instructions,
      decodeError: p.decodeError,
      virtualBalances: balances,
      trades
    })
  }
  return ser(items)
})

app.get('/api/strategies/:hash/trades', async (req) => {
  const h = hashSchema.parse((req.params as { hash: string }).hash)
  return ser(await prisma.trade.findMany({ where: { strategyHash: h }, orderBy: { blockNumber: 'desc' }, take: 100 }))
})

app.get('/api/trades', async () => ser(await prisma.trade.findMany({ orderBy: { blockNumber: 'desc' }, take: 100 })))

const quoteSchema = z.object({
  strategy: hashSchema,
  tokenIn: addrSchema,
  amount: z.string().regex(/^\d+$/),
  exactIn: z.coerce.boolean().default(true),
  taker: addrSchema
})
app.get('/api/quote', async (req) => {
  const q = quoteSchema.parse(req.query)
  const res = await quoteStrategy({ strategyHash: q.strategy as Hex, tokenIn: q.tokenIn as Address, amount: BigInt(q.amount), exactIn: q.exactIn, taker: q.taker as Address })
  // compare against the NAV reference for display (quote asset per share)
  let navRef: number | null = null
  let premiumPct: number | null = null
  try {
    const s = await prisma.strategy.findUnique({ where: { hash: q.strategy } })
    const p = parseStrategy(s!.orderData as Hex)
    const nav = p.instructions?.find((i) => i.opcode === 0xe1)?.args as { indexId: string; quoteToken: string } | undefined
    if (nav && res.ok) {
      navRef = await navReference(Number(nav.indexId), nav.quoteToken as Address)
      const sharesPerQuote = res.tokenOut.toLowerCase() !== nav.quoteToken.toLowerCase() ? res.priceOutPerIn : 1 / res.priceOutPerIn
      const quotePerShare = 1 / sharesPerQuote
      premiumPct = (quotePerShare / navRef - 1) * 100
    }
  } catch {
    /* NAV reference optional */
  }
  return { ...res, navReferenceQuotePerShare: navRef, premiumDiscountPct: premiumPct }
})

/** Authoritative order building: delegates to the on-chain AquaIndexStrategyManager (pure) so UI/SDK/chain cannot drift. */
app.post('/api/strategy/build', async (req) => {
  const body = z.object({ params: z.record(z.any()) }).parse(req.body)
  const p = body.params as Record<string, string | number | boolean>
  const tuple = [
    p.kind, p.maker, p.navSource, BigInt(p.indexId as string), p.indexToken, p.quoteToken, p.expiry, BigInt(p.salt as string), p.maxNavAge,
    BigInt(p.minEpoch as string), p.maxNavDeviationBps, p.premiumBps, p.maxPremiumBps, p.maxDiscountBps, p.spreadBps, p.feeBps, p.targetShareBps,
    p.maxSkewBps, p.slopeBps, p.maxAdjustBps, BigInt(p.maxAmountIn as string), BigInt(p.maxAmountOut as string), BigInt(p.minLiquidityOut as string),
    p.capabilityRegistry, p.capabilityId
  ]
  const names = ['kind','maker','navSource','indexId','indexToken','quoteToken','expiry','salt','maxNavAge','minEpoch','maxNavDeviationBps','premiumBps','maxPremiumBps','maxDiscountBps','spreadBps','feeBps','targetShareBps','maxSkewBps','slopeBps','maxAdjustBps','maxAmountIn','maxAmountOut','minLiquidityOut','capabilityRegistry','capabilityId']
  const struct = Object.fromEntries(names.map((n, i) => [n, tuple[i]]))
  const [order, hash] = await client.readContract({ address: addr('strategyManager'), abi: aquaIndexStrategyManagerAbi, functionName: 'buildOrder', args: [struct as never] })
  const parsed = parseStrategy(encodeAbiParameters([{ type: 'tuple', components: [{ name: 'maker', type: 'address' }, { name: 'traits', type: 'uint256' }, { name: 'data', type: 'bytes' }] }], [order as never]))
  return ser({ order, hash, instructions: parsed.instructions, source: 'AquaIndexStrategyManager.buildOrder (on-chain, pure)' })
})

app.get('/api/prices', async () => {
  const symbols = ['mBTC', 'mETH', 'mSOL', 'mLINK', 'mUNI', 'usdc']
  const { navOracleAbi } = await import('./abis-local')
  const out = await Promise.all(
    symbols.map(async (s) => {
      const a = D[s] as Address
      const [price, updatedAt] = await client.readContract({ address: addr('oracle'), abi: navOracleAbi, functionName: 'priceData', args: [a] })
      return { symbol: s, asset: a, price: price.toString(), updatedAt: Number(updatedAt) }
    })
  )
  return out
})

const port = Number(process.env.PORT ?? 4001)
const start = BigInt(process.env.START_BLOCK ?? '12079000')
if (process.env.DISABLE_INDEXER !== '1') startIndexer(start)
await app.listen({ port, host: '0.0.0.0' })
