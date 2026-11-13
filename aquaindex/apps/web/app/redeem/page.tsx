'use client'
import { useState } from 'react'
import { useAccount, useReadContract } from 'wagmi'
import { parseUnits } from 'viem'
import { indexShareAbi, redemptionManagerAbi } from '@aquaindex/shared'
import { D } from '@/lib/config'
import { useApi } from '@/lib/api'
import { useTx } from '@/lib/useTx'
import { num } from '@/lib/format'
import { Card, Connect, TxStatus } from '@/components/ui'

export default function Redeem() {
  const { address } = useAccount()
  const ix = useApi<any>('/api/indices/1')
  const [amt, setAmt] = useState('1')
  const raw = (() => { try { return parseUnits(amt || '0', 18) } catch { return 0n } })()
  const bal = useReadContract({ address: ix.data?.share, abi: indexShareAbi, functionName: 'balanceOf', args: [address!], query: { enabled: !!address && !!ix.data } })
  const inKind = useReadContract({ address: D.redemptionManager, abi: redemptionManagerAbi, functionName: 'previewInKind', args: [1n, raw], query: { enabled: raw > 0n && raw <= (bal.data ?? 0n) } })
  const toQuote = useReadContract({ address: D.redemptionManager, abi: redemptionManagerAbi, functionName: 'previewToQuote', args: [1n, raw], query: { enabled: raw > 0n && raw <= (bal.data ?? 0n) } })
  const { state, run } = useTx()
  if (!address) return <Connect />
  const sym = (a: string) => ix.data?.holdings.find((h: any) => h.asset.toLowerCase() === a.toLowerCase())
  const cashHeld = BigInt(ix.data?.holdings.find((h: any) => h.isCash)?.balance ?? '0')
  const canQuote = toQuote.data !== undefined && cashHeld >= toQuote.data
  const after = () => { bal.refetch(); ix.refetch() }
  return (
    <>
      <h1 className="text-2xl font-bold">Redeem</h1>
      <Card title="Burn shares">
        <label className="text-sm muted">Shares to redeem (balance {num(bal.data)})</label>
        <input className="input" value={amt} onChange={(e) => setAmt(e.target.value)} />
        <div className="mt-4 grid gap-4 md:grid-cols-2">
          <div>
            <h3 className="font-semibold">In-kind (pro-rata of every vault asset)</h3>
            <table className="t"><tbody>{(inKind.data?.[0] ?? []).map((a, i) => <tr key={a}><td>{sym(a)?.symbol ?? a}</td><td>{num(inKind.data![1][i], sym(a)?.decimals ?? 18, 6)}</td></tr>)}</tbody></table>
            <button className="btn mt-2" disabled={!inKind.data} onClick={() => run([{ label: 'Redeem in kind', req: { address: D.redemptionManager, abi: redemptionManagerAbi, functionName: 'redeemInKind', args: [1n, raw] } }]).then(after)}>Redeem in kind</button>
          </div>
          <div>
            <h3 className="font-semibold">To mUSDC</h3>
            <p className="text-sm">Value: <b>{num(toQuote.data, 6, 2)}</b> mUSDC (min output 0.5% below)</p>
            <p className="text-xs muted">Vault idle mUSDC: {num(cashHeld, 6, 2)}. {canQuote ? '' : 'Not enough idle USDC for this size: only in-kind redemption is available (no forced liquidation).'}</p>
            <button className="btn mt-2" disabled={!canQuote} onClick={() => run([{ label: 'Redeem to mUSDC', req: { address: D.redemptionManager, abi: redemptionManagerAbi, functionName: 'redeemToQuote', args: [1n, raw, ((toQuote.data ?? 0n) * 995n) / 1000n] } }]).then(after)}>Redeem to mUSDC</button>
          </div>
        </div>
        <TxStatus state={state} />
      </Card>
    </>
  )
}
