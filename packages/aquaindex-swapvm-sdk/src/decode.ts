import { HexString } from '@1inch/sdk-core'
import { IndexNavGuardArgs } from './instructions/index-nav-guard'
import { IndexNavPriceAdjusterArgs } from './instructions/index-nav-price-adjuster'
import { IndexInventorySkewArgs } from './instructions/index-inventory-skew'
import { IndexMaxTradeArgs } from './instructions/index-max-trade'
import { IndexCapabilityGuardArgs } from './instructions/index-capability-guard'

export interface DecodedInstruction {
  opcode: number
  name: string
  args: Record<string, unknown> | null
}

/** Dependency-light program decoder (no @1inch/swap-vm-sdk import) for servers: program bytes -> instruction list. */
export function decodeProgram(programHex: string): DecodedInstruction[] {
  const hex = programHex.startsWith('0x') ? programHex.slice(2) : programHex
  const out: DecodedInstruction[] = []
  let pos = 0
  while (pos < hex.length) {
    if (pos + 4 > hex.length) throw new Error('truncated instruction header')
    const opcode = parseInt(hex.slice(pos, pos + 2), 16)
    const len = parseInt(hex.slice(pos + 2, pos + 4), 16)
    pos += 4
    if (pos + len * 2 > hex.length) throw new Error('truncated instruction args')
    const args = new HexString('0x' + hex.slice(pos, pos + len * 2))
    pos += len * 2
    switch (opcode) {
      case 0x02:
        out.push({ opcode, name: 'Salt', args: { salt: BigInt('0x' + (args.toString().slice(2) || '0')).toString() } })
        break
      case 0x20:
        out.push({ opcode, name: 'Deadline', args: { deadline: BigInt(args.toString()).toString() } })
        break
      case 0x50:
        out.push({ opcode, name: 'XYCSwap', args: null })
        break
      case 0xe0:
        out.push({ opcode, name: 'INDEX_NAV_GUARD_XD', args: IndexNavGuardArgs.CODER.decode(args).toJSON() })
        break
      case 0xe1:
        out.push({ opcode, name: 'INDEX_NAV_PRICE_ADJUSTER_XD', args: IndexNavPriceAdjusterArgs.CODER.decode(args).toJSON() })
        break
      case 0xe2:
        out.push({ opcode, name: 'INDEX_INVENTORY_SKEW_XD', args: IndexInventorySkewArgs.CODER.decode(args).toJSON() })
        break
      case 0xe3:
        out.push({ opcode, name: 'INDEX_MAX_TRADE_XD', args: IndexMaxTradeArgs.CODER.decode(args).toJSON() })
        break
      case 0xe4:
        out.push({ opcode, name: 'INDEX_CAPABILITY_GUARD_XD', args: IndexCapabilityGuardArgs.CODER.decode(args).toJSON() })
        break
      default:
        throw new Error(`unknown opcode 0x${opcode.toString(16)}`)
    }
  }
  return out
}

/** Split `order.data` of a hook-free Aqua order into tokens + program. */
export function splitOrderData(data: string): { tokenA: string; tokenB: string; program: string } {
  const h = data.startsWith('0x') ? data.slice(2) : data
  return { tokenA: '0x' + h.slice(0, 40), tokenB: '0x' + h.slice(40, 80), program: '0x' + h.slice(80) }
}
