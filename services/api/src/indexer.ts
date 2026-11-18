import { parseEventLogs, type Log, type Address, type Hex } from 'viem'
import { client, addr } from './chain'
import { prisma } from './db'
import {
  aquaAbi,
  navOracleAbi,
  subscriptionManagerAbi,
  redemptionManagerAbi,
  rebalanceManagerAbi,
  aquaIndexStrategyManagerAbi
} from './abis-local'

const STATE_ID = 'main'
const CHUNK = 5_000n

const sources = () => [
  { address: addr('aqua'), abi: aquaAbi },
  { address: addr('oracle'), abi: navOracleAbi },
  { address: addr('subscriptionManager'), abi: subscriptionManagerAbi },
  { address: addr('redemptionManager'), abi: redemptionManagerAbi },
  { address: addr('rebalanceManager'), abi: rebalanceManagerAbi },
  { address: addr('strategyManager'), abi: aquaIndexStrategyManagerAbi }
]

const blockTimes = new Map<bigint, Date>()
async function tsOf(bn: bigint) {
  let t = blockTimes.get(bn)
  if (!t) {
    const b = await client.getBlock({ blockNumber: bn })
    t = new Date(Number(b.timestamp) * 1000)
    blockTimes.set(bn, t)
  }
  return t
}

type Decoded = { eventName: string; args: Record<string, unknown>; address: Address; blockNumber: bigint; transactionHash: Hex; logIndex: number }

const j = (v: unknown) => JSON.parse(JSON.stringify(v, (_k, x) => (typeof x === 'bigint' ? x.toString() : x)))

async function handle(ev: Decoded) {
  const router = addr('router').toLowerCase()
  const id = `${ev.transactionHash}:${ev.logIndex}`
  const timestamp = await tsOf(ev.blockNumber)
  const a = ev.args as Record<string, any>
  const isAqua = ev.address.toLowerCase() === addr('aqua').toLowerCase()
  // Aqua events are keyed by `app`; only the AquaIndex router's strategies are relevant here
  if (isAqua && String(a.app).toLowerCase() !== router) return

  const indexId = a.indexId !== undefined ? Number(a.indexId) : null
  const actor = (a.user ?? a.maker ?? null) as string | null
  await prisma.chainEvent.upsert({
    where: { id },
    update: {},
    create: { id, kind: ev.eventName, address: ev.address, blockNumber: ev.blockNumber, timestamp, txHash: ev.transactionHash, indexId, actor, data: j(a) }
  })

  switch (ev.eventName) {
    case 'NavPublished':
      await prisma.navPoint.upsert({
        where: { id },
        update: {},
        create: { id, indexId: Number(a.indexId), navPerShare: String(a.navPerShare), totalNav: String(a.totalNav), supply: String(a.supply), epoch: Number(a.epoch), blockNumber: ev.blockNumber, timestamp, txHash: ev.transactionHash }
      })
      break
    case 'Shipped':
      await prisma.strategy.upsert({
        where: { hash: a.strategyHash },
        update: { docked: false },
        create: { hash: a.strategyHash, maker: a.maker, orderData: a.strategy, shippedAt: timestamp, shippedTx: ev.transactionHash, blockNumber: ev.blockNumber }
      })
      break
    case 'Docked':
      await prisma.strategy.updateMany({ where: { hash: a.strategyHash }, data: { docked: true, dockedTx: ev.transactionHash } })
      break
  }
}

/** Pair Aqua Pulled (tokenOut) + Pushed (tokenIn) of the same tx/strategy into Trade rows. */
async function deriveTrades(logs: Decoded[]) {
  const router = addr('router').toLowerCase()
  const byKey = new Map<string, { pulled?: Record<string, any>; pushed?: Record<string, any>; ev: Decoded }>()
  for (const ev of logs) {
    if (ev.address.toLowerCase() !== addr('aqua').toLowerCase()) continue
    if (ev.eventName !== 'Pulled' && ev.eventName !== 'Pushed') continue
    const a = ev.args as Record<string, any>
    if (String(a.app).toLowerCase() !== router) continue
    const key = `${ev.transactionHash}:${a.strategyHash}`
    const e = byKey.get(key) ?? { ev }
    if (ev.eventName === 'Pulled') e.pulled = a
    else e.pushed = a
    byKey.set(key, e)
  }
  for (const [id, e] of byKey) {
    if (!e.pulled || !e.pushed) continue
    await prisma.trade.upsert({
      where: { id },
      update: {},
      create: {
        id,
        txHash: e.ev.transactionHash,
        blockNumber: e.ev.blockNumber,
        timestamp: await tsOf(e.ev.blockNumber),
        maker: e.pulled.maker,
        strategyHash: e.pulled.strategyHash,
        tokenIn: e.pushed.token,
        tokenOut: e.pulled.token,
        amountIn: String(e.pushed.amount),
        amountOut: String(e.pulled.amount)
      }
    })
  }
}

export async function syncOnce(startBlock: bigint) {
  const st = await prisma.indexerState.findUnique({ where: { id: STATE_ID } })
  let from = st ? st.lastBlock + 1n : startBlock
  const head = await client.getBlockNumber()
  let count = 0
  while (from <= head) {
    const to = from + CHUNK - 1n > head ? head : from + CHUNK - 1n
    const decoded: Decoded[] = []
    for (const s of sources()) {
      const raw = (await client.getLogs({ address: s.address, fromBlock: from, toBlock: to })) as Log[]
      const parsed = parseEventLogs({ abi: s.abi as any, logs: raw as any, strict: false }) as any[]
      for (const p of parsed) if (p.eventName) decoded.push(p)
    }
    decoded.sort((x, y) => (x.blockNumber === y.blockNumber ? x.logIndex - y.logIndex : x.blockNumber < y.blockNumber ? -1 : 1))
    for (const ev of decoded) await handle(ev)
    await deriveTrades(decoded)
    count += decoded.length
    await prisma.indexerState.upsert({ where: { id: STATE_ID }, update: { lastBlock: to }, create: { id: STATE_ID, lastBlock: to } })
    from = to + 1n
  }
  return { head: head.toString(), events: count }
}

export function startIndexer(startBlock: bigint, intervalMs = 15_000) {
  const loop = async () => {
    try {
      const r = await syncOnce(startBlock)
      if (r.events) console.log('[indexer]', r)
    } catch (e) {
      console.error('[indexer] error', (e as Error).message)
    }
  }
  void loop()
  return setInterval(loop, intervalMs)
}
