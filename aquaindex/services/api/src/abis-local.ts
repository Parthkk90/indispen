import { parseAbi } from 'viem'
import { navOracleAbi, indexRegistryAbi, indexVaultAbi, indexShareAbi, rebalanceManagerAbi, aquaIndexStrategyManagerAbi, aquaIndexSwapVMRouterAbi, aquaAbi, subscriptionManagerAbi, redemptionManagerAbi } from '@aquaindex/shared'

export const erc20Abiish = parseAbi([
  'function symbol() view returns (string)',
  'function decimals() view returns (uint8)',
  'function balanceOf(address) view returns (uint256)',
  'function allowance(address,address) view returns (uint256)'
])
export { navOracleAbi, indexRegistryAbi, indexVaultAbi, indexShareAbi, rebalanceManagerAbi, aquaIndexStrategyManagerAbi, aquaIndexSwapVMRouterAbi, aquaAbi, subscriptionManagerAbi, redemptionManagerAbi }
