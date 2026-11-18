import { decodeAbiParameters, encodeAbiParameters, type Hex } from 'viem'

export const ORDER_ABI = {
  type: 'tuple',
  components: [{ name: 'maker', type: 'address' }, { name: 'traits', type: 'uint256' }, { name: 'data', type: 'bytes' }]
} as const

export type Order = { maker: `0x${string}`; traits: bigint; data: Hex }
export const decodeOrder = (h: Hex): Order => decodeAbiParameters([ORDER_ABI], h)[0] as Order
export const encodeOrder = (o: Order): Hex => encodeAbiParameters([ORDER_ABI], [o])

/** Parameter presets mirroring `strategyA/B/C` in @aquaindex/swapvm-sdk (the on-chain builder remains authoritative). */
export const PRESETS = {
  A: { label: 'A - NAV-anchored index market', kind: 0, maxNavAge: 300, maxNavDeviationBps: 100, maxPremiumBps: 300, maxDiscountBps: 300, spreadBps: 20, maxSkewBps: 3000, slopeBps: 5000, maxAdjustBps: 500, maxAmountIn: '0' },
  B: { label: 'B - Conservative market maker', kind: 1, maxNavAge: 60, maxNavDeviationBps: 25, maxPremiumBps: 100, maxDiscountBps: 100, spreadBps: 60, maxSkewBps: 1500, slopeBps: 3000, maxAdjustBps: 200, maxAmountIn: '5000000000' },
  C: { label: 'C - Adaptive liquidity (XYC curve capped by NAV)', kind: 2, maxNavAge: 300, maxNavDeviationBps: 100, maxPremiumBps: 300, maxDiscountBps: 300, spreadBps: 30, maxSkewBps: 3000, slopeBps: 8000, maxAdjustBps: 1000, maxAmountIn: '25000000000' }
} as const
