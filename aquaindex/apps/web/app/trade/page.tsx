'use client'
import { useMemo, useState } from 'react'
import { useAccount, useReadContract } from 'wagmi'
import { parseUnits, type Hex } from 'viem'
import { Line, LineChart, CartesianGrid, ReferenceLine, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import { aquaIndexSwapVMRouterAbi, mockERC20Abi } from '@aquaindex/shared'
import { buildTakerData } from '@aquaindex/swapvm-sdk/taker'
import { D } from '@/lib/config'
import { useApi } from '@/lib/api'
import { useTx } from '@/lib/useTx'
import { decodeOrder } from '@/lib/strategies'
import { usd, num, short } from '@/lib/format'
import { Badge, Card, Connect, Loading, Source, TxStatus } from '@/components/ui'

export default function Trade() {
  const { address } = useAccount()
  const strategies = useApi<any[]>('/api/strategies')
  const ix = useApi<any>('/api/indices/1')
  const [side, setSide] = useState<'buy' | 'sell'>('buy')
  const navPs = ix.data?.nav ? Number(ix.data.nav.navPerShare) / 1e18 : 0
  const cap = (s: any) => {
    const shareFirst = s.tokenA.toLowerCase() === ix.data?.share.toLowerCase()
    const sh = Number(shareFirst ? s.virtualBalances?.tokenA ?? 0 : s.virtualBalances?.tokenB ?? 0) / 1e18
    const us = Number(shareFirst ? s.virtualBalances?.tokenB ?? 0 : s.virtualBalances?.tokenA ?? 0) / 1e6
    return { sh, us, maxBuyPay: sh * navPs, maxSellPay: navPs ? us / navPs : 0 } // approx., before spread/skew
  }
  const [sel, setSel] = useState<string>('')
  const live = useMemo(() => {
    const l = (strategies.data ?? []).filter((s) => s.isIndexStrategy && !s.docked)
    return l.sort((a, b) => (side === 'buy' ? cap(b).maxBuyPay - cap(a).maxBuyPay : cap(b).maxSellPay - cap(a).maxSellPay))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [strategies.data, side, navPs, ix.data?.share])
  const strat = live.find((s) => s.hash === sel) ?? live[0]
  const [amt, setAmt] = useState('1000')
  const c = strat ? cap(strat) : null
  const maxPay = c ? (side === 'buy' ? c.maxBuyPay * 0.995 : c.maxSellPay * 0.995) : 0
  const overCap = !!c && Number(amt || 0) > maxPay
  const [slip, setSlip] = useState('0.5')
  const [localErr, setLocalErr] = useState('')

  const share = ix.data?.share as `0x${string}` | undefined
  const tokenIn = (side === 'buy' ? D.usdc : share) as `0x${string}` | undefined
  const decIn = side === 'buy' ? 6 : 18
  const raw = (() => { try { return parseUnits(amt || '0', decIn) } catch { return 0n } })()
  const quote = useApi<any>(strat && address && tokenIn && raw > 0n ? `/api/quote?strategy=${strat.hash}&tokenIn=${tokenIn}&amount=${raw}&taker=${address}` : null, 8000)
  const trades = useApi<any[]>(strat ? `/api/strategies/${strat.hash}/trades` : null)
  const allowance = useReadContract({ address: tokenIn, abi: mockERC20Abi, functionName: 'allowance', args: [address!, D.router], query: { enabled: !!address && !!tokenIn } })
  const { state, run } = useTx()
  if (!address) return <Connect />

  const q = quote.data
  const outDec = side === 'buy' ? 18 : 6
  const minOut = q?.ok ? (BigInt(q.amountOut) * BigInt(Math.round((100 - Number(slip)) * 100))) / 10_000n : 0n
  const idxIn = strat ? (strat.instructions ?? []).find((i: any) => i.opcode === 0xe3)?.args : null

  const swap = async () => {
    if (!strat || !tokenIn || !q?.ok) return
    if (!strat.orderData) { setLocalErr('Strategy order data missing from the API response; restart the API.'); return }
    setLocalErr('')
    let order: ReturnType<typeof decodeOrder>
    try { order = decodeOrder(strat.orderData as Hex) } catch (e) { setLocalErr('Could not decode strategy order: ' + (e as Error).message.split('\n')[0]); return }
    const isAToB = tokenIn.toLowerCase() < q.tokenOut.toLowerCase()
    const takerData = buildTakerData({ isExactIn: true, isAToB, threshold: minOut })
    const steps: Parameters<typeof run>[0] = []
    if ((allowance.data ?? 0n) < raw) steps.push({ label: 'Approve', req: { address: tokenIn, abi: mockERC20Abi, functionName: 'approve', args: [D.router, raw] } })
    steps.push({ label: 'Swap via AquaIndex router', req: { address: D.router, abi: aquaIndexSwapVMRouterAbi, functionName: 'swap', args: [order, raw, takerData] } })
    if (await run(steps)) { quote.refetch(); trades.refetch(); strategies.refetch(); allowance.refetch() }
  }

  const series = [...(trades.data ?? [])].reverse().map((t) => {
    const buy = t.tokenIn.toLowerCase() === D.usdc.toLowerCase()
    const usdcAmt = Number(buy ? t.amountIn : t.amountOut) / 1e6
    const shareAmt = Number(buy ? t.amountOut : t.amountIn) / 1e18
    return { t: new Date(t.timestamp).toLocaleTimeString(), price: usdcAmt / shareAmt }
  })
  const navRef = q?.navReferenceQuotePerShare ?? (ix.data?.nav ? Number(ix.data.nav.navPerShare) / 1e18 : undefined)

  return (
    <>
      <h1 className="text-2xl font-bold">Trading terminal <span className="muted text-base">I50D / mUSDC</span></h1>
      <Loading q={strategies} />
      {live.length === 0 && !strategies.isLoading && <p className="muted">No live AquaIndex strategies. Ship one from the Market maker page.</p>}
      {strat && (
        <div className="grid gap-4 md:grid-cols-3">
          <div className="space-y-4 md:col-span-2">
            <Card title="Liquidity source">
              <select className="input" value={strat.hash} onChange={(e) => setSel(e.target.value)}>
                {live.map((s) => <option key={s.hash} value={s.hash}>{short(s.hash)} · maker {short(s.maker)} · {num(s.virtualBalances?.tokenA, 18, 2)}/{num(s.virtualBalances?.tokenB, 6, 0)}</option>)}
              </select>
              <div className="mt-2 flex flex-wrap items-center gap-2 text-sm">
                <Source>AquaIndex custom SwapVM router</Source>
                <span className="muted">router {short(D.router)} · opcodes {strat.instructions?.map((i: any) => '0x' + i.opcode.toString(16)).join(' ')}</span>
              </div>
              {idxIn && <p className="mt-2 text-xs muted">Max trade (on-chain, in strategy hash): {num(idxIn.maxAmountIn, 6, 0)} mUSDC in</p>}
            </Card>
            <Card title="Price vs NAV">
              <div className="h-56">
                {series.length ? (
                  <ResponsiveContainer><LineChart data={series}><CartesianGrid stroke="#1f2937" /><XAxis dataKey="t" stroke="#8b97ab" /><YAxis stroke="#8b97ab" domain={['auto', 'auto']} /><Tooltip contentStyle={{ background: '#121826', border: '1px solid #1f2937' }} />{navRef && <ReferenceLine y={navRef} stroke="#34d399" strokeDasharray="4 4" label={{ value: 'NAV', fill: '#34d399' }} />}<Line dataKey="price" stroke="#60a5fa" dot /></LineChart></ResponsiveContainer>
                ) : <p className="muted">No executed trades on this strategy yet.</p>}
              </div>
            </Card>
          </div>
          <Card title="Swap">
            <div className="flex gap-2 mb-3">
              <button className={side === 'buy' ? 'btn' : 'btn-ghost'} onClick={() => setSide('buy')}>Buy I50D</button>
              <button className={side === 'sell' ? 'btn' : 'btn-ghost'} onClick={() => setSide('sell')}>Sell I50D</button>
            </div>
            <label className="text-sm muted">Pay ({side === 'buy' ? 'mUSDC' : 'I50D'})</label>
            <input className="input" value={amt} onChange={(e) => setAmt(e.target.value)} />
            {c && (
              <p className="mt-1 text-xs muted">
                This strategy can fill about {maxPay.toLocaleString(undefined, { maximumFractionDigits: 2 })} {side === 'buy' ? 'mUSDC' : 'I50D'}{' '}
                <button className="underline" onClick={() => setAmt(String(Math.floor(maxPay * 100) / 100))}>max</button>
                {' '}(holds {c.sh.toLocaleString(undefined, { maximumFractionDigits: 2 })} I50D / {c.us.toLocaleString(undefined, { maximumFractionDigits: 0 })} mUSDC)
              </p>
            )}
            {overCap && <p className="mt-1 text-xs text-amber-300">Amount exceeds this strategy&apos;s liquidity. Pick another liquidity source or reduce the amount.</p>}
            <label className="mt-2 block text-sm muted">Slippage tolerance (%)</label>
            <input className="input" value={slip} onChange={(e) => setSlip(e.target.value)} />
            <div className="mt-3 space-y-1 text-sm">
              {quote.isLoading && <p className="muted">Quoting on-chain…</p>}
              {q?.ok && (
                <>
                  <div>You receive: <b>{num(q.amountOut, outDec, 6)}</b> {side === 'buy' ? 'I50D' : 'mUSDC'}</div>
                  <div>Min received: {num(minOut, outDec, 6)}</div>
                  <div>NAV reference: {q.navReferenceQuotePerShare ? usd((BigInt(Math.round(q.navReferenceQuotePerShare * 1e6)) * 10n ** 12n).toString(), 4) : '-'} / share</div>
                  <div>Premium / discount vs NAV: <Badge ok={Math.abs(q.premiumDiscountPct ?? 0) < 1}>{q.premiumDiscountPct?.toFixed(3)}%</Badge> <span className="muted text-xs">(spread + inventory skew)</span></div>
                  <Source>AquaIndex custom SwapVM router</Source>
                </>
              )}
              {q && !q.ok && (
                <div className="text-rose-300">
                  {/IndexSkewInsufficientLiquidity/.test(q.reverted) ? `Not enough liquidity: this strategy can fill at most about ${maxPay.toLocaleString(undefined, { maximumFractionDigits: 2 })} ${side === 'buy' ? 'mUSDC' : 'I50D'}. Reduce the amount or press "max".` : 'Blocked on-chain:'} <code>{q.reverted}</code>
                  {/IndexNavGuard(Deviation|Stale)/.test(q.reverted) && <p className="mt-1 text-xs">The published NAV no longer matches the index (share supply changed or snapshot is old). Republish NAV (Overview page, publisher wallet, or the keeper) and retry.</p>}
                </div>
              )}
            </div>
            {strat && address.toLowerCase() === strat.maker.toLowerCase() && <p className="mt-2 text-xs text-amber-300">You are this strategy&apos;s maker: trading against yourself settles on-chain but leaves your balances unchanged. Use a different wallet to see a real fill.</p>}
            <button className="btn mt-3 w-full" disabled={!q?.ok || overCap || state.status === 'signing' || state.status === 'pending'} onClick={swap}>Swap</button>
            {localErr && <p className="mt-2 text-sm text-rose-300">{localErr}</p>}
            <TxStatus state={state} />
          </Card>
        </div>
      )}
    </>
  )
}
