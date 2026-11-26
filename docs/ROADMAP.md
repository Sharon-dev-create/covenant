# Roadmap

**M0 CONDITIONALLY APPROVED — BLOCKERS REQUIRE RESOLUTION**

| Milestone | Scope and exit criteria |
|---|---|
| M0 | Architecture and evidence. RPC confirms contracts and reserve mismatch. Routed callbacks, proof deployment and lender recovery are open. |
| M1a | Dependency-minimal local scaffold implementation. Implement typed terms, one-lot custody, per-lender cash accounting, atomic one-draw/repay, terminal close, deterministic lending/oracle fixture, replay-safe Omni adapter boundaries and mock proof inputs. Write property and failure tests from the specification. Default stays locked and cureable. |
| M1-B | Isolated Omni transport probes for Unichain → Base, Base → Unichain and Base → Base through Lasna. Local implementation and tests are complete; obtain authorization, then capture live authentication, delivery, funding, failure and re-request evidence. |
| M2 | Validate real market with matching reserve token or bounded conversion route, explicit trigger strategy and fresh feed pair with sequencer checks. Implement testnet benchmark and optional frontend with Next.js, TypeScript, wagmi and viem. |
| Real-value gate | Specify, verify and audit prefunded settlement or verified sale/bridge and dispute path, including partial recovery, collateral/lender safeties, finality trust, and recognized losses. Keep real-value origination disabled pending these results. |

A local harness is feasible based on the specified interfaces. Live demo feasibility remains conditional pending actual callback and finality verification. Aave direct Circle-USDC repayment is ruled out at the pinned blocks. Autonomous lender recovery remains unproven and outside M1.

## M1-A local foundation

The M1a row above describes the broader originally proposed local milestone. The remediation brief narrows M1-A to the two vaults, shared ABI and accounting tests. A local binder and fixture manager/consumer stand in for future signed terms and purpose enforcement. No local release path is included. CreditManager, market harness and cross-chain ingress remain deferred.

## M1-B transport status

M1-B implements transport only: emitter, receiver and Lasna reactive probes with exact route subscriptions, payer support, replay protection, controlled failure and bounded application-level re-requests. Local tests and read-only network/simulation checks are complete. No transaction has been broadcast. Live evidence, authorization, finality and retry behavior remain pending. Typed consent, deterministic market tests, purpose-bound repayment, zero-debt close and independent finalized release remain future financial gates. [Transport verification](TRANSPORT_VERIFICATION.md) · [Reactive integration](REACTIVE_INTEGRATION.md)

## M2 local financial review — COMPLETE

The local credit engine has signed agreement and nonce checks, cash and debt accounting, atomic fixture-market execution, debt servicing, real local lock-only collateral custody and expanded invariant tests. The previously reproduced extreme-claim overflow is resolved by an enforced financial operating envelope: 1,000,000 USDC maximum commitment and principal, six-decimal asset validation, fixed 5% simple APR, a 365-day contractual term and checked uint64 timestamps. Interest continues after maturity and default throughout the uint64 range; there is no accrual cutoff, saturation or debt forgiveness. The version 3 signing schema is unchanged, the original reproduction is now a rejection regression, and boundary, fuzz and invariant verification passed. Status: **M2 COMPLETE — LOCAL FINANCIAL ENGINE READY FOR REACTIVE INTEGRATION**.

M1-B live callback authentication, delivery and finality, production oracle and market verification, collateral release/liquidation, lender recovery and real-value authorization remain separate unresolved integration gates. No production integration or real-value origination is enabled by M2. See `FINANCIAL_MODEL.md`, `INVARIANTS.md`, `THREAT_MODEL.md`, `M2_CREDIT_ENGINE.md`, `M2_SECURITY_VERIFICATION.md` and `TEST_PLAN.md`.

## M3 shortest implementation sequence

Reuse, rather than duplicate, the local `CreditManager` registration/activation/risk/draw/repay interfaces, the exact-repayment adapter and market boundary, and the existing transport emitter/receiver probes. The shortest path to an end-to-end Reactive financial demonstration is: capture outstanding M1-B live transport and finality evidence; bind and authenticate the exact Omni proxy, originating Reactive contract, source log domain and operation/payload hash to the existing manager callback boundary; verify callback funding/retry/idempotency against replay-protected operation IDs; run the local activation, exact draw and repayment sequence through that callback path with testnet-only value; then add production oracle/market adaptors and collateral recovery only as separately authorized gates. No M3 implementation was performed during this M2 closure.

## M3-B shared engine

The local shared-core and restricted Base Sepolia wrappers and factory are implemented for local testing. No testnet transaction has been broadcast. M3-C finality/attestation and M3-D financial Reactive callbacks remain future work; signer governance, live M1-B route verification, mock dependencies, funding and separate deployment authorization remain open.

## M3-C demo dependencies

The local 3-of-4 attestation verifier and restricted simulated token, oracle, market, adapter and demo factory have been implemented for local verification. Deployment requires approved attestor/governance custody and an agreed source-finality procedure. M1-B live transport and M3-D financial callback integration are still outstanding. No live deployment, collateral release or real-value origination is authorized by this milestone.

## M3-D financial callback

The registry, financial Reactive orchestrator and authenticated Base receiver are implemented for local simulation. M1-B live routes, real provider authentication and billing, source-finality policy, attestor governance, deployment funding and separate broadcast authorization remain open before an integrated testnet demonstration. No collateral release, liquidation or lender recovery is added.

## M4-A local deployment preparation

See [M4 deployment readiness](M4_DEPLOYMENT_READINESS.md) and [integrated verification](INTEGRATED_VERIFICATION.md). Live M1-B verification, operational approvals, fresh fee estimates and separate broadcast authorization remain gates.
