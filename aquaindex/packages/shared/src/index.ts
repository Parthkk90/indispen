import deployment from './deployment.sepolia.json'
export * from './abis'
export { deployment }
export type Deployment = typeof deployment

export const STATUS = ['NONE', 'ACTIVE', 'PAUSED', 'RETIRED'] as const
export const ASSET_SYMBOLS = ['mRELI', 'mTCS', 'mHDFC', 'mINFY', 'mICICI'] as const

/** Synthetic demo constituents (NOT a licensed Nifty 50 product). First five are backed by mock receipt tokens. */
export const DEMO_DISCLAIMER = 'Synthetic demo data on Sepolia. Not a licensed Nifty 50 product. Tokens have no value.'
export * from './constituents'
