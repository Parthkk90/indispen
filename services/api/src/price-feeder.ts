import { createWalletClient, http, parseAbi, parseUnits, type Hex } from 'viem'
import { privateKeyToAccount } from 'viem/accounts'
import { sepolia } from 'viem/chains'
import { client, addr, RPC, D } from './chain'
const navOracleAbi = parseAbi(['function setPrice(address asset, uint256 price)'])

/** Pushes live CoinGecko USD prices into NAVOracle (mock token <- real coin). Needs PRICE_UPDATER_ROLE; key from FEEDER_KEY. */
const key = process.env.FEEDER_KEY as Hex | undefined
if (!key) throw new Error('FEEDER_KEY is required')
const wallet = createWalletClient({ account: privateKeyToAccount(key), chain: sepolia, transport: http(RPC) })
const ids: Record<string, string> = { mBTC: 'bitcoin', mETH: 'ethereum', mSOL: 'solana', mLINK: 'chainlink', mUNI: 'uniswap' }

async function tick() {
  const r = await fetch(`https://api.coingecko.com/api/v3/simple/price?vs_currencies=usd&ids=${Object.values(ids).join(',')}`)
  if (!r.ok) throw new Error(`coingecko ${r.status}`)
  const px = (await r.json()) as Record<string, { usd: number }>
  for (const [sym, id] of Object.entries(ids)) {
    const usd = px[id]?.usd
    if (!usd) continue
    const hash = await wallet.writeContract({ address: addr('oracle'), abi: navOracleAbi, functionName: 'setPrice', args: [D[sym] as `0x${string}`, parseUnits(String(usd), 18)] })
    console.log(`[feeder] ${sym} = $${usd}`, hash)
    await client.waitForTransactionReceipt({ hash }) // sequential keeps nonces ordered
  }
}
await tick()
if (!process.argv.includes('--once')) setInterval(() => tick().catch((e) => console.error('[feeder]', e.message)), Number(process.env.FEEDER_POLL ?? 600) * 1000)
