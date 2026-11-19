import deployment from './deployment.sepolia.json'
export * from './abis'
export { deployment }
export type Deployment = typeof deployment

export const STATUS = ['NONE', 'ACTIVE', 'PAUSED', 'RETIRED'] as const
export const ASSET_SYMBOLS = ['mRELI', 'mTCS', 'mHDFC', 'mINFY', 'mICICI'] as const

/** Crypto blue-chip reference constituents. First five are backed by mock receipt tokens. */
export const DEMO_DISCLAIMER = 'Crypto Blue Chip demo index on Sepolia. Tokens have no value.'
export * from './constituents'
