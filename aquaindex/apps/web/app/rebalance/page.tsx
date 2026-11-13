'use client'
import { useAccount, useReadContract } from 'wagmi'
import { Bar, BarChart, CartesianGrid, ReferenceLine, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import { rebalanceManagerAbi } from '@aquaindex/shared'
import { D } from '@/lib/config'
import { useApi } from '@/lib/api'
import { usd, num, pct } from '@/lib/format'
import { Badge, Card, Loading } from '@/components/ui'

export default function Rebalance() {
  const q = useApi<any>('/api/indices/1/rebalance')
  const act = useApi<any[]>('/api/indices/1/activity')
  const { address } = useAccount()
  const roleHash = useReadContract({ address: D.rebalanceManager, abi: rebalanceManagerAbi, functionName: 'REBALANCER_ROLE' })
  const has = useReadContract({ address: D.rebalanceManager, abi: rebalanceManagerAbi, functionName: 'hasRole', args: [roleHash.data as `0x${string}`, address!], query: { enabled: !!roleHash.data && !!address } })
  const d = q.data
  const rebalanced = (act.data ?? []).filter((e) => e.kind === 'Rebalanced')
  return (
    <>
      <h1 className="text-2xl font-bold">Rebalancing</h1>
      <Loading q={q} />
      {d && (
        <>
          <Card title="Current vs target - drift (% of NAV)">
            <div className="h-64"><ResponsiveContainer><BarChart data={d.drift.map((x: any) => ({ name: x.symbol, drift: x.driftBps / 100 }))}><CartesianGrid stroke="#1f2937" /><XAxis dataKey="name" stroke="#8b97ab" /><YAxis stroke="#8b97ab" /><Tooltip contentStyle={{ background: '#121826', border: '1px solid #1f2937' }} /><ReferenceLine y={0} stroke="#475569" /><Bar dataKey="drift" fill="#f59e0b" /></BarChart></ResponsiveContainer></div>
            <table className="t mt-3"><thead><tr><th>Asset</th><th>Current</th><th>Target</th><th>Drift</th><th>Needed</th></tr></thead>
              <tbody>{d.drift.map((x: any) => <tr key={x.asset}><td>{x.symbol}</td><td>{usd(x.currentValue)}</td><td>{usd(x.targetValue)}</td><td>{pct(x.driftBps)}</td><td>{BigInt(x.deltaValue) >= 0n ? 'buy' : 'sell'} {usd((BigInt(x.deltaValue) < 0n ? -BigInt(x.deltaValue) : BigInt(x.deltaValue)).toString())}</td></tr>)}</tbody></table>
          </Card>
          <Card title="Proposal (computed by RebalanceManager.propose, read-only)">
            {d.proposals.length === 0 ? <p className="muted">Nothing to rebalance above the $1 threshold.</p> : (
              <table className="t"><thead><tr><th>Sell</th><th>Buy</th><th>Value</th></tr></thead>
                <tbody>{d.proposals.map((p: any, i: number) => <tr key={i}><td>{p.sellSymbol} {num(p.sellAmount, p.sellSymbol === 'mUSDC' ? 6 : 18, 4)}</td><td>{p.buySymbol}</td><td>{usd(p.sellValue)}</td></tr>)}</tbody></table>
            )}
            <p className="mt-3 text-xs muted">Limits enforced on-chain: max {pct(d.limits.maxTradeBps)} of NAV per trade, max {pct(d.limits.maxSlippageBps)} oracle slippage, and drift may not increase.</p>
          </Card>
          <Card title="Execute">
            <p className="text-sm">Your wallet: {address ? <Badge ok={!!has.data}>{has.data ? 'REBALANCER_ROLE' : 'no REBALANCER_ROLE'}</Badge> : 'not connected'}</p>
            <p className="mt-2 text-sm muted">Execution calls <code>RebalanceManager.execute(...)</code> with a counterparty SwapVM order (an Aqua strategy of the AquaIndex router) and taker data built for the manager as taker. The browser does not assemble counterparty orders; the reference flow is <code>script/Demo.s.sol</code> (rebalance step). Trades revert on-chain if they break the limits above.</p>
          </Card>
          <Card title="Executed rebalances (indexed events)">
            {rebalanced.length === 0 ? <p className="muted">None indexed.</p> : <table className="t"><thead><tr><th>Time</th><th>Sold</th><th>Bought</th><th>Tx</th></tr></thead><tbody>{rebalanced.map((e) => <tr key={e.id}><td>{new Date(e.timestamp).toLocaleString()}</td><td>{e.data.sold}</td><td>{e.data.bought}</td><td><a className="underline" target="_blank" href={`https://sepolia.etherscan.io/tx/${e.txHash}`}>tx</a></td></tr>)}</tbody></table>}
          </Card>
        </>
      )}
    </>
  )
}
