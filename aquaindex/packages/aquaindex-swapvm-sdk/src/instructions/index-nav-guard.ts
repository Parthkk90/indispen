import { Opcode, type IArgsData } from '../opcode'
import { IndexNavGuardCoder } from '../coders/index-nav-guard-coder'
import { BPS } from '../bytes'

/** INDEX_NAV_GUARD_XD (0xe0). Args (42 bytes): navSource:20 indexId:8 maxNavAge:4 minEpoch:8 maxDeviationBps:2 */
export class IndexNavGuardArgs implements IArgsData {
  static readonly LENGTH = 42
  static readonly CODER = new IndexNavGuardCoder()

  constructor(
    public readonly navSource: string,
    public readonly indexId: bigint,
    public readonly maxNavAge: number,
    public readonly minEpoch: bigint,
    public readonly maxDeviationBps: number
  ) {
    if (BigInt(maxDeviationBps) > BPS) throw new Error('maxDeviationBps must be <= 10000')
  }

  toJSON(): Record<string, unknown> {
    return { ...this, indexId: this.indexId.toString(), minEpoch: this.minEpoch.toString() } as unknown as Record<string, unknown>
  }
}

export const indexNavGuardXD = new Opcode(Symbol('AquaIndex.IndexNavGuard'), IndexNavGuardArgs.CODER)
