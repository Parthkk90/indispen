# Upstream integration

| Component | Source | Commit | Licence | Use |
|---|---|---|---|---|
| Aqua | github.com/1inch/aqua | `ef24220ed9647555727b06867bf509cd6959d84b` | Degensoft-Aqua-Source-1.1 | vendored in `lib/aqua`, unmodified |
| SwapVM | github.com/1inch/swap-vm (main) | `3b3da7d66e4f865e4c57279f89727ec4b96e4d7e` | Degensoft-SwapVM-1.1 | vendored in `lib/swap-vm`; **only `libs/OpcodeList.sol` modified**: slots e0–e4 named for AquaIndex, BUCKET bank d0–d3 removed |
| @1inch/swap-vm-sdk | npm 0.5.0 | – | Degensoft-SwapVM-1.1 | generic `ProgramBuilder`, `controls`, `xycSwap` coders |

The vendored copies were taken from the sibling BUCKET project (same pinned commits). `references/1inch/*` were NOT cloned
and upstream baseline tests (swap-vm, SDK) were NOT re-run - still to do. Review the Degensoft licences before any
redistribution or commercial use.

## SDK findings
* `@1inch/swap-vm-sdk@0.5.0` opcode tables are position-indexed (v1.0 layout) and do not match swap-vm `main`'s banked numbering → AquaIndex ships a **sparse 256-slot table** (`instruction-set.ts`).
* `Opcode`/`IOpcode` classes are not exported → local `src/opcode.ts` implements the `IOpcode` contract.
* SDK `Order.data` omits the leading `tokenA|tokenB` prefix used by `main` → `buildStrategyOrder` builds the order itself (verified against Solidity hash).
* The package's ESM build imports extensionless paths; vitest needs `server.deps.inline: [/@1inch\//]`.
* Aqua is not officially deployed on Sepolia → upstream `AquaRouter` source is deployed by `script/Deploy.s.sol` (labelled self-deployed).
