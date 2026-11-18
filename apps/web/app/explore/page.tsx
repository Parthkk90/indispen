'use client'
import Link from 'next/link'
import { DEMO_CONSTITUENTS } from '@aquaindex/shared'
import { useApi } from '@/lib/api'
import { usd, num, pct } from '@/lib/format'
import { Badge, Card, Loading } from '@/components/ui'

export default function Explore() {
  const q = useApi<any[]>('/api/indices')
  return (
    <>
      <h1 className="text-2xl font-bold">Explore indices</h1>
      <Loading q={q} />
      {(q.data ?? []).map((ix) => (
        <Card key={ix.indexId}>
          <div className="flex flex-wrap items-center gap-3">
            <h2 className="text-lg font-semibold">{ix.name}</h2><span className="muted">{ix.symbol}</span>
            <Badge ok={ix.status === 'ACTIVE'}>{ix.status}</Badge>
            <span className="muted text-sm">methodology v{ix.methodologyVersion}</span>
            <div className="ml-auto flex gap-2">
              <Link className="btn-ghost" href={`/index/${ix.indexId}`}>Details</Link>
              <Link className="btn" href="/invest">Subscribe</Link>
            </div>
          </div>
          <div className="mt-3 grid gap-3 md:grid-cols-3 text-sm">
            <div>NAV/share <b>{ix.nav ? usd(ix.nav.navPerShare, 4) : '-'}</b></div>
            <div>Total NAV <b>{ix.nav ? usd(ix.nav.totalNav) : '-'}</b></div>
            <div>Shares <b>{num(ix.supply)}</b></div>
          </div>
          <p className="mt-3 text-sm muted">On-chain constituents: {ix.holdings.filter((h: any) => !h.isCash).map((h: any) => `${h.symbol} (${pct(h.targetWeightBps)})`).join(', ')}</p>
        </Card>
      ))}
      <Card title="Reference universe - 50 synthetic constituents (metadata only; first 5 are backed by mock receipt tokens)">
        <div className="max-h-96 overflow-auto">
          <table className="t"><thead><tr><th>#</th><th>Ticker</th><th>Name</th><th>Sector</th><th>Ref. weight</th><th>On-chain</th></tr></thead>
            <tbody>{DEMO_CONSTITUENTS.map((c) => (
              <tr key={c.ticker}><td>{c.rank}</td><td>{c.ticker}</td><td>{c.name}</td><td>{c.sector}</td><td>{pct(c.referenceWeightBps)}</td><td>{c.backedOnChain ? <Badge ok>{c.onChainSymbol}</Badge> : <span className="muted">metadata</span>}</td></tr>
            ))}</tbody></table>
        </div>
      </Card>
    </>
  )
}
