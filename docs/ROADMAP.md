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
