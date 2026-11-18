import { http, createConfig } from 'wagmi'
import { sepolia } from 'wagmi/chains'
import { injected } from '@wagmi/core'
import { deployment } from '@aquaindex/shared'

export const API = process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:4001'
export const D = deployment as unknown as Record<string, `0x${string}`>
export const EXPLORER = 'https://sepolia.etherscan.io'

export const wagmiConfig = createConfig({
  chains: [sepolia],
  connectors: [injected() as never],
  transports: { [sepolia.id]: http('https://ethereum-sepolia-rpc.publicnode.com') },
  ssr: true
})
