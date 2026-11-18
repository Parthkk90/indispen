'use client'
import { useState } from 'react'
import { useAccount, useReadContract } from 'wagmi'
import { parseUnits, formatUnits } from 'viem'
import { mockERC20Abi, subscriptionManagerAbi } from '@aquaindex/shared'
import { D } from '@/lib/config'
import { useApi } from '@/lib/api'
import { useTx } from '@/lib/useTx'
import { usd, num, ago } from '@/lib/format'
import { Card, Connect, TxStatus } from '@/components/ui'

export default function Invest() {
  const { address } = useAccount()
  const [amt, setAmt] = useState('1000')
  const ix = useApi<any>('/api/indices/1')
  const raw = (() => { try { return parseUnits(amt || '0', 6) } catch { return 0n } })()
  const quote = useReadContract({ address: D.subscriptionManager, abi: subscriptionManagerAbi, functionName: 'quote', args: [1n, raw], query: { enabled: raw > 0n } })
  const bal = useReadContract({ address: D.usdc, abi: mockERC20Abi, functionName: 'balanceOf', args: [address!], query: { enabled: !!address } })
  const allowance = useReadContract({ address: D.usdc, abi: mockERC20Abi, functionName: 'allowance', args: [address!, D.subscriptionManager], query: { enabled: !!address } })
  const { state, run } = useTx()
  const shares = quote.data?.[0] ?? 0n
  const minShares = (shares * 995n) / 1000n

  if (!address) return <Connect />
  const subscribe = async () => {
    const steps: Parameters<typeof run>[0] = []
    if ((allowance.data ?? 0n) < raw) steps.push({ label: 'Approve mUSDC', req: { address: D.usdc, abi: mockERC20Abi, functionName: 'approve', args: [D.subscriptionManager, raw] } })
    steps.push({ label: 'Subscribe', req: { address: D.subscriptionManager, abi: subscriptionManagerAbi, functionName: 'subscribe', args: [1n, raw, minShares] } })
    if (await run(steps)) { bal.refetch(); allowance.refetch(); ix.refetch() }
  }
  const faucet = () => run([{ label: 'Mint 10,000 mUSDC (test faucet)', req: { address: D.usdc, abi: mockERC20Abi, functionName: 'mint', args: [address, 10_000n * 10n ** 6n] } }]).then(() => bal.refetch())

  return (
    <>
      <h1 className="text-2xl font-bold">Invest</h1>
      <Card title="Subscribe with mock USDC">
        <div className="grid gap-3 md:grid-cols-2">
          <div>
            <label className="text-sm muted">Amount (mUSDC)</label>
            <input className="input" value={amt} onChange={(e) => setAmt(e.target.value)} />
            <p className="mt-1 text-xs muted">Wallet: {num(bal.data, 6, 2)} mUSDC <button className="underline" onClick={faucet}>get 10,000 test mUSDC</button></p>
          </div>
          <div className="text-sm space-y-1">
            <div>Estimated shares: <b>{num(shares)}</b> {ix.data?.symbol}</div>
            <div>Min shares (0.5% slippage): {num(minShares)}</div>
            <div>NAV/share used: {quote.data ? usd(quote.data[1], 4) : '-'} <span className="muted">(live on-chain, before your deposit)</span></div>
            <div>Fee: {ix.data ? '0%' : '-'} (index subscription fee bps = 0)</div>
            <div className="muted">Published NAV snapshot: epoch {ix.data?.snapshot.epoch}, {ago(ix.data?.snapshot.ageSeconds)}</div>
          </div>
        </div>
        <button className="btn mt-4" disabled={raw === 0n || shares === 0n || state.status === 'signing' || state.status === 'pending'} onClick={subscribe}>
          {(allowance.data ?? 0n) < raw ? 'Approve & subscribe' : 'Subscribe'}
        </button>
        <TxStatus state={state} />
        <p className="mt-3 text-xs muted">Shares are minted on-chain by SubscriptionManager at vault NAV; your USDC is recorded in the IndexVault ledger.</p>
      </Card>
      <p className="text-xs muted">formatUnits check: {formatUnits(raw, 6)} mUSDC</p>
    </>
  )
}
