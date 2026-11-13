import { Opcode, type IArgsData } from '../opcode'
import { IndexMaxTradeCoder } from '../coders/index-max-trade-coder'

/** INDEX_MAX_TRADE_XD (0xe3). Args (76 bytes): navSource:20 indexId:8 maxAmountIn:16 maxAmountOut:16 minLiquidityOut:16 (0 = no cap) */
export class IndexMaxTradeArgs implements IArgsData {
  static readonly LENGTH = 76
  static readonly CODER = new IndexMaxTradeCoder()

  constructor(
    public readonly navSource: string,
    public readonly indexId: bigint,
    public readonly maxAmountIn: bigint,
    public readonly maxAmountOut: bigint,
    public readonly minLiquidityOut: bigint
  ) {}

  toJSON(): Record<string, unknown> {
    return {
      navSource: this.navSource,
      indexId: this.indexId.toString(),
      maxAmountIn: this.maxAmountIn.toString(),
      maxAmountOut: this.maxAmountOut.toString(),
      minLiquidityOut: this.minLiquidityOut.toString()
    }
  }
}

export const indexMaxTradeXD = new Opcode(Symbol('AquaIndex.IndexMaxTrade'), IndexMaxTradeArgs.CODER)
