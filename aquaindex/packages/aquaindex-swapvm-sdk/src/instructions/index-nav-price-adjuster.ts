import { Opcode, type IArgsData } from '../opcode'
import { IndexNavPriceCoder } from '../coders/index-nav-price-coder'

export const NAV_PRICE_MODE_SET = 0
export const NAV_PRICE_MODE_CAP = 1

export interface IndexNavPriceAdjusterParams {
  navSource: string
  indexId: bigint
  quoteToken: string
  premiumBps: number
  maxPremiumBps: number
  maxDiscountBps: number
  spreadBps: number
  feeBps: number
  mode: 0 | 1
}

/**
 * INDEX_NAV_PRICE_ADJUSTER_XD (0xe1). Args (59 bytes):
 * navSource:20 indexId:8 quoteToken:20 premiumBps:int16 maxPremiumBps:2 maxDiscountBps:2 spreadBps:2 feeBps:2 mode:1
 * Validation mirrors the Solidity builder (`validate`).
 */
export class IndexNavPriceAdjusterArgs implements IArgsData, IndexNavPriceAdjusterParams {
  static readonly LENGTH = 59
  static readonly CODER = new IndexNavPriceCoder()

  readonly navSource: string
  readonly indexId: bigint
  readonly quoteToken: string
  readonly premiumBps: number
  readonly maxPremiumBps: number
  readonly maxDiscountBps: number
  readonly spreadBps: number
  readonly feeBps: number
  readonly mode: 0 | 1

  constructor(p: IndexNavPriceAdjusterParams) {
    if (p.mode !== 0 && p.mode !== 1) throw new Error('invalid mode')
    if (p.maxPremiumBps >= 10_000 || p.maxDiscountBps >= 10_000) throw new Error('invalid bounds')
    if (p.premiumBps > p.maxPremiumBps || p.premiumBps < -p.maxDiscountBps) {
      throw new Error(`premium ${p.premiumBps} bps outside [-${p.maxDiscountBps}, ${p.maxPremiumBps}]`)
    }
    if (p.spreadBps + p.feeBps >= 10_000) throw new Error('spread + fee must be < 100%')
    Object.assign(this, p)
    this.navSource = p.navSource
    this.indexId = p.indexId
    this.quoteToken = p.quoteToken
    this.premiumBps = p.premiumBps
    this.maxPremiumBps = p.maxPremiumBps
    this.maxDiscountBps = p.maxDiscountBps
    this.spreadBps = p.spreadBps
    this.feeBps = p.feeBps
    this.mode = p.mode
  }

  toJSON(): Record<string, unknown> {
    return { ...this, indexId: this.indexId.toString() } as unknown as Record<string, unknown>
  }
}

export const indexNavPriceAdjusterXD = new Opcode(Symbol('AquaIndex.IndexNavPriceAdjuster'), IndexNavPriceAdjusterArgs.CODER)
