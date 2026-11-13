# Status

## Done
* Custom router + 5 instructions + explicit dispatch (22.2 KB runtime, under EIP-170), Aqua settlement via upstream `AquaRouter`.
* Index contracts: registry, vault (ledger-based backing), share, NAV oracle (on-chain NAV from vault x prices), subscription, redemption (in-kind and USDC), rebalance manager (drift, proposals, constrained execution via Aqua strategies), capability registry, strategy manager (ship/dock records verified against Aqua).
* TS SDK: sparse instruction set, coders, `AquaIndexProgramBuilder`, strategies A/B/C, byte-exact Solidity equality in both directions.
* Tests: Foundry 71 (index accounting, every opcode, fuzz: quote==swap, round-trip never profits, skew monotonicity, rebalance, isolation); SDK 23.
* Sepolia: full deploy + live demo (subscribe, rebalance through Aqua, ship Strategy A, custom-router quote == swap, NAV change, inventory change, limit revert, redemption).

## Backend / frontend (added)
* API: `/api/indices`, `/indices/:id`, `/nav-history`, `/rebalance`, `/activity`, `/portfolio/:addr`, `/strategies`, `/quote`, `/strategy/build`, `/prices`, `/trades`; indexer (events -> Postgres), keeper.
* Web: 9 pages; every number is read live from Sepolia via the API or wagmi.

## Not done
* `packages/aqua-client` (the web app and API call Aqua through viem + shared ABIs directly).
* Browser wallet flows are built and type-checked but were NOT exercised with a real wallet extension in this session (read paths verified via headless Chrome against live Sepolia; the swap calldata uses the same byte-verified taker data as the on-chain demo).
* Rebalance execution from the browser (needs a counterparty order; use `script/Demo.s.sol`). Redis not used. No frontend automated tests; API has unit tests only for strategy decoding.
* Etherscan verification; upstream baseline tests (swap-vm/SDK) not run; `references/1inch` clones.
* Cumulative / windowed limits; SDK coders for Jump/FeeFlat/XYCConcentrate; Strategy C `FeeFlatIn`.
* Official-Aqua mainnet-fork test (Aqua 0x1111113c… not exercised); no audit.
* Known design caveats: skew impact is evaluated on pre-skew amounts (sub-bps residual); oracle prices come from a trusted PRICE_UPDATER (no Chainlink); the Sepolia oracle window is 24h for demo convenience.
