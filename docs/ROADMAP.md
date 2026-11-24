# Roadmap

**M0 CONDITIONALLY APPROVED — BLOCKERS REQUIRE RESOLUTION**

| Milestone | Scope and exit criteria |
|---|---|
| M0 | Architecture and evidence. RPC confirms contracts and reserve mismatch. Routed callbacks, proof deployment and lender recovery are open. |
| M1a | Dependency-minimal local scaffold implementation. Implement typed terms, one-lot custody, per-lender cash accounting, atomic one-draw/repay, terminal close, deterministic lending/oracle fixture, replay-safe Omni adapter boundaries and mock proof inputs. Write property and failure tests from the specification. Default stays locked and cureable. |
| M1b | Pin reviewed Omni dependency and validate proxy implementation/authentication on-chain. With separate authorization, smoke test both cross-chain directions and Base-to-Base, recipient funding, failures and retries. Implement and test independent finalized attestation quorum and measure lock/release liveness. Run the labelled live harness only after these gates. |
| M2 | Validate real market with matching reserve token or bounded conversion route, explicit trigger strategy and fresh feed pair with sequencer checks. Implement testnet benchmark and optional frontend with Next.js, TypeScript, wagmi and viem. |
| Real-value gate | Specify, verify and audit prefunded settlement or verified sale/bridge and dispute path, including partial recovery, collateral/lender safeties, finality trust, and recognized losses. Keep real-value origination disabled pending these results. |

A local harness is feasible based on the specified interfaces. Live demo feasibility remains conditional pending actual callback and finality verification. Aave direct Circle-USDC repayment is ruled out at the pinned blocks. Autonomous lender recovery remains unproven and outside M1.

## M1-A local foundation

The M1a row above describes the broader originally proposed local milestone. The remediation brief narrows M1-A to the two vaults, shared ABI and accounting tests. A local binder and fixture manager/consumer stand in for future signed terms and purpose enforcement. No local release path is included. CreditManager, market harness and cross-chain ingress remain deferred.

Recommended M1-B begins with typed consent and the deterministic market, then verifies purpose-bound repayment, zero-debt close and finalized release locally before a separately authorized Omni smoke test. M2 retains the external market, pricing and settlement gates above. Foundry remediation is complete for local verification. Cross-chain and real-value gates remain open.
