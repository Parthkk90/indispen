import { decodeAbiParameters, decodeErrorResult, formatUnits, type Address, type Hex } from 'viem'
import { decodeProgram, splitOrderData } from '@aquaindex/swapvm-sdk/decode'
import { buildTakerData } from '@aquaindex/swapvm-sdk/taker'
import { aquaIndexSwapVMRouterAbi, navOracleAbi, erc20Abiish } from './abis-local'
import { client, addr, ZERO } from './chain'
import { prisma } from './db'

const ORDER_ABI = {
  type: 'tuple',
  components: [
    { name: 'maker', type: 'address' },
    { name: 'traits', type: 'uint256' },
    { name: 'data', type: 'bytes' }
  ]
} as const

export function parseStrategy(orderData: Hex) {
  const [order] = decodeAbiParameters([ORDER_ABI], orderData)
  const { tokenA, tokenB, program } = splitOrderData(order.data)
  let instructions: ReturnType<typeof decodeProgram> | null = null
  let decodeError: string | null = null
  try {
    instructions = decodeProgram(program)
  } catch (e) {
    decodeError = (e as Error).message
  }
  const isIndexStrategy = !!instructions?.some((i) => i.opcode >= 0xe0 && i.opcode <= 0xe4)
  return { order, tokenA: tokenA as Address, tokenB: tokenB as Address, instructions, decodeError, isIndexStrategy }
}

function revertName(e: unknown): string {
  // walk the viem error chain for the raw revert data
  let cur = e as { raw?: Hex; data?: unknown; cause?: unknown; shortMessage?: string } | undefined
  for (let i = 0; i < 8 && cur; i++) {
    const cand = typeof cur.raw === 'string' ? cur.raw : typeof cur.data === 'string' ? (cur.data as Hex) : undefined
    if (cand && cand.startsWith('0x') && cand.length >= 10) {
      try {
        const d = decodeErrorResult({ abi: aquaIndexSwapVMRouterAbi, data: cand })
        return `${d.errorName}(${(d.args ?? []).map(String).join(', ')})`
      } catch {
        return `unrecognised revert ${cand.slice(0, 10)}`
      }
    }
    cur = cur.cause as typeof cur
  }
  return (e as Error).message.split('\n')[0]
}

export async function quoteStrategy(p: { strategyHash: Hex; tokenIn: Address; amount: bigint; exactIn: boolean; taker: Address }) {
  const s = await prisma.strategy.findUnique({ where: { hash: p.strategyHash } })
  if (!s) throw Object.assign(new Error('unknown strategy (not indexed yet)'), { statusCode: 404 })
  const { order, tokenA, tokenB } = parseStrategy(s.orderData as Hex)
  const tIn = p.tokenIn.toLowerCase()
  if (tIn !== tokenA.toLowerCase() && tIn !== tokenB.toLowerCase()) throw Object.assign(new Error('tokenIn is not part of this strategy'), { statusCode: 400 })
  const tokenOut = tIn === tokenA.toLowerCase() ? tokenB : tokenA
  const isAToB = tIn === tokenA.toLowerCase()
  const takerData = buildTakerData({ isExactIn: p.exactIn, isAToB, threshold: p.exactIn ? 0n : (1n << 256n) - 1n })
  const router = addr('router')
  try {
    const res = await client.simulateContract({
      address: router,
      abi: aquaIndexSwapVMRouterAbi,
      functionName: 'quote',
      args: [order, p.amount, takerData],
      account: p.taker
    })
    const [amountIn, amountOut] = res.result
    const [inDec, outDec] = await Promise.all([
      client.readContract({ address: p.tokenIn, abi: erc20Abiish, functionName: 'decimals' }),
      client.readContract({ address: tokenOut, abi: erc20Abiish, functionName: 'decimals' })
    ])
    const price = Number(formatUnits(amountOut, outDec)) / Number(formatUnits(amountIn, inDec))
    return { ok: true as const, source: 'AquaIndex custom SwapVM router', router, tokenIn: p.tokenIn, tokenOut, amountIn: amountIn.toString(), amountOut: amountOut.toString(), priceOutPerIn: price, exactIn: p.exactIn }
  } catch (e) {
    return { ok: false as const, source: 'AquaIndex custom SwapVM router', router, tokenIn: p.tokenIn, tokenOut, reverted: revertName(e) }
  }
}

export async function navReference(indexId: number, quoteToken: Address) {
  const oracle = addr('oracle')
  const [, , navPerShare] = await client.readContract({ address: oracle, abi: navOracleAbi, functionName: 'computeNav', args: [BigInt(indexId)] })
  const qp = await client.readContract({ address: oracle, abi: navOracleAbi, functionName: 'assetPrice', args: [quoteToken] })
  return Number(formatUnits(navPerShare, 18)) / Number(formatUnits(qp, 18)) // quote units per share
}

export { ZERO }
