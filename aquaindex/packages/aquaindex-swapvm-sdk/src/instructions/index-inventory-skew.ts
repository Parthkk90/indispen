import { Opcode, type IArgsData } from '../opcode'
import { IndexInventorySkewCoder } from '../coders/index-inventory-skew-coder'

export interface IndexInventorySkewParams {
  navSource: string
  indexId: bigint
  quoteToken: string
  targetShareBps: number
  maxSkewBps: number
  slopeBps: number
  maxAdjustBps: number
}

/** INDEX_INVENTORY_SKEW_XD (0xe2). Args (56 bytes): navSource:20 indexId:8 quoteToken:20 targetShareBps:2 maxSkewBps:2 slopeBps:2 maxAdjustBps:2 */
export class IndexInventorySkewArgs implements IArgsData, IndexInventorySkewParams {
  static readonly LENGTH = 56
  static readonly CODER = new IndexInventorySkewCoder()

  readonly navSource: string
  readonly indexId: bigint
  readonly quoteToken: string
  readonly targetShareBps: number
  readonly maxSkewBps: number
  readonly slopeBps: number
  readonly maxAdjustBps: number

  constructor(p: IndexInventorySkewParams) {
    if (p.targetShareBps > 10_000 || p.maxSkewBps > 10_000) throw new Error('bps out of range')
    if (p.maxAdjustBps > 5_000) throw new Error('maxAdjustBps must be <= 5000')
    this.navSource = p.navSource
    this.indexId = p.indexId
    this.quoteToken = p.quoteToken
    this.targetShareBps = p.targetShareBps
    this.maxSkewBps = p.maxSkewBps
    this.slopeBps = p.slopeBps
    this.maxAdjustBps = p.maxAdjustBps
  }

  toJSON(): Record<string, unknown> {
    return { ...this, indexId: this.indexId.toString() } as unknown as Record<string, unknown>
  }
}

export const indexInventorySkewXD = new Opcode(Symbol('AquaIndex.IndexInventorySkew'), IndexInventorySkewArgs.CODER)
