import { Opcode, type IArgsData } from '../opcode'
import { IndexCapabilityCoder } from '../coders/index-capability-coder'

/** INDEX_CAPABILITY_GUARD_XD (0xe4). Args (52 bytes): registry:20 capabilityId:32 */
export class IndexCapabilityGuardArgs implements IArgsData {
  static readonly LENGTH = 52
  static readonly CODER = new IndexCapabilityCoder()

  constructor(public readonly registry: string, public readonly capabilityId: string) {}

  toJSON(): Record<string, unknown> {
    return { ...this } as unknown as Record<string, unknown>
  }
}

export const indexCapabilityGuardXD = new Opcode(Symbol('AquaIndex.IndexCapabilityGuard'), IndexCapabilityGuardArgs.CODER)
