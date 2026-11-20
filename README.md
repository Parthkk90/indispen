# AquaIndex

Programmable index protocol on **1inch Aqua + a custom SwapVM router** with NAV-aware opcodes (0xe0–0xe4).
All tokens are **synthetic mocks**; the "Crypto Blue Chip 5" index uses mock tokens with no value. Not audited.

## Layout
`contracts/index` (registry, vault, share, NAV oracle, subscription/redemption/rebalance) ·
`contracts/swapvm` (router, opcodes, 5 instructions, strategy manager, capability registry) ·
`packages/aquaindex-swapvm-sdk` (TS instruction set, coders, `AquaIndexProgramBuilder`, strategies A/B/C) ·
`packages/shared` (ABIs, deployment, 50 synthetic constituents) · `services/api` (Fastify + viem + Prisma/Postgres: NAV engine, rebalance engine, pricing/quote engine, event indexer, NAV keeper) · `apps/web` (Next.js + wagmi + Tailwind + Recharts) · `script/Deploy.s.sol`, `script/Demo.s.sol` · `docs/`

## Sepolia deployment (chain 11155111) - addresses in `deployments/11155111.json`
Aqua is **self-deployed from upstream source** (no official Sepolia Aqua). Router `0x2Ff69110c092a1ebeC273Bc3dcaAE56cba9f6306`,
Aqua `0x2F4C05E1b5408F0359f15b65F35ebEa6034C12b5`, Registry `0x687f20f332189d3C0F162c6f4A321248852B8830`,
NAVOracle `0x6ee3F271bB8feE149aC2c7210Fe5EA4A32125630`, CB5 share `0x63d9c18B13b352199094B0564447a8bbbA8793ff`,
Vault `0x76ae1BF6c7FF5FC842f1B263c5f7a17f8112ca22`. Contracts are not yet verified on Etherscan.

## Commands
```bash
pnpm install && npm install            # deps (forge-std/OZ via npm, SDK via pnpm)
export PATH="$HOME/.foundry/bin:$PATH"
forge test                              # 71 tests
pnpm --filter @aquaindex/swapvm-sdk test # 23 tests (run after `forge test` regenerates golden.json)
cp .env.example .env                    # fill PRIVATE_KEY / TAKER_KEY (throwaway keys!)
forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --slow --skip-simulation --gas-estimate-multiplier 150
SKIP_SETUP=false forge script script/Demo.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --slow --skip-simulation --gas-estimate-multiplier 150
```
Sepolia note: Foundry's local gas simulation under-estimates on current Sepolia; deploys fail with out-of-gas unless
`--skip-simulation` (node estimates) is used.

See `docs/opcode-reference.md`, `docs/upstream-integration.md`, `docs/status.md`.

## Backend + frontend
```bash
docker run -d --name aquaindex-pg -e POSTGRES_USER=aquaindex -e POSTGRES_PASSWORD=aquaindex -e POSTGRES_DB=aquaindex -p 5440:5432 postgres:18-alpine
cd services/api && cp .env.example .env && npx prisma generate && npx prisma db push
pnpm start                      # API on :4001 (starts the event indexer; DISABLE_INDEXER=1 to skip)
KEEPER_KEY=0x... pnpm keeper    # optional: republish NAV when the snapshot is older than KEEPER_MAX_AGE (needs NAV_PUBLISHER_ROLE)
cd ../../apps/web && cp .env.example .env.local && pnpm build && pnpm start   # web on :3001
```
Pages: Overview, Explore (+ 50-entry synthetic universe), Index details, Portfolio, Invest, Redeem, Trade (quotes from the
custom router, labelled), Market maker (build via on-chain `buildOrder`, ship/dock to Aqua), Rebalance (drift/proposals read-only).
Note: custom-router trading needs a fresh published NAV (strategy `maxNavAge`); run the keeper or press "Publish NAV" on the Overview page with the publisher wallet.
