import { formatUnits } from 'viem'

export const usd = (v1e18: string | bigint | null | undefined, dp = 2) =>
  v1e18 == null ? '-' : '$' + Number(formatUnits(BigInt(v1e18), 18)).toLocaleString(undefined, { maximumFractionDigits: dp, minimumFractionDigits: dp })
export const num = (v: string | bigint | null | undefined, dec = 18, dp = 4) =>
  v == null ? '-' : Number(formatUnits(BigInt(v), dec)).toLocaleString(undefined, { maximumFractionDigits: dp })
export const pct = (bps: number | null | undefined) => (bps == null ? '-' : (bps / 100).toFixed(2) + '%')
export const short = (a?: string) => (a ? a.slice(0, 6) + '…' + a.slice(-4) : '')
export const ago = (sec: number | null | undefined) => {
  if (sec == null) return 'never'
  if (sec < 90) return `${sec}s ago`
  if (sec < 5400) return `${Math.round(sec / 60)} min ago`
  return `${(sec / 3600).toFixed(1)} h ago`
}
