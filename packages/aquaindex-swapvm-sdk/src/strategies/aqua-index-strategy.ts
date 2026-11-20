import { SwapVmProgram } from '@1inch/swap-vm-sdk'
import { HexString } from '@1inch/sdk-core'
import { encodeAbiParameters, keccak256, concatHex, type Hex } from 'viem'
import { AquaIndexProgramBuilder } from '../program-builder'
import { IndexNavGuardArgs } from '../instructions/index-nav-guard'
import { IndexMaxTradeArgs } from '../instructions/index-max-trade'
import { IndexCapabilityGuardArgs } from '../instructions/index-capability-guard'
import { NAV_PRICE_MODE_CAP, NAV_PRICE_MODE_SET } from '../instructions/index-nav-price-adjuster'

export enum StrategyKind {
  NAV_ANCHORED = 0, // Strategy A
  CONSERVATIVE = 1, // Strategy B
  ADAPTIVE = 2 // Strategy C
}

/** Mirrors `AquaIndexStrategyManager.Params` field for field. */
export interface AquaIndexStrategyParams {
  kind: StrategyKind
  maker: string
  navSource: string
  indexId: bigint
  indexToken: string
  quoteToken: string
  expiry: bigint
  salt: bigint
  maxNavAge: number
  minEpoch: bigint
  maxNavDeviationBps: number
  premiumBps: number
  maxPremiumBps: number
  maxDiscountBps: number
  spreadBps: number
  feeBps: number
  targetShareBps: number
  maxSkewBps: number
  slopeBps: number
  maxAdjustBps: number
  maxAmountIn: bigint
  maxAmountOut: bigint
  minLiquidityOut: bigint
  capabilityRegistry: string
  capabilityId: string
}

export const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'
export const ZERO_BYTES32 = ('0x' + '00'.repeat(32)) as Hex

/**
 * Canonical instruction order (security-critical; identical to `AquaIndexStrategyManager.buildProgram`):
 *   Deadline, Salt, NavGuard, [XYCSwap if ADAPTIVE], NavPriceAdjuster, InventorySkew, MaxTrade, [CapabilityGuard]
 * Guards that read amounts (MaxTrade, CapabilityGuard) must come AFTER the instructions that set them.
 */
export function buildStrategyProgram(p: AquaIndexStrategyParams): SwapVmProgram {
  const adaptive = p.kind === StrategyKind.ADAPTIVE
  const b = new AquaIndexProgramBuilder()
    .deadline(p.expiry)
    .salt(p.salt)
    .navGuard(new IndexNavGuardArgs(p.navSource, p.indexId, p.maxNavAge, p.minEpoch, p.maxNavDeviationBps))
  if (adaptive) b.xycSwap()
  b.navPriceAdjuster({
    navSource: p.navSource,
    indexId: p.indexId,
    quoteToken: p.quoteToken,
    premiumBps: p.premiumBps,
    maxPremiumBps: p.maxPremiumBps,
    maxDiscountBps: p.maxDiscountBps,
    spreadBps: p.spreadBps,
    feeBps: p.feeBps,
    mode: adaptive ? NAV_PRICE_MODE_CAP : NAV_PRICE_MODE_SET
  })
    .inventorySkew({
      navSource: p.navSource,
      indexId: p.indexId,
      quoteToken: p.quoteToken,
      targetShareBps: p.targetShareBps,
      maxSkewBps: p.maxSkewBps,
      slopeBps: p.slopeBps,
      maxAdjustBps: p.maxAdjustBps
    })
    .maxTrade(new IndexMaxTradeArgs(p.navSource, p.indexId, p.maxAmountIn, p.maxAmountOut, p.minLiquidityOut))
  if (p.capabilityRegistry.toLowerCase() !== ZERO_ADDRESS) {
    b.capabilityGuard(new IndexCapabilityGuardArgs(p.capabilityRegistry, p.capabilityId))
  }
  return b.build()
}

export interface AquaIndexOrder {
  maker: Hex
  traits: bigint
  data: Hex
}

