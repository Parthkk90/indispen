/**
 * India 50 Demo Index reference universe: 50 SYNTHETIC metadata entries (invented names/tickers, not a licensed
 * Nifty 50 product). Only the first five are backed on-chain by mock receipt tokens; the rest are metadata only.
 */
const sectors = ['Financials', 'IT Services', 'Energy', 'Consumer', 'Industrials', 'Healthcare', 'Materials', 'Telecom', 'Utilities', 'Autos']
const onChain = ['mRELI', 'mTCS', 'mHDFC', 'mINFY', 'mICICI']

export interface DemoConstituent {
  rank: number
  ticker: string
  name: string
  sector: string
  referenceWeightBps: number
  backedOnChain: boolean
  onChainSymbol: string | null
}

export const DEMO_CONSTITUENTS: DemoConstituent[] = Array.from({ length: 50 }, (_, i) => ({
  rank: i + 1,
  ticker: `DEMO${String(i + 1).padStart(2, '0')}`,
  name: `Demo Company ${String(i + 1).padStart(2, '0')}`,
  sector: sectors[i % sectors.length],
  referenceWeightBps: i < 5 ? 400 : Math.round(8000 / 45),
  backedOnChain: i < 5,
  onChainSymbol: i < 5 ? onChain[i] : null
}))
