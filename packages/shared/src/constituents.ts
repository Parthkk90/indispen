/**
 * Crypto Blue Chip reference universe (metadata only). Weights are approximate market-cap based.
 * Only the first five are backed on-chain by mock receipt tokens (Sepolia, no value).
 */
const onChain = ['mBTC', 'mETH', 'mSOL', 'mLINK', 'mUNI']

export interface DemoConstituent {
  rank: number
  ticker: string
  name: string
  sector: string
  referenceWeightBps: number
  backedOnChain: boolean
  onChainSymbol: string | null
}

const tokens: [string, string, string, number][] = [
  ['BTC', 'Bitcoin', 'Store of Value', 3000],
  ['ETH', 'Ethereum', 'Smart Contract L1', 2500],
  ['SOL', 'Solana', 'Smart Contract L1', 1000],
  ['BNB', 'BNB', 'Exchange / L1', 900],
  ['LINK', 'Chainlink', 'Oracles', 500],
  ['UNI', 'Uniswap', 'DeFi / DEX', 400],
  ['AAVE', 'Aave', 'DeFi / Lending', 700],
  ['ARB', 'Arbitrum', 'Layer 2', 500],
  ['OP', 'Optimism', 'Layer 2', 300],
  ['MKR', 'Maker', 'DeFi / Stablecoin', 200]
]

export const DEMO_CONSTITUENTS: DemoConstituent[] = tokens.map(([ticker, name, sector, referenceWeightBps], i) => ({
  rank: i + 1,
  ticker,
  name,
  sector,
  referenceWeightBps,
  backedOnChain: i < 5,
  onChainSymbol: i < 5 ? onChain[i] : null
}))
