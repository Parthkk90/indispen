import { HexString } from '@1inch/sdk-core'

/** Strict big-endian packed writer/reader used by every AquaIndex args coder (mirrors Solidity `abi.encodePacked`). */
export class Writer {
  private hex = ''

  uint(value: bigint | number, bytes: number): this {
    const v = BigInt(value)
    if (v < 0n || v >= 1n << BigInt(bytes * 8)) throw new Error(`value ${v} does not fit uint${bytes * 8}`)
    this.hex += v.toString(16).padStart(bytes * 2, '0')
    return this
  }

  int(value: bigint | number, bytes: number): this {
    const v = BigInt(value)
    const bits = BigInt(bytes * 8)
    if (v < -(1n << (bits - 1n)) || v >= 1n << (bits - 1n)) throw new Error(`value ${v} does not fit int${bits}`)
    return this.uint(v < 0n ? v + (1n << bits) : v, bytes)
  }

  address(a: string): this {
    if (!/^0x[0-9a-fA-F]{40}$/.test(a)) throw new Error(`invalid address ${a}`)
    this.hex += a.slice(2).toLowerCase()
    return this
  }

  bytes32(b: string): this {
    if (!/^0x[0-9a-fA-F]{64}$/.test(b)) throw new Error(`invalid bytes32 ${b}`)
    this.hex += b.slice(2).toLowerCase()
    return this
  }

  toHexString(): HexString {
    return new HexString('0x' + this.hex)
  }
}

export class Reader {
  private pos = 0
  private readonly hex: string

  constructor(data: HexString | string, private readonly expectedLength: number) {
    const s = data.toString()
    this.hex = s.startsWith('0x') ? s.slice(2) : s
    if (this.hex.length !== expectedLength * 2) {
      throw new Error(`invalid args length: expected ${expectedLength} bytes, got ${this.hex.length / 2}`)
    }
  }

  private take(bytes: number): string {
    const out = this.hex.slice(this.pos, this.pos + bytes * 2)
    this.pos += bytes * 2
    return out
  }

  uint(bytes: number): bigint {
    return BigInt('0x' + this.take(bytes))
  }

  int(bytes: number): bigint {
    const bits = BigInt(bytes * 8)
    const v = this.uint(bytes)
    return v >= 1n << (bits - 1n) ? v - (1n << bits) : v
  }

  address(): string {
    return '0x' + this.take(20)
  }

  bytes32(): string {
    return '0x' + this.take(32)
  }

  done(): void {
    if (this.pos !== this.expectedLength * 2) throw new Error('args not fully consumed')
  }
}

export const BPS = 10_000n
