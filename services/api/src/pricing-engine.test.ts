import { describe, expect, it } from 'vitest'
import { encodeAbiParameters } from 'viem'
import { readFileSync } from 'node:fs'
import { parseStrategy } from './pricing-engine'

const golden = JSON.parse(readFileSync(new URL('../../../packages/aquaindex-swapvm-sdk/test/golden.json', import.meta.url), 'utf8'))
const enc = (o: { maker: string; traits: string; data: string }) =>
  encodeAbiParameters(
    [{ type: 'tuple', components: [{ name: 'maker', type: 'address' }, { name: 'traits', type: 'uint256' }, { name: 'data', type: 'bytes' }] }],
    [{ maker: o.maker as `0x${string}`, traits: BigInt(o.traits), data: o.data as `0x${string}` }]
  )

describe('parseStrategy', () => {
  it('decodes the Solidity-built Strategy A order into AquaIndex instructions', () => {
    const p = parseStrategy(enc(golden.orders.A))
    expect(p.isIndexStrategy).toBe(true)
    expect(p.decodeError).toBeNull()
    expect(p.instructions!.map((i) => i.opcode)).toEqual([0x20, 0x02, 0xe0, 0xe1, 0xe2, 0xe3, 0xe4])
    expect(p.tokenA.toLowerCase()).toBe('0x3333333333333333333333333333333333333333')
  })

  it('flags non-index programs and reports undecodable ones without throwing', () => {
    const xyc = '0x' + '11'.repeat(20) + '22'.repeat(20) + '020800000000000000010' + '050' // salt + xyc
    const good = parseStrategy(enc({ maker: '0x' + '11'.repeat(20), traits: '0', data: '0x' + '11'.repeat(20) + '22'.repeat(20) + '0208' + '0000000000000001' + '5000' }))
    expect(good.isIndexStrategy).toBe(false)
    expect(good.instructions!.map((i) => i.name)).toEqual(['Salt', 'XYCSwap'])
    const bad = parseStrategy(enc({ maker: '0x' + '11'.repeat(20), traits: '0', data: xyc.length % 2 ? xyc + '0' : xyc }))
    expect(bad.decodeError).toBeTruthy()
  })
})
