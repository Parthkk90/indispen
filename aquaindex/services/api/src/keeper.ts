import { createWalletClient, http, type Hex } from 'viem'
import { privateKeyToAccount } from 'viem/accounts'
import { sepolia } from 'viem/chains'
import { client, addr, RPC } from './chain'
import { navOracleAbi, indexRegistryAbi, indexShareAbi } from './abis-local'

/**
 * NAV keeper: republishes the on-chain NAV snapshot when it is older than KEEPER_MAX_AGE seconds.
 * The keeper cannot choose a NAV: `publishNav` recomputes it on-chain from vault holdings x oracle prices.
 * Needs NAV_PUBLISHER_ROLE. Key comes from KEEPER_KEY (never commit it).
 */
const key = process.env.KEEPER_KEY as Hex | undefined
if (!key) throw new Error('KEEPER_KEY is required')
const maxAge = Number(process.env.KEEPER_MAX_AGE ?? 600)
const indexId = BigInt(process.env.KEEPER_INDEX_ID ?? '1')
const account = privateKeyToAccount(key)
const wallet = createWalletClient({ account, chain: sepolia, transport: http(RPC) })

async function tick() {
  const snap = await client.readContract({ address: addr('oracle'), abi: navOracleAbi, functionName: 'navSnapshot', args: [indexId] })
  const age = Math.floor(Date.now() / 1000) - Number(snap.updatedAt)
  // also republish when share supply moved since the snapshot (subscription/redemption): the on-chain NAV guard
  // rejects trades once |navPerShare - totalNav/liveSupply| exceeds the strategy's deviation limit
  const share = await client.readContract({ address: addr('registry'), abi: indexRegistryAbi, functionName: 'shareOf', args: [indexId] })
  const supply = await client.readContract({ address: share, abi: indexShareAbi, functionName: 'totalSupply' })
  const supplyMoved = supply !== snap.supplyRef
  if (snap.updatedAt !== 0 && age < maxAge && !supplyMoved) return console.log(`[keeper] NAV fresh (${age}s), supply unchanged`)
  console.log(`[keeper] republishing (age ${age}s, supply moved: ${supplyMoved})`)
  const hash = await wallet.writeContract({ address: addr('oracle'), abi: navOracleAbi, functionName: 'publishNav', args: [indexId], gas: 400_000n })
  console.log('[keeper] published NAV', hash)
}
const once = process.argv.includes('--once')
await tick()
if (!once) setInterval(() => tick().catch((e) => console.error('[keeper]', e.message)), Number(process.env.KEEPER_POLL ?? 60) * 1000)
