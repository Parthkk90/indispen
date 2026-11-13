import { createPublicClient, http, type Address } from 'viem'
import { sepolia } from 'viem/chains'
import { deployment } from '@aquaindex/shared'

export const RPC = process.env.SEPOLIA_RPC_URL ?? 'https://ethereum-sepolia-rpc.publicnode.com'
export const client = createPublicClient({ chain: sepolia, transport: http(RPC, { batch: true, retryCount: 3 }) })

export const D = deployment as unknown as Record<string, string>
export const addr = (k: string) => D[k] as Address

export const ZERO = '0x0000000000000000000000000000000000000000' as Address

/** JSON-safe: bigint -> decimal string. */
export function ser<T>(v: T): unknown {
  return JSON.parse(JSON.stringify(v, (_k, x) => (typeof x === 'bigint' ? x.toString() : x)))
}
