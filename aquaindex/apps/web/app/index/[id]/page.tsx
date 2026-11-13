'use client'
import { use } from 'react'
import { Bar, BarChart, CartesianGrid, Legend, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import { useApi } from '@/lib/api'
import { usd, num, pct, ago, short } from '@/lib/format'
import { Badge, Card, Loading, Stat } from '@/components/ui'

export default function IndexDetails({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params)
  const ix = useApi<any>(`/api/indices/${id}`)
  const rb = useApi<any>(`/api/indices/${id}/rebalance`)
  const act = useApi<any[]>(`/api/indices/${id}/activity`)
  const d = ix.data
  const bars = (d?.holdings ?? []).map((h: any) => ({ name: h.symbol, current: (h.weightBps ?? 0) / 100, target: h.targetWeightBps / 100 }))
  const maxDrift = rb.data ? Math.max(...rb.data.drift.map((x: any) => Math.abs(x.driftBps))) : null
  return (
    <>
      <Loading q={ix} />
      {d && (
        <>
          <h1 className="text-2xl font-bold">{d.name} <span className="muted text-base">{d.symbol}</span></h1>
          <div className="grid gap-4 md:grid-cols-4">
            <Stat label="NAV / share" value={d.nav ? usd(d.nav.navPerShare, 4) : '-'} />
            <Stat label="Methodology" value={`v${d.methodologyVersion}`} sub={d.metadataURI} />
            <Stat label="Backing" value={<Badge ok={d.backing.verified}>{d.backing.verified ? 'Verified' : 'NOT BACKED'}</Badge>} sub={d.backing.source} />
            <Stat label="Rebalance status" value={maxDrift == null ? '-' : maxDrift > 500 ? <Badge ok={false}>Drift {pct(maxDrift)}</Badge> : <Badge ok>Within band</Badge>} sub={`snapshot epoch ${d.snapshot.epoch}, ${ago(d.snapshot.ageSeconds)}`} />
          </div>
          <Card title="Composition: current vs target weight (%)">
            <div className="h-64"><ResponsiveContainer><BarChart data={bars}><CartesianGrid stroke="#1f2937" /><XAxis dataKey="name" stroke="#8b97ab" /><YAxis stroke="#8b97ab" /><Tooltip contentStyle={{ background: '#121826', border: '1px solid #1f2937' }} /><Legend /><Bar dataKey="current" fill="#60a5fa" /><Bar dataKey="target" fill="#34d399" /></BarChart></ResponsiveContainer></div>
          </Card>
          <Card title="Holdings (vault ledger)">
            <table className="t"><thead><tr><th>Asset</th><th>Address</th><th>Balance</th><th>Oracle price</th><th>Value</th></tr></thead>
              <tbody>{d.holdings.map((h: any) => <tr key={h.asset}><td>{h.symbol}</td><td>{short(h.asset)}</td><td>{num(h.balance, h.decimals)}</td><td>{usd(h.price)}</td><td>{usd(h.value)}</td></tr>)}</tbody></table>
          </Card>
          <Card title="Methodology">
            <p className="text-sm muted">Shares are minted at on-chain NAV (vault ledger × authorised oracle prices) and redeem pro-rata, so outstanding claims never exceed vault backing. Weights are equal (20% each) over five synthetic receipt tokens; USDC held in the vault is idle cash until rebalanced through Aqua liquidity.</p>
          </Card>
          <Card title="Activity">
            <table className="t"><thead><tr><th>Time</th><th>Event</th><th>Tx</th></tr></thead>
              <tbody>{(act.data ?? []).slice(0, 15).map((e) => <tr key={e.id}><td>{new Date(e.timestamp).toLocaleString()}</td><td>{e.kind}</td><td><a className="underline" target="_blank" href={`https://sepolia.etherscan.io/tx/${e.txHash}`}>{short(e.txHash)}</a></td></tr>)}</tbody></table>
          </Card>
        </>
      )}
    </>
  )
}
