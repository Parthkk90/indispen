'use client'
import { useState } from 'react'
import { useAccount, useReadContract } from 'wagmi'
import { parseUnits, type Hex } from 'viem'
import { aquaAbi, aquaIndexStrategyManagerAbi, mockERC20Abi, indexShareAbi } from '@aquaindex/shared'
import { API, D } from '@/lib/config'
import { useApi } from '@/lib/api'
import { useTx } from '@/lib/useTx'
import { PRESETS, encodeOrder } from '@/lib/strategies'
import { num, short, usd, ago } from '@/lib/format'
import { Badge, Card, Connect, Source, TxStatus } from '@/components/ui'

const ZERO = '0x0000000000000000000000000000000000000000'
const ZERO32 = ('0x' + '00'.repeat(32)) as Hex

export default function Maker() {
  const { address } = useAccount()
  const ix = useApi<any>('/api/indices/1')
  const mine = useApi<any[]>(address ? `/api/strategies?maker=${address}` : null)
  const [preset, setPreset] = useState<'A' | 'B' | 'C'>('A')
  const [f, setF] = useState<Record<string, string>>({ premiumBps: '0', feeBps: '0', targetShareBps: '5000', minLiquidityOut: '0', maxAmountOut: '0', shareAmt: '100', usdcAmt: '10000' })
  const [built, setBuilt] = useState<any>(null)
  const [err, setErr] = useState('')
  const { state, run } = useTx()
  const shareBal = useReadContract({ address: ix.data?.share, abi: indexShareAbi, functionName: 'balanceOf', args: [address!], query: { enabled: !!address && !!ix.data } })
  const aquaShareAllow = useReadContract({ address: ix.data?.share, abi: indexShareAbi, functionName: 'allowance', args: [address!, D.aqua], query: { enabled: !!address && !!ix.data } })
  const aquaUsdcAllow = useReadContract({ address: D.usdc, abi: mockERC20Abi, functionName: 'allowance', args: [address!, D.aqua], query: { enabled: !!address } })

  if (!address) return <Connect />
  const p = PRESETS[preset]
  const val = (k: keyof typeof p | string) => f[k as string] ?? String((p as any)[k])
  const set = (k: string, v: string) => setF({ ...f, [k]: v })

  const params = () => ({
    kind: p.kind, maker: address, navSource: D.oracle, indexId: '1', indexToken: ix.data.share, quoteToken: D.usdc,
    expiry: Math.floor(Date.now() / 1000) + 7 * 86400, salt: String(Date.now()),
    maxNavAge: Number(val('maxNavAge')), minEpoch: '1', maxNavDeviationBps: Number(val('maxNavDeviationBps')),
    premiumBps: Number(val('premiumBps')), maxPremiumBps: Number(val('maxPremiumBps')), maxDiscountBps: Number(val('maxDiscountBps')),
    spreadBps: Number(val('spreadBps')), feeBps: Number(val('feeBps')), targetShareBps: Number(val('targetShareBps')),
    maxSkewBps: Number(val('maxSkewBps')), slopeBps: Number(val('slopeBps')), maxAdjustBps: Number(val('maxAdjustBps')),
    maxAmountIn: val('maxAmountIn'), maxAmountOut: val('maxAmountOut'), minLiquidityOut: val('minLiquidityOut'),
    capabilityRegistry: ZERO, capabilityId: ZERO32
  })

  const build = async () => {
    setErr(''); setBuilt(null)
    try {
      const body = params()
      const r = await fetch(`${API}/api/strategy/build`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ params: body }) })
      const j = await r.json()
      if (!r.ok) throw new Error(j.error)
      setBuilt({ ...j, params: body })
    } catch (e) { setErr((e as Error).message) }
  }

  const ship = async () => {
    if (!built) return
    const order = { maker: built.order.maker, traits: BigInt(built.order.traits), data: built.order.data as Hex }
    const shareRaw = parseUnits(val('shareAmt'), 18)
    const usdcRaw = parseUnits(val('usdcAmt'), 6)
    const [a, b] = ix.data.share.toLowerCase() < D.usdc.toLowerCase() ? [ix.data.share, D.usdc] : [D.usdc, ix.data.share]
    const amounts = a.toLowerCase() === D.usdc.toLowerCase() ? [usdcRaw, shareRaw] : [shareRaw, usdcRaw]
    const steps: Parameters<typeof run>[0] = []
    if ((aquaShareAllow.data ?? 0n) < shareRaw) steps.push({ label: 'Approve I50D to Aqua', req: { address: ix.data.share, abi: indexShareAbi, functionName: 'approve', args: [D.aqua, shareRaw] } })
    if ((aquaUsdcAllow.data ?? 0n) < usdcRaw) steps.push({ label: 'Approve mUSDC to Aqua', req: { address: D.usdc, abi: mockERC20Abi, functionName: 'approve', args: [D.aqua, usdcRaw] } })
    steps.push({ label: 'Ship strategy to Aqua', req: { address: D.aqua, abi: aquaAbi, functionName: 'ship', args: [D.router, encodeOrder(order), [a, b], amounts] } })
    if (await run(steps)) { mine.refetch(); setBuilt(null) }
  }

  const dock = (s: any) => run([{ label: 'Dock strategy', req: { address: D.aqua, abi: aquaAbi, functionName: 'dock', args: [D.router, s.hash, [s.tokenA, s.tokenB]] } }]).then(() => mine.refetch())
  const nps = ix.data?.nav ? Number(ix.data.nav.navPerShare) / 1e18 : 0

  return (
    <>
      <h1 className="text-2xl font-bold">Market maker</h1>
      <Card title="1 · Configure strategy">
        <div className="flex flex-wrap gap-2">
          {(['A', 'B', 'C'] as const).map((k) => <button key={k} className={preset === k ? 'btn' : 'btn-ghost'} onClick={() => { setPreset(k); setF({ ...f }); }}>{PRESETS[k].label}</button>)}
        </div>
        <div className="mt-4 grid gap-3 md:grid-cols-4 text-sm">
          {[['premiumBps', 'Premium/discount (bps, signed)'], ['maxPremiumBps', 'Max premium (bps)'], ['maxDiscountBps', 'Max discount (bps)'], ['spreadBps', 'Spread (bps)'], ['feeBps', 'Fee (bps)'],
            ['maxNavAge', 'NAV max age (s)'], ['maxNavDeviationBps', 'NAV deviation (bps)'], ['targetShareBps', 'Target share inventory (bps)'], ['maxSkewBps', 'Max skew (bps)'], ['slopeBps', 'Skew slope (bps)'],
            ['maxAdjustBps', 'Max skew adjust (bps)'], ['maxAmountIn', 'Max trade in (raw)'], ['maxAmountOut', 'Max trade out (raw)'], ['minLiquidityOut', 'Min liquidity left (raw)']].map(([k, l]) => (
            <label key={k}><span className="muted">{l}</span><input className="input" value={val(k)} onChange={(e) => set(k, e.target.value)} /></label>
          ))}
        </div>
        <div className="mt-4 grid gap-3 md:grid-cols-2 text-sm">
          <label><span className="muted">I50D to allocate (wallet {num(shareBal.data)})</span><input className="input" value={val('shareAmt')} onChange={(e) => set('shareAmt', e.target.value)} /></label>
          <label><span className="muted">mUSDC to allocate</span><input className="input" value={val('usdcAmt')} onChange={(e) => set('usdcAmt', e.target.value)} /></label>
        </div>
        <p className="mt-2 text-xs muted">Allocation value: {usd((parseFloat(val('shareAmt') || '0') * nps * 1e18).toLocaleString('fullwide', { useGrouping: false }))} I50D vs ${val('usdcAmt')} mUSDC. Aqua keeps tokens in your wallet; allocations are virtual until a trade settles.</p>
        <button className="btn mt-3" disabled={!ix.data} onClick={build}>Build via on-chain StrategyManager</button>
        {err && <p className="mt-2 text-rose-300 text-sm">{err}</p>}
      </Card>

      {built && (
        <Card title="2 · Review and ship">
          <p className="text-sm">Strategy hash (Aqua key): <code>{built.hash}</code> <Source>{built.source}</Source></p>
          <table className="t mt-2"><thead><tr><th>Opcode</th><th>Instruction</th><th>Args</th></tr></thead>
            <tbody>{(built.instructions ?? []).map((i: any, k: number) => <tr key={k}><td>0x{i.opcode.toString(16)}</td><td>{i.name}</td><td className="text-xs muted break-all">{JSON.stringify(i.args)}</td></tr>)}</tbody></table>
          <p className="mt-2 text-xs muted">Aqua strategies are immutable: to change parameters dock this strategy and ship a new one.</p>
          <button className="btn mt-3" onClick={ship}>Ship strategy</button>
        </Card>
      )}
      <TxStatus state={state} />

      <Card title="Your strategies - health and liquidity">
        {(mine.data ?? []).length === 0 ? <p className="muted">No strategies shipped by this wallet.</p> : (
          <table className="t"><thead><tr><th>Hash</th><th>Status</th><th>Virtual I50D</th><th>Virtual mUSDC</th><th>Inventory (I50D %)</th><th>NAV max age</th><th>Trades</th><th /></tr></thead>
            <tbody>{mine.data!.map((s) => {
              const shareFirst = s.tokenA.toLowerCase() === ix.data?.share.toLowerCase()
              const sh = BigInt(shareFirst ? s.virtualBalances?.tokenA ?? 0 : s.virtualBalances?.tokenB ?? 0)
              const us = BigInt(shareFirst ? s.virtualBalances?.tokenB ?? 0 : s.virtualBalances?.tokenA ?? 0)
              const shVal = (Number(sh) / 1e18) * nps; const usVal = Number(us) / 1e6
              const invPct = shVal + usVal > 0 ? (100 * shVal) / (shVal + usVal) : 0
              const navAge = s.instructions?.find((i: any) => i.opcode === 0xe0)?.args?.maxNavAge
              const stale = navAge && ix.data?.snapshot.ageSeconds != null && ix.data.snapshot.ageSeconds > navAge
              return (
                <tr key={s.hash}><td>{short(s.hash)}</td><td>{s.docked ? <Badge ok={false}>docked</Badge> : <Badge ok>{s.isIndexStrategy ? 'live' : 'live (non-index)'}</Badge>}</td>
                  <td>{num(sh, 18, 3)}</td><td>{num(us, 6, 0)}</td><td>{s.isIndexStrategy ? invPct.toFixed(1) + '%' : '-'}</td>
                  <td>{navAge ? <span className={stale ? 'text-rose-300' : ''}>{navAge}s{stale ? ` (snapshot ${ago(ix.data.snapshot.ageSeconds)}: blocked)` : ''}</span> : '-'}</td><td>{s.trades}</td>
                  <td>{!s.docked && <button className="btn-ghost" onClick={() => dock(s)}>Dock</button>}</td></tr>)
            })}</tbody></table>
        )}
      </Card>
    </>
  )
}
