import { rebalanceManagerAbi, erc20Abiish } from './abis-local'
import { client, addr } from './chain'
import type { Address } from 'viem'

export async function rebalanceView(indexId: number, minValue = 10n ** 18n) {
  const rm = addr('rebalanceManager')
  const id = BigInt(indexId)
  const [totalNav, drift] = await client.readContract({ address: rm, abi: rebalanceManagerAbi, functionName: 'drift', args: [id] })
  const proposals = await client.readContract({ address: rm, abi: rebalanceManagerAbi, functionName: 'propose', args: [id, minValue] })
  const [maxTradeBps, maxSlippageBps] = await Promise.all([
    client.readContract({ address: rm, abi: rebalanceManagerAbi, functionName: 'maxTradeBps' }),
    client.readContract({ address: rm, abi: rebalanceManagerAbi, functionName: 'maxSlippageBps' })
  ])
  const sym = async (a: Address) => client.readContract({ address: a, abi: erc20Abiish, functionName: 'symbol' })
  return {
    indexId,
    totalNav: totalNav.toString(),
    limits: { maxTradeBps, maxSlippageBps, note: 'Enforced on-chain by RebalanceManager.execute; this endpoint only proposes.' },
    drift: await Promise.all(
      drift.map(async (d) => ({
        asset: d.asset,
        symbol: await sym(d.asset),
        currentValue: d.currentValue.toString(),
        targetValue: d.targetValue.toString(),
        driftBps: Number(d.driftBps),
        deltaValue: d.deltaValue.toString(),
        deltaAmount: d.deltaAmount.toString()
      }))
    ),
    proposals: await Promise.all(
      proposals.map(async (p) => ({
        sellAsset: p.sellAsset,
        sellSymbol: await sym(p.sellAsset),
        buyAsset: p.buyAsset,
        buySymbol: await sym(p.buyAsset),
        sellValue: p.sellValue.toString(),
        sellAmount: p.sellAmount.toString()
      }))
    )
  }
}
