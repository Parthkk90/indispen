import { formatUnits } from 'viem'

import { loadDeployment } from './deployment'
import { protocolEvents } from './indexer'

const KINDS = ['NONE', 'REBALANCE', 'SWAP', 'PAY'] as const
const HEADER = ['time_utc', 'tx_hash', 'kind', 'asset_out', 'amount_out', 'asset_in', 'amount_in', 'ref_value_out_wad', 'recipient', 'operator', 'capability_id']

const csv = (cell: unknown) => (/[",\n]/.test(String(cell)) ? `"${String(cell).replaceAll('"', '""')}"` : String(cell))

/**
 * One row per on-chain execution receipt. Every swap/rebalance/pay is a "transfer" of a virtual digital asset in Indian
 * tax terms (s.115BBH / s.194S), so the owner needs a per-fill record. Amounts are human units; INR valuation is left to
 * the filer (the protocol's reference price is not a market quote). Built purely from public chain data: no PII.
 */
export async function ledgerCsv(bucketId?: string): Promise<string> {
  const tokens = new Map(loadDeployment().evm.tokens.map((t) => [t.address.toLowerCase(), t]))
  const amount = (addr: string, raw: unknown) => {
    const t = tokens.get(addr.toLowerCase())
    return t ? formatUnits(BigInt(String(raw)), t.decimals) : String(raw)
  }
  const sym = (addr: string) => tokens.get(addr.toLowerCase())?.symbol ?? addr

  const { events } = await protocolEvents()
  const rows = events
    .filter((e) => e.eventName === 'ExecutionRecorded')
    .filter((e) => !bucketId || String(e.args.bucketId).toLowerCase() === bucketId.toLowerCase())
    .reverse() // oldest first: cost-basis order
    .map((e) => {
      const r = e.args.receipt as Record<string, string>
      return [
        e.timestamp ? new Date(e.timestamp * 1000).toISOString() : '',
        e.txHash,
        KINDS[Number(r.kind)] ?? r.kind,
        sym(r.tokenOut!), amount(r.tokenOut!, r.amountOut),
        sym(r.tokenIn!), amount(r.tokenIn!, r.amountIn),
        r.valueOut, r.recipient, r.operator, e.args.capabilityId,
      ]
    })
  return [HEADER, ...rows].map((row) => row.map(csv).join(',')).join('\n') + '\n'
}
