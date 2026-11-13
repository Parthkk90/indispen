# AquaIndex SwapVM instruction set - version 1

Router: `contracts/swapvm/AquaIndexSwapVMRouter.sol` (explicit dispatcher in `opcodes/AquaIndexOpcodes.sol`).
Numbering is the swap-vm `main` banked `OpcodeList` (lib/swap-vm, commit `3b3da7d6`); AquaIndex takes the previously
unallocated slots `0xe0–0xe4`. The only change to upstream source is in `OpcodeList.sol` (see `lib/VENDORED.md` note below).
Cross-language equality is enforced by `test/Vectors.t.sol` (writes `packages/aquaindex-swapvm-sdk/test/golden.json`) and
`packages/aquaindex-swapvm-sdk/test/sdk.test.ts` (writes `ts-vectors.json`, checked back in Solidity).

| Opcode | Instruction | Args (bytes) | Role |
|---|---|---|---|
| 0x02 | Salt (upstream) | 8 | unique strategy hash |
| 0x20 | Deadline (upstream) | 5 | strategy expiry |
| 0x50 | XYCSwap (upstream) | 0 | constant-product curve (Strategy C) |
| 0x51/0x70/0x03/0x31/0x32 | XYCConcentrate, FeeFlatIn, Jump, JumpIfTokenIn/Out (upstream) | – | on router, **not exposed in the TS SDK v1** |
| **0xe0** | `INDEX_NAV_GUARD_XD` | 42: navSource20 indexId8 maxNavAge4 minEpoch8 maxDeviationBps2 | active, NAV age, epoch, supply-vs-NAV deviation |
| **0xe1** | `INDEX_NAV_PRICE_ADJUSTER_XD` | 59: navSource20 indexId8 quote20 premium(int16)2 maxPremium2 maxDiscount2 spread2 fee2 mode1 | ask/bid from NAV; mode 0 SET, 1 CAP |
| **0xe2** | `INDEX_INVENTORY_SKEW_XD` | 56: navSource20 indexId8 quote20 target2 maxSkew2 slope2 maxAdjust2 | price skew from Aqua virtual balances, evaluated at post-trade inventory |
| **0xe3** | `INDEX_MAX_TRADE_XD` | 76: navSource20 indexId8 maxIn16 maxOut16 minLiquidityOut16 | per-swap caps, pair & pause check |
| **0xe4** | `INDEX_CAPABILITY_GUARD_XD` | 52: registry20 capabilityId32 | operator == taker, expiry, revoked, nonce, pair, max amount |

Not on the router (reverts `UnknownOpcode`): everything else, e.g. Extruction (external call), OraclePriceAdjuster, Decay, PeggedSwap, protocol fees.

Canonical order (security critical): `Deadline, Salt, NavGuard, [XYCSwap], NavPriceAdjuster, InventorySkew, MaxTrade, [CapabilityGuard]`.
Guards that read amounts run after the instructions that set them. External sources must be allowlisted on the router
(`setTrustedSource`) and are also bound inside the strategy hash.

Limitations: guards are stateless (no cumulative/windowed spend limits - quotes cannot consume quota).
