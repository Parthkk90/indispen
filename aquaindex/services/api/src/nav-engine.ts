import { erc20Abiish, navOracleAbi, indexRegistryAbi, indexVaultAbi, indexShareAbi } from './abis-local'
import { client, addr, ZERO } from './chain'
import { formatUnits, type Address } from 'viem'

export interface Holding {
  asset: Address
  symbol: string
  decimals: number
  balance: string
  price: string | null
  priceUpdatedAt: number | null
  value: string | null // 1e18 USD
  weightBps: number | null
  targetWeightBps: number
  isCash: boolean
}

const q = (v: bigint) => v.toString()

/** Pull-based NAV engine: everything is read from chain (vault ledger x oracle prices); nothing is trusted from a backend feed. */
export async function indexOverview(indexId: number) {
  const id = BigInt(indexId)
  const registry = addr('registry')
  const oracle = addr('oracle')
  const info = await client.readContract({ address: registry, abi: indexRegistryAbi, functionName: 'getIndex', args: [id] })
  const [constituents, weights] = await client.readContract({ address: registry, abi: indexRegistryAbi, functionName: 'constituentsOf', args: [id] })
  const assets = await client.readContract({ address: info.vault, abi: indexVaultAbi, functionName: 'assets' })
  const quoteAsset = await client.readContract({ address: registry, abi: indexRegistryAbi, functionName: 'quoteAsset' })
  const supply = await client.readContract({ address: info.share, abi: indexShareAbi, functionName: 'totalSupply' })
  const backed = await client.readContract({ address: info.vault, abi: indexVaultAbi, functionName: 'verifyBacking' })
  const snap = await client.readContract({ address: oracle, abi: navOracleAbi, functionName: 'navSnapshot', args: [id] })
  const tradable = await client.readContract({ address: oracle, abi: navOracleAbi, functionName: 'isTradable', args: [id] })

  let nav: { totalNav: bigint; navPerShare: bigint } | null = null
  let navError: string | null = null
  try {
    const [totalNav, , navPerShare] = await client.readContract({ address: oracle, abi: navOracleAbi, functionName: 'computeNav', args: [id] })
    nav = { totalNav, navPerShare }
  } catch (e) {
    navError = (e as Error).message.split('\n')[0]
  }

  const holdings: Holding[] = await Promise.all(
    assets.map(async (a): Promise<Holding> => {
      const [balance, symbol, decimals, pd] = await Promise.all([
        client.readContract({ address: info.vault, abi: indexVaultAbi, functionName: 'holdings', args: [a] }),
        client.readContract({ address: a, abi: erc20Abiish, functionName: 'symbol' }),
        client.readContract({ address: a, abi: erc20Abiish, functionName: 'decimals' }),
        client.readContract({ address: oracle, abi: navOracleAbi, functionName: 'priceData', args: [a] })
      ])
      const price = pd[0]
      const fresh = price !== 0n
      const value = fresh ? (balance * price) / 10n ** BigInt(decimals) : null
      const idx = constituents.findIndex((c) => c.toLowerCase() === a.toLowerCase())
      return {
        asset: a,
        symbol,
        decimals,
        balance: q(balance),
        price: fresh ? q(price) : null,
        priceUpdatedAt: fresh ? Number(pd[1]) : null,
        value: value === null ? null : q(value),
        weightBps: null,
        targetWeightBps: idx >= 0 ? weights[idx] : 0,
        isCash: a.toLowerCase() === quoteAsset.toLowerCase()
      }
    })
  )
  const total = nav?.totalNav ?? 0n
  for (const h of holdings) h.weightBps = total > 0n && h.value ? Number((BigInt(h.value) * 10_000n) / total) : null

  const now = Math.floor(Date.now() / 1000)
  return {
    indexId,
    name: info.name,
    symbol: info.symbol,
    metadataURI: info.metadataURI,
    status: ['NONE', 'ACTIVE', 'PAUSED', 'RETIRED'][info.status],
    methodologyVersion: info.methodologyVersion,
    vault: info.vault,
    share: info.share,
    quoteAsset,
    supply: q(supply),
    initialNavPerShare: q(info.initialNavPerShare),
    nav: nav ? { totalNav: q(nav.totalNav), navPerShare: q(nav.navPerShare), formatted: formatUnits(nav.navPerShare, 18) } : null,
    navError,
    snapshot: {
      navPerShare: q(snap.navPerShare),
      totalNav: q(snap.totalNav),
      supplyRef: q(snap.supplyRef),
      epoch: Number(snap.updatedAt) === 0 ? 0 : Number(snap.epoch),
      updatedAt: Number(snap.updatedAt),
      ageSeconds: snap.updatedAt === 0 ? null : now - Number(snap.updatedAt)
    },
    tradable,
    backing: { verified: backed, source: 'IndexVault.verifyBacking (ledger <= token balance for every asset)' },
    holdings,
    constituents: constituents.map((c, i) => ({ asset: c, weightBps: weights[i] }))
  }
}

export async function listIndices() {
  const count = await client.readContract({ address: addr('registry'), abi: indexRegistryAbi, functionName: 'indexCount' })
  const out = []
  for (let i = 1n; i <= count; i++) out.push(await indexOverview(Number(i)))
  return out
}

export { ZERO }
