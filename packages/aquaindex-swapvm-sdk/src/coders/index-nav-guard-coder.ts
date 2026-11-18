import type { HexString } from '@1inch/sdk-core'
import type { IArgsCoder } from '../opcode'
import { Reader, Writer } from '../bytes'
import { IndexNavGuardArgs } from '../instructions/index-nav-guard'

export class IndexNavGuardCoder implements IArgsCoder<IndexNavGuardArgs> {
  encode(a: IndexNavGuardArgs): HexString {
    return new Writer().address(a.navSource).uint(a.indexId, 8).uint(a.maxNavAge, 4).uint(a.minEpoch, 8).uint(a.maxDeviationBps, 2).toHexString()
  }

  decode(data: HexString): IndexNavGuardArgs {
    const r = new Reader(data, IndexNavGuardArgs.LENGTH)
    const out = new IndexNavGuardArgs(r.address(), r.uint(8), Number(r.uint(4)), r.uint(8), Number(r.uint(2)))
    r.done()
    return out
  }
}
