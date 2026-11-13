import type { instructions } from '@1inch/swap-vm-sdk'

export type IArgsData = instructions.IArgsData
export type IArgsCoder<T> = instructions.IArgsCoder<T>
export type IOpcode<T extends IArgsData = IArgsData> = instructions.IOpcode<T>
export type IInstruction<T extends IArgsData = IArgsData> = instructions.IInstruction<T>

/** `Opcode` is not exported by @1inch/swap-vm-sdk@0.5.0, so this is a local implementation of its `IOpcode` contract. */
export class Opcode<T extends IArgsData> implements IOpcode<T> {
  constructor(public readonly id: symbol, public readonly coder: IArgsCoder<T>) {}

  argsCoder(): IArgsCoder<T> {
    return this.coder
  }

  createIx(args: T): IInstruction<T> {
    const opcode = this
    return {
      args,
      opcode,
      toJSON: () => ({ id: String(opcode.id.description), args: args.toJSON() })
    }
  }
}
