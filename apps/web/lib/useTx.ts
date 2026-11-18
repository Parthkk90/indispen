'use client'
import { useState } from 'react'
import { useAccount, usePublicClient, useSwitchChain, useWriteContract } from 'wagmi'
import { sepolia } from 'wagmi/chains'

const SEPOLIA_HEX = '0xaa36a7'
const SEPOLIA_PARAMS = {
  chainId: SEPOLIA_HEX,
  chainName: 'Sepolia',
  nativeCurrency: { name: 'Sepolia Ether', symbol: 'ETH', decimals: 18 },
  rpcUrls: ['https://ethereum-sepolia-rpc.publicnode.com'],
  blockExplorerUrls: ['https://sepolia.etherscan.io']
}

export type TxState = { status: 'idle' | 'signing' | 'pending' | 'success' | 'error'; hash?: `0x${string}`; error?: string; step?: string }

/** Sequential transaction runner: each step is signed, then awaited, with live state for the UI. */
export function useTx() {
  const [state, setState] = useState<TxState>({ status: 'idle' })
  const { writeContractAsync } = useWriteContract()
  const pc = usePublicClient({ chainId: sepolia.id })
  const { connector } = useAccount()
  const { switchChainAsync } = useSwitchChain()

  /** Ask the wallet itself (not wagmi's cached state) which chain it is on; switch or add Sepolia if needed. */
  async function ensureSepolia() {
    const provider = (await connector?.getProvider()) as { request: (a: { method: string; params?: unknown[] }) => Promise<unknown> } | undefined
    if (!provider) throw new Error('No wallet connected.')
    const current = () => provider.request({ method: 'eth_chainId' }).then((c) => Number(c as string))
    if ((await current()) === sepolia.id) return
    setState({ status: 'signing', step: 'Approve the switch to Sepolia in your wallet' })
    try {
      await provider.request({ method: 'wallet_switchEthereumChain', params: [{ chainId: SEPOLIA_HEX }] })
    } catch (e) {
      const code = (e as { code?: number }).code
      if (code === 4902 || code === -32603) {
        await provider.request({ method: 'wallet_addEthereumChain', params: [SEPOLIA_PARAMS] })
      } else {
        throw new Error('Your wallet is not on Sepolia and the switch was rejected. Select Sepolia (chain 11155111) in your wallet and retry.')
      }
    }
    try { await switchChainAsync({ chainId: sepolia.id }) } catch { /* wagmi state sync only */ }
    const now = await current()
    if (now !== sepolia.id) throw new Error(`Wallet is still on chain ${now}. Select Sepolia (chain 11155111) in your wallet and retry.`)
  }

  async function run(steps: { label: string; req: Parameters<typeof writeContractAsync>[0] }[]) {
    try {
      await ensureSepolia()
      for (const s of steps) {
        setState({ status: 'signing', step: s.label })
        const hash = await writeContractAsync({ ...s.req, chainId: sepolia.id } as typeof s.req)
        setState({ status: 'pending', hash, step: s.label })
        const rc = await pc!.waitForTransactionReceipt({ hash })
        if (rc.status !== 'success') throw new Error(`${s.label} reverted on-chain`)
        setState({ status: 'success', hash, step: s.label })
      }
      return true
    } catch (e) {
      setState({ status: 'error', error: ((e as Error).message ?? 'failed').split('\n')[0] })
      return false
    }
  }
  return { state, run, reset: () => setState({ status: 'idle' }) }
}
