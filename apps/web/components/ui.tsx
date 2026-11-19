'use client'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { useAccount, useConnect, useDisconnect, useSwitchChain } from 'wagmi'
import { sepolia } from 'wagmi/chains'
import clsx from 'clsx'
import { EXPLORER } from '@/lib/config'
import { short } from '@/lib/format'
import type { TxState } from '@/lib/useTx'

const links = [
  ['/', 'Overview'], ['/explore', 'Explore'], ['/portfolio', 'Portfolio'], ['/invest', 'Invest'],
  ['/redeem', 'Redeem'], ['/trade', 'Trade'], ['/maker', 'Market maker'], ['/rebalance', 'Rebalance']
] as const

export function Header() {
  const path = usePathname()
  const { address, chainId, isConnected } = useAccount()
  const { connectors, connect } = useConnect()
  const { disconnect } = useDisconnect()
  const { switchChain } = useSwitchChain()
  return (
    <header className="border-b border-slate-800">
      <div className="mx-auto flex max-w-6xl flex-wrap items-center gap-4 px-4 py-3">
        <span className="font-bold tracking-tight">AquaIndex</span>
        <nav className="flex flex-wrap gap-3 text-sm">
          {links.map(([h, l]) => (
            <Link key={h} href={h} className={clsx('hover:text-white', path === h ? 'text-white font-semibold' : 'muted')}>{l}</Link>
          ))}
        </nav>
        <div className="ml-auto flex items-center gap-2 text-sm">
          <span className="rounded bg-amber-500/15 px-2 py-0.5 text-amber-300">Sepolia testnet</span>
          {isConnected && chainId !== sepolia.id && <button className="btn-ghost" onClick={() => switchChain({ chainId: sepolia.id })}>Switch to Sepolia</button>}
          {isConnected ? (
            <button className="btn-ghost" onClick={() => disconnect()}>{short(address)}</button>
          ) : (
            <button className="btn" onClick={() => connect({ connector: connectors[0] })}>Connect wallet</button>
          )}
        </div>
      </div>
      <div className="bg-amber-500/10 px-4 py-1 text-center text-xs text-amber-200">
        Crypto Blue Chip demo index on Sepolia. Tokens have no value. Unaudited.
      </div>
    </header>
  )
}

export const Card = ({ title, children, className }: { title?: string; children: React.ReactNode; className?: string }) => (
  <section className={clsx('card', className)}>
    {title && <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide muted">{title}</h2>}
    {children}
  </section>
)

export const Stat = ({ label, value, sub }: { label: string; value: React.ReactNode; sub?: React.ReactNode }) => (
  <div className="card">
    <div className="text-xs uppercase muted">{label}</div>
    <div className="mt-1 text-2xl font-semibold">{value}</div>
    {sub && <div className="mt-1 text-xs muted">{sub}</div>}
  </div>
)

export const Badge = ({ ok, children }: { ok: boolean; children: React.ReactNode }) => (
  <span className={clsx('rounded px-2 py-0.5 text-xs font-medium', ok ? 'bg-emerald-500/15 text-emerald-300' : 'bg-rose-500/15 text-rose-300')}>{children}</span>
)

export const Source = ({ children }: { children: React.ReactNode }) => (
  <span className="rounded bg-indigo-500/15 px-2 py-0.5 text-xs text-indigo-300">{children}</span>
)

export function TxStatus({ state }: { state: TxState }) {
  if (state.status === 'idle') return null
  return (
    <div className={clsx('mt-3 rounded-lg border p-3 text-sm', state.status === 'error' ? 'border-rose-700 text-rose-300' : 'border-slate-700')}>
      {state.status === 'signing' && <>Confirm in wallet: {state.step}…</>}
      {state.status === 'pending' && <>Waiting for confirmation: {state.step}… <a className="underline" target="_blank" href={`${EXPLORER}/tx/${state.hash}`}>{short(state.hash)}</a></>}
      {state.status === 'success' && <>Confirmed: {state.step} - <a className="underline" target="_blank" href={`${EXPLORER}/tx/${state.hash}`}>{short(state.hash)}</a></>}
      {state.status === 'error' && <>Error: {state.error}</>}
    </div>
  )
}

export const Loading = ({ q }: { q: { isLoading: boolean; error: unknown } }) =>
  q.isLoading ? <p className="muted">Loading live chain data…</p> : q.error ? <p className="text-rose-300">API error: {(q.error as Error).message}. Is the API running on port 4001?</p> : null

export const Connect = () => <p className="muted">Connect a wallet (top right) to continue.</p>
