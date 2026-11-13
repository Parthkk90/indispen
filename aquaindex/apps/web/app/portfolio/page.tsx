'use client'
import { useAccount } from 'wagmi'
import { useApi } from '@/lib/api'
import { usd, num, short } from '@/lib/format'
import { Card, Connect, Loading, Stat } from '@/components/ui'

export default function Portfolio() {
  const { address } = useAccount()
  const q = useApi<any>(address ? `/api/portfolio/${address}` : null)
  if (!address) return <Connect />
  const d = q.data
  const total = d ? d.positions.reduce((a: bigint, p: any) => a + BigInt(p.value), 0n) : 0n
  const invested = d ? d.positions.reduce((a: bigint, p: any) => a + BigInt(p.investedUsdc), 0n) : 0n
  const investedUsd = invested * 10n ** 12n
  const pnl = total - investedUsd
  return (
    <>
      <h1 className="text-2xl font-bold">Portfolio</h1>
      <Loading q={q} />
      {d && (
        <>
          <div className="grid gap-4 md:grid-cols-4">
            <Stat label="Index value" value={usd(total)} />
            <Stat label="Invested (subscriptions)" value={usd(investedUsd)} sub="from indexed Subscribed events" />
            <Stat label="Unrealised P/L" value={<span className={pnl >= 0n ? 'text-emerald-300' : 'text-rose-300'}>{usd(pnl)}</span>} sub="value − subscribed; ignores secondary-market trades" />
            <Stat label="Wallet mUSDC" value={num(d.usdc, 6, 2)} />
          </div>
          <Card title="Positions">
            <table className="t"><thead><tr><th>Index</th><th>Shares</th><th>NAV/share</th><th>Value</th></tr></thead>
              <tbody>{d.positions.map((p: any) => <tr key={p.indexId}><td>{p.symbol}</td><td>{num(p.shares)}</td><td>{usd(p.navPerShare, 4)}</td><td>{usd(p.value)}</td></tr>)}</tbody></table>
          </Card>
          <Card title="Transaction history">
            {d.activity.length === 0 ? <p className="muted">No indexed events for this address.</p> : (
              <table className="t"><thead><tr><th>Time</th><th>Event</th><th>Tx</th></tr></thead>
                <tbody>{d.activity.map((e: any) => <tr key={e.id}><td>{new Date(e.timestamp).toLocaleString()}</td><td>{e.kind}</td><td><a className="underline" target="_blank" href={`https://sepolia.etherscan.io/tx/${e.txHash}`}>{short(e.txHash)}</a></td></tr>)}</tbody></table>
            )}
          </Card>
        </>
      )}
    </>
  )
}
