import type { HexString } from '@1inch/sdk-core'
import type { IArgsCoder } from '../opcode'
import { Reader, Writer } from '../bytes'
import { IndexNavPriceAdjusterArgs } from '../instructions/index-nav-price-adjuster'

export class IndexNavPriceCoder implements IArgsCoder<IndexNavPriceAdjusterArgs> {
  encode(a: IndexNavPriceAdjusterArgs): HexString {
    return new Writer()
      .address(a.navSource)
      .uint(a.indexId, 8)
      .address(a.quoteToken)
      .int(a.premiumBps, 2)
      .uint(a.maxPremiumBps, 2)
      .uint(a.maxDiscountBps, 2)
      .uint(a.spreadBps, 2)
      .uint(a.feeBps, 2)
      .uint(a.mode, 1)
      .toHexString()
  }

  decode(data: HexString): IndexNavPriceAdjusterArgs {
    const r = new Reader(data, IndexNavPriceAdjusterArgs.LENGTH)
    const out = new IndexNavPriceAdjusterArgs({
      navSource: r.address(),
      indexId: r.uint(8),
      quoteToken: r.address(),
      premiumBps: Number(r.int(2)),
      maxPremiumBps: Number(r.uint(2)),
      maxDiscountBps: Number(r.uint(2)),
      spreadBps: Number(r.uint(2)),
      feeBps: Number(r.uint(2)),
      mode: Number(r.uint(1)) as 0 | 1
    })
    r.done()
    return out
  }
}
