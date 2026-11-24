# Threat model

| Threat and trust assumption | Control and residual failure |
|---|---|
| Forged callbacks, replay or wrong route | Pin Omni proxy and originating Reactive contract, verify exact source/log domain and named operation, check state and payload hash. Test untrusted proxy, spoofed first argument, same sender with wrong payload and cross-agreement replay. |
| Early source reorg or provider equivocation | Require independent finalized log attestation for custody-affecting updates. Base risk is rechecked locally. A signer quorum is trusted for finalized-source assertions; collusion with transport can violate safety. Finality lag or outage can strand collateral temporarily. |
| Concurrent withdrawals, allocations and draws | One Base manager owns state, reservation is atomic with activation, cash spending is bounded, non-reentrant guards cover USDC and adapter paths. Duplicate callbacks and public attempts converge on same epoch. |
| Griefing through events, fees or stale intents | Narrow subscriptions, bounded retries, one pending epoch, rate-limit reannouncements and observation where practical, monitor balances and failure rates. Base execution permissionless under unchanged guards. |
| Oracle manipulation, sequencer outage or USDC basis | Use allowlisted fresh feeds and grace checks, conservative LTV, exposure caps and exact unit conversion. Real-value service needs confirmed feeds and a basis policy. Test fixtures are explicit privileged inputs. |
| Adapter returns false success, pool upgrades, token pauses | Restrict bytecode/config and purpose; validate actual spending and market result, compare risk or full debt exit, reset approval, pause new risk after drift. Token issuer or market pause can prevent repayment and prolong custody. |
| Default/repayment/award race | Base serializes cure and settlement entry; escrow locks claim, Unichain serializes award and cancel. Await final proof; carry liability across outages and disputes. |
| Emergency or governance abuse | Guardian may pause activation, new locks and execution. Leave repayments, earned withdrawals and already-authorized claims available; pause new risk separately from cross-chain ingress. Admin must never sweep collateral, alter signed terms, substitute an adapter for an existing loan or clear debt. Use immutable modules per deployment where possible and explicit future migrations. |
| Underfunding or proxy/system behavior changes | Isolated native reserves and health monitoring; test proxy identity and code/implementation drift, pause new risk upon change. Reactive network signer, proxy and transport liveness are external trust assumptions. |
| Third-party position state and approval | Anybody can change market debt between observation and execution. Recheck current account and debt, use exact approval, bounded amount and risk improvement. Debt may be liquidated before callback inclusion. |
| Unaccounted loss on recovery | Default keeps debt outstanding; Base USDC receipt or an explicitly approved terminal write-off is required. Settlement provider inventory, quotes, receipt proof and dispute resolution are production dependencies. |

Roles include the borrower and lender as term signers, deployment/config owner with narrowly scoped route/adapter setup, guardian, finality signer quorum, public risk samplers/recovery submitters, and future settlement providers. Deploy isolated configurations for test fixtures and real feeds. Incident response halts new risk, preserves proofs, reconciles canonical receipts and retries valid pending operations after correcting funding or configuration. Never use a privileged success override.

## M1-A boundaries and findings

The immutable binder can choose who is allowed to deposit a particular local lot and for what amount. It cannot redirect or release ETH. The one-time binding prevents callers from claiming a known agreement ID before its borrower. Custody has no release entry point. Use isolated test deployments because any ETH accepted by this version stays locked.

The immutable manager cannot withdraw lender cash or choose a transfer destination. It can reserve within the lender's per-agreement cap, return an existing reserve, and consume it once to the immutable consumer. It is trusted to use those powers only for the fixture scenario. A real integration must enforce signed terms, financial conditions, exact applied repayment and debt recording in the manager transaction. No actual funds should be placed under these local authorities.

The vault requires a conventional fixed-supply-behavior ERC-20 reporting honest balances, and it checks both sides of each transfer. Direct token and forced ETH surplus are observable and excluded from withdrawable balances. There is no surplus sweep. The contribution of the fixed consumer is tested as an asset transfer. Production token, adapter, proxy, finalized proof and settlement assumptions remain open.
