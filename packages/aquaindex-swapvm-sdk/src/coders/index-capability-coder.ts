import type { HexString } from '@1inch/sdk-core'
import type { IArgsCoder } from '../opcode'
import { Reader, Writer } from '../bytes'
import { IndexCapabilityGuardArgs } from '../instructions/index-capability-guard'

export class IndexCapabilityCoder implements IArgsCoder<IndexCapabilityGuardArgs> {
  encode(a: IndexCapabilityGuardArgs): HexString {
    return new Writer().address(a.registry).bytes32(a.capabilityId).toHexString()
  }

  decode(data: HexString): IndexCapabilityGuardArgs {
    const r = new Reader(data, IndexCapabilityGuardArgs.LENGTH)
    const out = new IndexCapabilityGuardArgs(r.address(), r.bytes32())
    r.done()
    return out
  }
}
