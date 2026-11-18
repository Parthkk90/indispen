import { decodeProgram as decodeLite, splitOrderData } from '../src/decode'
import { describe, expect, it } from 'vitest'
import { readFileSync, writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import { HexString } from '@1inch/sdk-core'
import { AquaProgramBuilder, instructions } from '@1inch/swap-vm-sdk'

const { controls } = instructions
import {
  AquaIndexProgramBuilder,
  IndexCapabilityGuardArgs,
  IndexInventorySkewArgs,
  IndexMaxTradeArgs,
  IndexNavGuardArgs,
  IndexNavPriceAdjusterArgs,
  OPCODE_IDS,
  StrategyKind,
  aquaIndexInstructions,
  buildStrategyOrder,
  buildStrategyProgram,
  opcodeByte,
  indexNavGuardXD,
  indexMaxTradeXD,
  indexCapabilityGuardXD,
  INSTRUCTION_SET_VERSION,
  type AquaIndexStrategyParams,
  buildTakerData
} from '../src'

const here = dirname(fileURLToPath(import.meta.url))
const golden = JSON.parse(readFileSync(join(here, 'golden.json'), 'utf8'))

const NAV = '0x2222222222222222222222222222222222222222'
const QUOTE = '0x4444444444444444444444444444444444444444'
const REG = '0x5555555555555555555555555555555555555555'

// identical to Vectors.t.sol::_params
const params = (kind: StrategyKind): AquaIndexStrategyParams => ({
  kind,
  maker: '0x1111111111111111111111111111111111111111',
  navSource: NAV,
  indexId: 7n,
  indexToken: '0x3333333333333333333333333333333333333333',
  quoteToken: QUOTE,
  expiry: 1_900_000_000n,
  salt: 42n,
  maxNavAge: 300,
  minEpoch: 3n,
  maxNavDeviationBps: 150,
  premiumBps: -125,
  maxPremiumBps: 300,
  maxDiscountBps: 250,
  spreadBps: 20,
  feeBps: 5,
  targetShareBps: 5000,
  maxSkewBps: 3000,
  slopeBps: 5000,
  maxAdjustBps: 500,
  maxAmountIn: 1_000_000n * 10n ** 6n,
  maxAmountOut: 5_000n * 10n ** 18n,
  minLiquidityOut: 10n * 10n ** 18n,
  capabilityRegistry: REG,
  capabilityId: '0x' + 'abcdef'.padStart(64, '0')
})

describe('opcode table == Solidity dispatch ids', () => {
  it('matches the numbers emitted by Foundry (golden.json)', () => {
    expect(golden.instructionSetVersion).toBe(INSTRUCTION_SET_VERSION)
    expect(OPCODE_IDS.Salt).toBe(golden.opcodes.Salt)
    expect(OPCODE_IDS.Deadline).toBe(golden.opcodes.Deadline)
    expect(OPCODE_IDS.XYCSwap).toBe(golden.opcodes.XYCSwap)
    expect(OPCODE_IDS.IndexNavGuard).toBe(golden.opcodes.IndexNavGuard)
    expect(OPCODE_IDS.IndexNavPriceAdjuster).toBe(golden.opcodes.IndexNavPriceAdjuster)
    expect(OPCODE_IDS.IndexInventorySkew).toBe(golden.opcodes.IndexInventorySkew)
    expect(OPCODE_IDS.IndexMaxTrade).toBe(golden.opcodes.IndexMaxTrade)
    expect(OPCODE_IDS.IndexCapabilityGuard).toBe(golden.opcodes.IndexCapabilityGuard)
  })

  it('table index equals opcode byte and there are no collisions', () => {
    expect(aquaIndexInstructions).toHaveLength(256)
    expect(opcodeByte(indexNavGuardXD)).toBe(0xe0)
    expect(opcodeByte(indexMaxTradeXD)).toBe(0xe3)
    expect(opcodeByte(indexCapabilityGuardXD)).toBe(0xe4)
    expect(opcodeByte(controls.salt)).toBe(0x02)
    expect(opcodeByte(controls.deadline)).toBe(0x20)
    const used = Object.values(OPCODE_IDS)
    expect(new Set(used).size).toBe(used.length)
  })
})

describe('args coders: round trip and Solidity byte equality', () => {
  it('nav guard', () => {
    const a = new IndexNavGuardArgs(NAV, 7n, 300, 3n, 150)
    const enc = IndexNavGuardArgs.CODER.encode(a)
    expect('0xe0' + '2a' + enc.toString().slice(2)).toBe(golden.instructions.navGuard)
    expect(IndexNavGuardArgs.CODER.decode(enc).toJSON()).toEqual(a.toJSON())
  })

  it('max trade', () => {
    const a = new IndexMaxTradeArgs(NAV, 7n, 1n, 2n, 3n)
    const enc = IndexMaxTradeArgs.CODER.encode(a)
    expect('0xe3' + '4c' + enc.toString().slice(2)).toBe(golden.instructions.maxTrade)
    expect(IndexMaxTradeArgs.CODER.decode(enc).toJSON()).toEqual(a.toJSON())
  })

  it('capability guard', () => {
    const a = new IndexCapabilityGuardArgs(REG, '0x' + 'abcdef'.padStart(64, '0'))
    const enc = IndexCapabilityGuardArgs.CODER.encode(a)
    expect('0xe4' + '34' + enc.toString().slice(2)).toBe(golden.instructions.capability)
    expect(IndexCapabilityGuardArgs.CODER.decode(enc).toJSON()).toEqual(a.toJSON())
  })

  it('price adjuster round trip incl. negative premium and boundaries', () => {
    for (const premium of [-300, -1, 0, 1, 300]) {
      const a = new IndexNavPriceAdjusterArgs({
        navSource: NAV, indexId: 1n, quoteToken: QUOTE, premiumBps: premium,
        maxPremiumBps: 300, maxDiscountBps: 300, spreadBps: 20, feeBps: 5, mode: 0
      })
      const back = IndexNavPriceAdjusterArgs.CODER.decode(IndexNavPriceAdjusterArgs.CODER.encode(a))
      expect(back.toJSON()).toEqual(a.toJSON())
    }
  })

  it('skew round trip', () => {
    const a = new IndexInventorySkewArgs({
      navSource: NAV, indexId: 9n, quoteToken: QUOTE, targetShareBps: 5000, maxSkewBps: 3000, slopeBps: 5000, maxAdjustBps: 500
    })
    expect(IndexInventorySkewArgs.CODER.decode(IndexInventorySkewArgs.CODER.encode(a)).toJSON()).toEqual(a.toJSON())
  })

  it('strict argument validation', () => {
    expect(() => new IndexNavGuardArgs(NAV, 1n, 1, 1n, 10_001)).toThrow()
    expect(() => IndexNavGuardArgs.CODER.encode(new IndexNavGuardArgs(NAV, 1n << 64n, 1, 1n, 1))).toThrow()
    expect(() => IndexNavGuardArgs.CODER.decode(new HexString('0x1234'))).toThrow(/invalid args length/)
    expect(() => IndexNavGuardArgs.CODER.decode(new HexString('0x' + '00'.repeat(43)))).toThrow(/invalid args length/)
    expect(() => IndexMaxTradeArgs.CODER.encode(new IndexMaxTradeArgs(NAV, 1n, 1n << 128n, 0n, 0n))).toThrow()
    expect(() => new IndexCapabilityGuardArgs('0x12', '0x' + '00'.repeat(32)).toJSON() && IndexCapabilityGuardArgs.CODER.encode(new IndexCapabilityGuardArgs('0x12', '0x' + '00'.repeat(32)))).toThrow()
    const mk = (premiumBps: number) => new IndexNavPriceAdjusterArgs({
      navSource: NAV, indexId: 1n, quoteToken: QUOTE, premiumBps, maxPremiumBps: 300, maxDiscountBps: 300, spreadBps: 0, feeBps: 0, mode: 0
    })
    expect(() => mk(301)).toThrow(/outside/)
    expect(() => mk(-301)).toThrow(/outside/)
    expect(() => new IndexInventorySkewArgs({ navSource: NAV, indexId: 1n, quoteToken: QUOTE, targetShareBps: 5000, maxSkewBps: 1, slopeBps: 1, maxAdjustBps: 5001 })).toThrow()
  })
})

describe('program builder / strategies == Solidity AquaIndexStrategyManager', () => {
  for (const kind of [StrategyKind.NAV_ANCHORED, StrategyKind.CONSERVATIVE, StrategyKind.ADAPTIVE]) {
    const name = ['A', 'B', 'C'][kind]
    it(`program ${name} is byte-identical to Solidity`, () => {
      expect(buildStrategyProgram(params(kind)).toString()).toBe(golden.programs[name])
    })

    it(`order ${name}: maker, traits, data and Aqua strategy hash match Solidity`, () => {
      const { order, hash } = buildStrategyOrder(params(kind))
      expect(order.maker.toLowerCase()).toBe(golden.orders[name].maker.toLowerCase())
      expect(order.traits.toString()).toBe(golden.orders[name].traits)
      expect(order.data).toBe(golden.orders[name].data)
      expect(hash).toBe(golden.orders[name].hash)
    })

    it(`program ${name} decodes back and re-encodes to the same bytes`, () => {
      const program = buildStrategyProgram(params(kind))
      const decoded = new AquaIndexProgramBuilder().decode(program)
      expect(decoded.build().toString()).toBe(program.toString())
      expect(decoded.getInstructions().length).toBe(kind === StrategyKind.ADAPTIVE ? 8 : 7)
    })
  }

  it('writes ts-vectors.json for the Solidity cross-check', () => {
    const programs: Record<string, string> = {}
    const orders: Record<string, unknown> = {}
    for (const kind of [StrategyKind.NAV_ANCHORED, StrategyKind.CONSERVATIVE, StrategyKind.ADAPTIVE]) {
      const name = ['A', 'B', 'C'][kind]
      const { order, hash, program } = buildStrategyOrder(params(kind))
      programs[name] = program.toString()
      orders[name] = { data: order.data, traits: order.traits.toString(), hash }
    }
    writeFileSync(join(here, 'ts-vectors.json'), JSON.stringify({ programs, orders }, null, 2))
  })

  it('without capability guard the guard instruction is omitted', () => {
    const p = { ...params(StrategyKind.NAV_ANCHORED), capabilityRegistry: '0x' + '00'.repeat(20) }
    const ixs = new AquaIndexProgramBuilder().decode(buildStrategyProgram(p)).getInstructions()
    expect(ixs).toHaveLength(6)
  })
})

describe('wrong instruction set / unknown opcodes are rejected', () => {
  it('rejects an unknown opcode id', () => {
    const bytes = new HexString('0xe500')
    expect(() => new AquaIndexProgramBuilder().decode(bytes as never)).toThrow()
  })

  it('rejects upstream opcodes that are not in the set (reserved slot)', () => {
    // 0xb2 = OraclePriceAdjuster on the router's OpcodeList, deliberately absent from instruction set v1
    expect(() => new AquaIndexProgramBuilder().decode(new HexString('0xb200') as never)).toThrow()
  })

  it('AquaProgramBuilder (deployed-router table) cannot decode AquaIndex programs', () => {
    const program = buildStrategyProgram(params(StrategyKind.NAV_ANCHORED))
    expect(() => new AquaProgramBuilder().decode(program)).toThrow()
  })

  it('AquaIndex builder rejects instructions from another table', () => {
    const b = new AquaIndexProgramBuilder()
    expect(() => b.add(controls.onlyTakerTokenBalanceNonZero.createIx(new controls.OnlyTakerTokenBalanceNonZeroArgs(QUOTE as never)))).toThrow()
  })
})

describe('taker data == Solidity TakerTraitsLib', () => {
  for (let i = 0; i < 4; i++) {
    it(`combo ${i}`, () => {
      const data = buildTakerData({ isExactIn: (i & 1) !== 0, isAToB: (i & 2) !== 0, threshold: BigInt(123456 + i) })
      expect(data).toBe(golden.takerData['c' + i])
    })
  }
})


describe('server-side lite decoder', () => {
  it('decodes program A (7 instructions) with correct names and args', () => {
    const ixs = decodeLite(golden.programs.A)
    expect(ixs.map((i) => i.name)).toEqual([
      'Deadline', 'Salt', 'INDEX_NAV_GUARD_XD', 'INDEX_NAV_PRICE_ADJUSTER_XD', 'INDEX_INVENTORY_SKEW_XD', 'INDEX_MAX_TRADE_XD', 'INDEX_CAPABILITY_GUARD_XD'
    ])
    expect((ixs[3].args as { premiumBps: number }).premiumBps).toBe(-125)
    expect(splitOrderData(golden.orders.A.data).program).toBe(golden.programs.A)
  })
  it('rejects unknown opcodes and truncated programs', () => {
    expect(() => decodeLite('0xe500')).toThrow(/unknown opcode/)
    expect(() => decodeLite('0xe0')).toThrow(/truncated/)
    expect(() => decodeLite('0xe02a00')).toThrow(/truncated/)
  })
})
