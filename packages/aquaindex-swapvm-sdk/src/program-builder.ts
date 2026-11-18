import { ProgramBuilder, instructions } from '@1inch/swap-vm-sdk'

const { controls, xycSwap } = instructions
import { aquaIndexInstructions } from './instruction-set'
import { IndexNavGuardArgs, indexNavGuardXD } from './instructions/index-nav-guard'
import { IndexNavPriceAdjusterArgs, indexNavPriceAdjusterXD } from './instructions/index-nav-price-adjuster'
import type { IndexNavPriceAdjusterParams } from './instructions/index-nav-price-adjuster'
import { IndexInventorySkewArgs, indexInventorySkewXD } from './instructions/index-inventory-skew'
import type { IndexInventorySkewParams } from './instructions/index-inventory-skew'
import { IndexMaxTradeArgs, indexMaxTradeXD } from './instructions/index-max-trade'
import { IndexCapabilityGuardArgs, indexCapabilityGuardXD } from './instructions/index-capability-guard'

/**
 * Program builder bound to the AquaIndexSwapVMRouter opcode table. Do NOT use `AquaProgramBuilder` for these programs:
 * its table targets the deployed 1inch router. Unknown / wrong-set opcodes throw in `add()` and `decode()`.
 */
export class AquaIndexProgramBuilder extends ProgramBuilder {
  constructor() {
    super(aquaIndexInstructions)
  }

  salt(salt: bigint): this {
    return this.add(controls.salt.createIx(controls.SaltArgs.fromUint64(salt)))
  }

  deadline(deadline: bigint): this {
    return this.add(controls.deadline.createIx(new controls.DeadlineArgs(deadline)))
  }

  xycSwap(): this {
    return this.add(xycSwap.xycSwapXD.createIx(new xycSwap.XycSwapXDArgs()))
  }

  navGuard(a: IndexNavGuardArgs): this {
    return this.add(indexNavGuardXD.createIx(a))
  }

  navPriceAdjuster(p: IndexNavPriceAdjusterParams): this {
    return this.add(indexNavPriceAdjusterXD.createIx(new IndexNavPriceAdjusterArgs(p)))
  }

  inventorySkew(p: IndexInventorySkewParams): this {
    return this.add(indexInventorySkewXD.createIx(new IndexInventorySkewArgs(p)))
  }

  maxTrade(a: IndexMaxTradeArgs): this {
    return this.add(indexMaxTradeXD.createIx(a))
  }

  capabilityGuard(a: IndexCapabilityGuardArgs): this {
    return this.add(indexCapabilityGuardXD.createIx(a))
  }
}
