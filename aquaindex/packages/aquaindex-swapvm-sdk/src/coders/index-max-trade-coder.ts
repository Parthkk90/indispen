import type { HexString } from '@1inch/sdk-core'
import type { IArgsCoder } from '../opcode'
import { Reader, Writer } from '../bytes'
import { IndexMaxTradeArgs } from '../instructions/index-max-trade'

export class IndexMaxTradeCoder implements IArgsCoder<IndexMaxTradeArgs> {
  encode(a: IndexMaxTradeArgs): HexString {
    return new Writer()
      .address(a.navSource)
      .uint(a.indexId, 8)
      .uint(a.maxAmountIn, 16)
      .uint(a.maxAmountOut, 16)
      .uint(a.minLiquidityOut, 16)
      .toHexString()
  }

  decode(data: HexString): IndexMaxTradeArgs {
    const r = new Reader(data, IndexMaxTradeArgs.LENGTH)
    const out = new IndexMaxTradeArgs(r.address(), r.uint(8), r.uint(16), r.uint(16), r.uint(16))
    r.done()
    return out
  }
}
