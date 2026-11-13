"""Regenerate packages/shared/src/abis.ts from forge artifacts. Run `forge build` first."""
import json
names = ['IndexRegistry', 'NAVOracle', 'IndexVault', 'IndexShare', 'SubscriptionManager', 'RedemptionManager', 'RebalanceManager',
         'AquaIndexStrategyManager', 'AquaIndexSwapVMRouter', 'AquaIndexCapabilityRegistry', 'MockERC20']
out = "// Generated from forge artifacts (scripts/gen-abis.py). Do not edit.\n"
for n in names:
    key = n[0].lower() + n[1:]
    if n == 'NAVOracle':
        key = 'navOracle'
    out += f"export const {key}Abi = {json.dumps(json.load(open(f'out/{n}.sol/{n}.json'))['abi'])} as const\n"
out += f"export const aquaAbi = {json.dumps(json.load(open('out/AquaRouter.sol/AquaRouter.json'))['abi'])} as const\n"
open('packages/shared/src/abis.ts', 'w').write(out)
