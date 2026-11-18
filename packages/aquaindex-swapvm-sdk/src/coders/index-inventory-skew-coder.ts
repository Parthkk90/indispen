import type { HexString } from '@1inch/sdk-core'
import type { IArgsCoder } from '../opcode'
import { Reader, Writer } from '../bytes'
import { IndexInventorySkewArgs } from '../instructions/index-inventory-skew'

export class IndexInventorySkewCoder implements IArgsCoder<IndexInventorySkewArgs> {
  encode(a: IndexInventorySkewArgs): HexString {
    return new Writer()
      .address(a.navSource)
      .uint(a.indexId, 8)
      .address(a.quoteToken)
      .uint(a.targetShareBps, 2)
      .uint(a.maxSkewBps, 2)
      .uint(a.slopeBps, 2)
      .uint(a.maxAdjustBps, 2)
      .toHexString()
  }

  decode(data: HexString): IndexInventorySkewArgs {
    const r = new Reader(data, IndexInventorySkewArgs.LENGTH)
    const out = new IndexInventorySkewArgs({
      navSource: r.address(),
      indexId: r.uint(8),
      quoteToken: r.address(),
      targetShareBps: Number(r.uint(2)),
      maxSkewBps: Number(r.uint(2)),
      slopeBps: Number(r.uint(2)),
      maxAdjustBps: Number(r.uint(2))
    })
    r.done()
    return out
  }
}