// no-hook layout: every slice index = 40 (two token addresses precede the program in `order.data`)
const USE_AQUA_FLAG = 1n << 254n
const SLICE = 40n
const SLICES = (SLICE << 48n) | (SLICE << 32n) | (SLICE << 16n) | SLICE
const NO_HOOK_TRAITS = USE_AQUA_FLAG | (SLICES << 160n)

/**
 * Order exactly as `MakerTraitsLib.build` produces it on swap-vm `main` for an Aqua strategy without hooks.
 * NOTE: `Order` in `@1inch/swap-vm-sdk@0.5.0` omits the leading `tokenA|tokenB` data prefix of `main`, so it is not
 * used here (see docs/upstream-integration.md).
 */
export function buildStrategyOrder(p: AquaIndexStrategyParams): { order: AquaIndexOrder; hash: Hex; program: SwapVmProgram } {
  const [a, b] = BigInt(p.indexToken) < BigInt(p.quoteToken) ? [p.indexToken, p.quoteToken] : [p.quoteToken, p.indexToken]
  const program = buildStrategyProgram(p)
  const data = concatHex([a as Hex, b as Hex, program.toString() as Hex])
  const order: AquaIndexOrder = { maker: p.maker as Hex, traits: NO_HOOK_TRAITS, data }
  return { order, hash: hashOrder(order), program }
}

export const ORDER_ABI = {
  type: 'tuple',
  components: [
    { name: 'maker', type: 'address' },
    { name: 'traits', type: 'uint256' },
    { name: 'data', type: 'bytes' }
  ]
} as const

export function encodeOrder(o: AquaIndexOrder): Hex {
  return encodeAbiParameters([ORDER_ABI], [o])
}

/** Aqua strategy hash == SwapVM Aqua-mode order hash == keccak256(abi.encode(order)). */
export function hashOrder(o: AquaIndexOrder): Hex {
  return keccak256(encodeOrder(o))
}

const base = (kind: StrategyKind, p: Partial<AquaIndexStrategyParams> & Pick<AquaIndexStrategyParams, 'maker' | 'navSource' | 'indexId' | 'indexToken' | 'quoteToken' | 'expiry' | 'salt'>): AquaIndexStrategyParams => ({
  kind,
  maxNavAge: 300,
  minEpoch: 1n,
  maxNavDeviationBps: 100,
  premiumBps: 0,
  maxPremiumBps: 300,
  maxDiscountBps: 300,
  spreadBps: 20,
  feeBps: 0,
  targetShareBps: 5000,
  maxSkewBps: 3000,
  slopeBps: 5000,
  maxAdjustBps: 500,
  maxAmountIn: 0n,
  maxAmountOut: 0n,
  minLiquidityOut: 0n,
  capabilityRegistry: ZERO_ADDRESS,
  capabilityId: ZERO_BYTES32,
  ...p
})

type Core = Pick<AquaIndexStrategyParams, 'maker' | 'navSource' | 'indexId' | 'indexToken' | 'quoteToken' | 'expiry' | 'salt'>

/** Strategy A: NAV-anchored index market (CB5/USDC). */
export const strategyA = (c: Core, o: Partial<AquaIndexStrategyParams> = {}) => base(StrategyKind.NAV_ANCHORED, { ...c, ...o })

/** Strategy B: conservative market maker (tight deviation, strict freshness, wide spread, small trades, less skew exposure). */
export const strategyB = (c: Core, o: Partial<AquaIndexStrategyParams> = {}) =>
  base(StrategyKind.CONSERVATIVE, {
    ...c,
    maxNavAge: 60,
    maxNavDeviationBps: 25,
    maxPremiumBps: 100,
    maxDiscountBps: 100,
    spreadBps: 60,
    maxSkewBps: 1500,
    slopeBps: 3000,
    maxAdjustBps: 200,
    maxAmountIn: 5_000_000_000n,
    ...o
  })

/** Strategy C: adaptive liquidity (XYC curve capped by the NAV price, inventory skew, size limits). */
export const strategyC = (c: Core, o: Partial<AquaIndexStrategyParams> = {}) =>
  base(StrategyKind.ADAPTIVE, { ...c, spreadBps: 30, slopeBps: 8000, maxAdjustBps: 1000, maxAmountIn: 25_000_000_000n, ...o })
