# India: legal & compliance notes

> **Not legal advice.** An engineering reading of Indian rules as understood at the time of writing, to steer design.
> Indian crypto rules change often (Finance Acts, FIU-IND/CERT-In notices). Have counsel verify before any mainnet launch.
> **Status today: Sepolia testnet only, test tokens with no value, zero fees.** Most items below bite at mainnet.

## 1. Where Indian law touches this protocol

| Area | Rule (summary) | Effect on BUCKET |
|---|---|---|
| **Status of crypto** | No crypto-specific statute; neither banned nor legal tender. Defined as *Virtual Digital Assets* (VDA), Income-tax Act s.2(47A). The 2020 Supreme Court ruling (*IAMAI v RBI*) struck down the RBI banking ban. | Legal to build and use; regulatory risk is real, not zero. |
| **Income tax** | s.115BBH: flat 30% on VDA transfer gains, only cost of acquisition deductible, no loss set-off or carry-forward. s.194S: 1% TDS on VDA transfers (thresholds apply). Crypto-to-crypto swaps count as transfers. | **Every swap/rebalance an agent executes is a taxable event.** An auto-rebalancing agent can create hundreds. Users need a per-fill record → `GET /api/ledger.csv`. |
| **Reporting (s.285BAA, Finance Act 2025)** | Reporting-entity obligations for crypto-asset transactions, from FY2026-27 (verify current text). | Matters if BUCKET (or a host) is a "reporting entity". Non-custodial design helps but does not settle it. |
| **PMLA / FIU-IND** | Since March 2023, VDA service providers (exchange, transfer, **custody/administration**, issuer-related services) are PMLA reporting entities: registration, KYC, STR/CTR. | Core risk. A non-custodial *protocol* is arguably outside; a **hosted operator that signs on users' behalf** is not clearly outside (see §3). |
| **GST** | 18% GST on service fees. | Zero fees today. Any fee/spread to a protocol treasury adds GST + invoicing for Indian users. |
| **DPDP Act 2023** | Consent, purpose limitation, erasure for personal data of individuals (rules phasing in). | On-chain data is immutable; never put personal data on-chain. ENS names can identify a person: treat as personal data off-chain. BYOK cookie / logs are in scope. |
| **IT Act + CERT-In (2022)** | Incident reporting (6 hours), log retention (180 days) for covered intermediaries. | Server logs and incident process once hosted for Indian users. |
| **FEMA** | VDAs are not "currency"; cross-border treatment unsettled. | Don't market as a remittance/forex product. |
| **Advertising (ASCI)** | VDA ads need the prescribed risk disclaimer. | Applies to any India-facing marketing. |
| **Agency law (Indian Contract Act ss.182+)** | A principal is bound by acts of an authorised agent. | A Financial Capability *is* a machine-enforced mandate: the **owner is the principal and bears liability** for what an in-limit agent does. Limits are the written scope of authority. |

## 2. What was changed because of this

| Change | Why |
|---|---|
| `GET /api/ledger.csv[?bucketId=]`: one row per `ExecutionRecorded` receipt (time, tx, kind, in/out asset + human amounts, reference value, operator, capability) | s.115BBH/s.194S: per-transfer records, cost-basis order. Public chain data only (no PII). INR valuation is deliberately left to the filer: the protocol's reference price is not a market quote. |
| This document + README "Legal & compliance" section | Make assumptions explicit and reviewable. |

## 3. Architecture / DeFi findings (not yet fixed; ranked)

1. **Hosted operator key is the biggest legal and security smell.** The server holds `OPERATOR_PRIVATE_KEY` and signs on users' behalf. For Indian law that edges toward "administration of VDAs". For DeFi it is a single trusted hot key. *Fix:* let the **owner supply the operator** (their own agent, own key); the hosted agent becomes a demo/convenience, behind an explicit opt-in. The contracts already support any operator address.
2. **Reporter-published price feed** (`BucketReferencePriceFeed`) is a centralised oracle; a bad reporter can misprice fills up to the concession cap. *Fix before mainnet:* Chainlink/Pyth-backed `IBucketPriceFeed`, plus deviation and staleness circuit breakers. The interface already allows it.
3. **No timelock on policy changes / no owner-recovery path** (SECURITY.md: losing the ENS name is catastrophic). *Fix:* optional timelock on `updatePolicy` so operators/guardians see changes first; optional social-recovery guardian role for the owner name.
4. **Pause is guardian-only; resume is owner-only.** Good. Keep: this asymmetry (any one trusted party can stop, only the owner can restart) is the right DeFi default.
5. **Pre-mainnet:** independent audit, `forge` fuzz/invariant tests on invariants A, B, D (authority only shrinks; usage charged to whole chain), bug bounty.
6. **Do not custody and do not take fees until counsel has signed off** on PMLA/GST position. Keeping zero fees and zero custody is the cheapest compliant posture.

## 4. Mainnet checklist (India-facing)

- [ ] Legal opinion on PMLA/VDA-service-provider status of the hosted components.
- [ ] Operator keys owner-supplied; hosted signer removed or opt-in.
- [ ] Decentralised price oracle + circuit breakers; external audit.
- [ ] ASCI-compliant risk disclaimer in UI and marketing; terms making the owner the responsible principal.
- [ ] Privacy notice + DPDP consent for any stored data; no personal data on-chain.
- [ ] Ledger export reviewed by a Chartered Accountant (TDS, cost basis, reporting format).
- [ ] Sanctions screening decision (hosted front-end geoblocking vs pure protocol).
