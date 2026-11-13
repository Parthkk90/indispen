'use client'
import { useAccount, useReadContract, useWriteContract } from 'wagmi'
import { Area, AreaChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import { useApi } from '@/lib/api'
import { D } from '@/lib/config'
import { usd, num, pct, ago, short } from '@/lib/format'
import { navOracleAbi } from '@aquaindex/shared'
import { Badge, Card, Loading, Stat, TxStatus } from '@/components/ui'
import { useTx } from '@/lib/useTx'

export default function Overview() {
  const ix = useApi<any>('/api/indices/1')
  const hist = useApi<any[]>('/api/indices/1/nav-history')
  const trades = useApi<any[]>('/api/trades')
  const { address } = useAccount()
  const publisherRole = useReadContract({ address: D.oracle, abi: navOracleAbi, functionName: 'NAV_PUBLISHER_ROLE' })
  const hasRole = useReadContract({ address: D.oracle, abi: navOracleAbi, functionName: 'hasRole', args: [publisherRole.data as `0x${string}`, address!], query: { enabled: !!publisherRole.data && !!address } })
  const { state, run } = useTx()

  const d = ix.data
  const stale = d && d.snapshot.ageSeconds != null && d.snapshot.ageSeconds > 1800
  const chart = (hist.data ?? []).map((p) => ({ t: new Date(p.timestamp).toLocaleTimeString(), nav: Number(p.navPerShare) / 1e18, epoch: p.epoch }))

  return (
    <>
      <h1 className="text-2xl font-bold">Overview</h1>
      <Loading q={ix} />
      {d && (
        <>
          <div className="grid gap-4 md:grid-cols-4">
            <Stat label="NAV per share" value={d.nav ? usd(d.nav.navPerShare, 4) : '-'} sub={d.navError ?? 'computed on-chain from vault × oracle prices'} />
            <Stat label="Total vault assets" value={d.nav ? usd(d.nav.totalNav) : '-'} sub={`${num(d.supply)} ${d.symbol} outstanding`} />
            <Stat label="Backing" value={<Badge ok={d.backing.verified}>{d.backing.verified ? 'Verified' : 'NOT BACKED'}</Badge>} sub="vault ledger ≤ token balance, every asset" />
            <Stat label="NAV snapshot" value={`epoch ${d.snapshot.epoch}`} sub={<span className={stale ? 'text-rose-300' : ''}>{ago(d.snapshot.ageSeconds)}{stale ? ' - stale: custom-router trading is blocked until republished' : ''}</span>} />
          </div>
          {stale && hasRole.data && (
            <Card title="NAV keeper">
              <p className="mb-2 text-sm muted">Your wallet holds NAV_PUBLISHER_ROLE. Publishing recomputes NAV on-chain; you cannot set a number.</p>
              <button className="btn" onClick={() => run([{ label: 'Publish NAV', req: { address: D.oracle, abi: navOracleAbi, functionName: 'publishNav', args: [1n] } }])}>Publish NAV</button>
              <TxStatus state={state} />
            </Card>
          )}
          <Card title={`${d.name} - NAV per share (published snapshots)`}>
            {chart.length > 1 ? (
              <div className="h-64">
                <ResponsiveContainer>
                  <AreaChart data={chart}>
                    <CartesianGrid stroke="#1f2937" />
                    <XAxis dataKey="t" stroke="#8b97ab" />
                    <YAxis stroke="#8b97ab" domain={['auto', 'auto']} />
                    <Tooltip contentStyle={{ background: '#121826', border: '1px solid #1f2937' }} />
                    <Area dataKey="nav" stroke="#60a5fa" fill="#1d4ed833" />
                  </AreaChart>
                </ResponsiveContainer>
              </div>
            ) : <p className="muted">Fewer than two indexed NAV snapshots so far.</p>}
          </Card>
          <Card title="Holdings">
            <table className="t">
              <thead><tr><th>Asset</th><th>Balance</th><th>Value</th><th>Weight</th><th>Target</th></tr></thead>
              <tbody>
                {d.holdings.map((h: any) => (
                  <tr key={h.asset}><td>{h.symbol}{h.isCash && <span className="muted"> (idle cash)</span>}</td><td>{num(h.balance, h.decimals)}</td><td>{usd(h.value)}</td><td>{pct(h.weightBps)}</td><td>{pct(h.targetWeightBps)}</td></tr>
                ))}
              </tbody>
            </table>
          </Card>
        </>
      )}
      <Card title="Recent trades through the AquaIndex router">
        {(trades.data ?? []).length === 0 ? <p className="muted">No trades indexed yet.</p> : (
          <table className="t"><thead><tr><th>Time</th><th>Maker</th><th>In</th><th>Out</th><th>Tx</th></tr></thead>
            <tbody>{trades.data!.slice(0, 8).map((t) => (
              <tr key={t.id}><td>{new Date(t.timestamp).toLocaleString()}</td><td>{short(t.maker)}</td><td>{short(t.tokenIn)} {t.amountIn}</td><td>{short(t.tokenOut)} {t.amountOut}</td><td><a className="underline" target="_blank" href={`https://sepolia.etherscan.io/tx/${t.txHash}`}>{short(t.txHash)}</a></td></tr>
            ))}</tbody></table>
        )}
      </Card>
    </>
  )
}
