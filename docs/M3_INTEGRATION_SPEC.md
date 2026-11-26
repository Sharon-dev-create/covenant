# M3-A financial integration specification

Status: design only, based on repository `af1ccd40dc787ea675f2eedd842cc2b81042c419`. M1-B live delivery, injected-sender behavior, retry and source finality have not been verified. Nothing here enables financial activation. The Base-side manager is the authoritative agreement, reservation and debt ledger; Reactive coordinates requests and is never an accounting authority.

```mermaid
sequenceDiagram
    participant L as Lender / borrower
    participant C as Unichain test collateral vault
    participant A as Base collateral verifier
    participant V as Base liquidity vault
    participant M as Base testnet manager
    participant H as Base test market + signal registry
    participant R as Lasna reactive orchestrator
    participant G as Base authenticated ingress
    L->>V: Deposit six-decimal test asset
    L->>M: Register bilateral V3 agreement
    L->>C: Bind and lock ETH test collateral
    Note over C,A: Independent finalized-lock attestation; transport alone is not finality
    L->>A: Submit and verify attestation
    L->>V: Commit liquidity
    L->>M: Activate: verify evidence and reserve
    H->>H: Test operator changes fixture position; emit signal
    H-->>R: Base log observed (M1-B live gate)
    R-->>G: Callback through pinned Base proxy (M1-B live gate)
    G->>M: Reuse pending operation or observeRisk(id)
    G->>M: executePending(id, operationId, signed amount)
    M->>V: consume reservation
    M->>H: fixed adapter repays exact signed amount
    H-->>M: checked debt and token balance deltas
    M-->>G: DrawExecuted; principal recorded atomically
    L->>M: repay(id, amount, payerNonce)
    M->>V: pull exact receipt; credit original lender
```

## Reuse and boundaries

| Component | Existing behavior to preserve | Integration boundary |
|---|---|---|
| `CreditManager` | V3 bilateral signatures, independent nonces, deterministic lot, `observeRisk`, `executePending`, market/price/collateral revalidation, single draw, interest and repayment | Local constructor restricts chain 31337; no testnet deployment exists. Extract a shared abstract core and retain chain-scoped local and testnet wrappers, with identical financial logic and explicit test-only limits. Do not remove the restriction in the existing contract. |
| `CreditLiquidityVault` | Fixed manager/consumer, reservation and exact receipt to bound lender | Deploy a separate testnet instance bound permanently to the testnet manager and six-decimal test asset. |
| `CollateralVault` | Binder-bound agreement/borrower/amount, one lot, ETH lock-only | Separate Unichain instance; binder governance and attestation are explicit trust boundaries. No unlock or recovery exists. |
| `LocalCreditFactory` | Predictable, atomic local pair | Remains 31337-only. A distinct testnet factory must enforce chain, implementation and dependencies and independently test address prediction and rollback. |
| Omni probe emitter/receiver/reactive | Subscription, proxy + injected sender checks, replay/failure tests | Reuse the patterns and libraries, not probe-specific ABI or probe state as financial state. The probe receiver accepts `ProbeMessage` and cannot invoke the manager. |
| Local market, adapter, collateral and price fixtures | Deterministic test interfaces and scenarios | Test fixtures are operator-controlled. Testnet versions must be explicitly labeled and deployed/configured separately; no production authenticity is implied. |

The signed manager/domain address binds the fixed testnet dependencies. Testnet EIP-712 V3 signatures must be freshly produced for chain 84532 and the new manager; local signatures are invalid. Preserve `MAX_COMMITMENT`, `MAX_PRINCIPAL`, `MAX_TERM`, checked timestamps, accounting and rollback, and add the lower demonstration cap described in the deployment specification at manager registration, not solely in a UI or bypassable ingress.

## Final shared-engine decision

Extract the existing manager's financial state, EIP-712 V3, risk, draw, interest and servicing implementation **once** into an abstract, non-deployable `CreditManagerCore`. Keep the externally named `CreditManager` as a thin wrapper with the same constructor ABI and an unconditional chain-31337 check; retain `LocalCreditFactory` creation order, prediction and binding behavior. Add a separate `TestnetCreditManager` wrapper and `TestnetCreditFactory`, each requiring chain 84532. The abstract core constructor accepts the same immutable dependencies and enforces the common dependency/decimal checks; only concrete wrappers enforce their literal chain IDs. The core itself cannot be directly deployed. Do not use a user-selected chain ID, generic unrestricted concrete manager or duplicate financial implementation.

Add only two internal, narrowly scoped policy hooks: one validates testnet caps at registration; one accounts for successful draws against an aggregate lifetime limit. Local hooks are no-ops, preserving local semantics. Testnet hooks enforce the 300 mock-USDC per-agreement commitment cap and 300 aggregate lifetime principal cap described in the deployment document. These hooks must execute inside the manager's guarded transactions, and a failed draw rolls back the counter; no callback, vault or direct manager entrypoint can bypass them. The 200-unit demonstration draw leaves 100 units of lifetime headroom. This aggregate restriction is an additional testnet-only demonstration policy, not existing M2 behavior.

Changing code structure changes creation/runtime bytecode and gas, so identical bytecode is not an acceptance criterion. Verify the public ABI, storage semantics, events, errors, deterministic factory addresses and EIP-712 V3 typed data/lot derivation and signing vectors; confirm old local tests and all 108 baseline regressions pass, then run the same lifecycle, signature, nonce, boundary, atomicity, repayment, fuzz and invariant scenarios against both wrappers. Test both chain guard failures, factory prediction/rollback and direct attempts to bypass testnet caps. New testnet chain and manager addresses require new signatures; existing local signatures are not portable. Do not change compiler or factory nonce assumptions without a reviewed migration.

## Trigger and execution

For the shortest demonstrable route, use **Base Sepolia risk signal -> Lasna -> Base Sepolia callback** after M1-B's Base-to-Base route is live verified. A narrowly scoped Base signal registry reads the fixture market, emits a monotonic `RiskSignaled` event for a registered agreement and stores its current generation; repeated calls cannot supersede an outstanding eligible signal. Signal issuance is permissionless but does not authorize borrowing; the fixture operator controls simulated market state. No user-supplied borrower, lender, market, asset, adapter, recipient or amount is trusted. At callback time the ingress checks the registry's current generation and manager state, then calls `observeRisk` if no pending operation exists or uses the existing pending operation if it is still eligible. It reads the exact amount from the manager's signed terms, and invokes `executePending`; the manager independently revalidates all financial predicates at execution. The manager's existing permissionless path remains permissionless, including non-Reactive execution: the ingress cannot be described as an exclusive authorization gate.

`observeRisk` and `executePending` may execute in one Base transaction. If either reverts, revert the callback so a newly created pending operation and ingress receipt are rolled back. An already pending operation created by a previous transaction remains available on failure. Recovery clears a no-longer-eligible pending operation using the manager's existing `clearRecoveredRisk`; a subsequent fresh observation creates a new epoch. Terminal Drawn/Closed/Defaulted state prevents another draw. The callback returns a distinct acknowledged/no-op result for a successfully completed semantic intent and never silently claims a failed financial call succeeded. Details and explicit replay keys are in [M3_CALLBACK_SCHEMA.md](M3_CALLBACK_SCHEMA.md).

## Collateral evidence and finality gate

An authenticated transport message proves neither a Unichain event's finality nor an attestation's truth. Adopt a proposed test-only 3-of-4 signer verifier, domain-separated and bound to chain, vault, manager, agreement, lot, owner, amount, source block hash, transaction hash, log index, terms hash, policy version, epoch and expiry. It is a **trusted committee assertion**, not consensus verification. The verifier rejects stale/revoked, replayed, conflicting, wrong-domain and wrong-lot evidence; signer rotation and emergency disable are explicit reviewed administrative operations. Any two 3-of-4 quorums intersect in two signers; conflicting certificates cannot both form if at most one signer equivocates and honest signers enforce non-equivocation across epochs. Two unavailable signers block liveness and three compromised signers can forge assertions. Four keys controlled by one developer are one operational trust domain, not independent decentralization. Source canonicality policy, independent signer operators and finality evidence must be agreed and implemented before any cross-chain activation; use a clearly marked mock only for local integration tests. A callback can carry a reference to separately accepted evidence but cannot itself finalize it. No collateral release is implemented or implied.

## Market choice

1. **Real testnet market:** the repository's pinned Base Sepolia observation found Aave's reserve list did not include Circle test USDC. This is historical, not a current guarantee. A compatible reserve, token, third-party repayment, adapter behavior and liquidity must be reverified; a different asset or conversion requires separately signed terms and security review. Market-reported debt and health are a trusted dependency, not independent proof of market honesty.
2. **Deterministic Base testnet market harness — recommended shortest route:** deploy an explicitly named demo market with a six-decimal test token, operator-set distress and genuine on-chain token transfers and debt state. The adapter enforces the M2 exact-spend, debt-reduction, balance and allowance postconditions in the same Base transaction. This demonstrates a real cross-chain callback and real testnet accounting against a **simulated lending market**, not production lending.

## Demonstration and acceptance

1. Lender deposits 1,000 six-decimal mock USDC; borrower and lender sign V3 terms for a 300 mock-USDC commitment and exact 200 mock-USDC autonomous repayment. 2. Borrower locks 0.001 test ETH in the bound Unichain lot. 3. Approved finalized-lock evidence is accepted by the Base verifier. 4. Lender commitment and manager activation reserve liquidity. 5. The explicitly simulated oracle values the collateral at 1,000 mock USDC; the fixture reports 800 mock USDC debt and a simulated market collateral value of 840 mock USDC (health factor 1.05), then emits a registry-backed signal. After the exact 200 repayment, fixture debt is 600 and the health factor is 1.4. The 300 commitment is below the 500 mock-USDC maximum at 50% LTV. 6. Reactive observes the Base event and requests the Base callback; both steps require M1-B live verification. 7. Authenticated ingress verifies and calls the manager. 8. Manager revalidates fresh oracle, collateral evidence, debt, health, signed amount and fixed dependencies, then atomically repays the test market and creates equal principal. 9. Borrower pays principal plus any interest; exact receipts credit the original lender. With a 1,000 deposit, reserving 300 leaves 700 free; drawing 200 returns the unused 100, leaving 800 free and 200 principal. Repayment credits 200 plus accrued interest, restoring at least 1,000 free. Collateral remains locked throughout.

Acceptance requires actual source, Lasna and destination receipts, event identity, proxy trace/injected identity, manager `DrawExecuted`, token and market debt deltas, pending/consumed state, vault free/reserved accounting and borrower repayment receipt. Test wrong sender/proxy/chain, duplicate or conflicting signals, stale evidence/prices, recovered position, retry after revert, competing executors and atomic rollback. No callback request alone counts as success. Capture separate source, reaction and destination timestamps and finalized-tag observations; do not infer source finality from callback delivery. No real-value origination, collateral release, liquidation or cross-chain lender recovery.

## Implementation order and gates

1. Extract the shared abstract core and chain-scoped wrappers in local development. **Acceptance:** all 108 existing tests and local ABI/domain/factory regression tests pass; no unrestricted deployable manager exists. 2. Add the 84532-only testnet factory, 300-unit cap and deterministic mock asset/market/adapter/oracle. **Acceptance:** local-vs-testnet differential financial tests, bypass and rollback tests pass. 3. Implement the 3-of-4 verifier. **Acceptance:** threshold, domain, replay, conflict, expiry and signer-rotation tests pass; source finality policy and signer custody are approved before use. 4. Implement signal registry, orchestrator and ingress. **Acceptance:** callback matrix, competing direct execution, retry, duplicate and gas tests pass in a local multi-chain simulation. 5. Complete all M1-B live routes and funding, then independently review the M3 expenditure plan and obtain broadcast authorization. **Acceptance:** actual receipts, source identity, destination state and per-transaction funding evidence match the demonstration. No stage authorizes activation or deployment by itself. Estimated funding and precise blockers are in [M3_TESTNET_DEPLOYMENT.md](M3_TESTNET_DEPLOYMENT.md).

Reactive documentation: [subscriptions and system calls](https://dev.reactive.network/reactive-contracts), [callback sender and proxy authentication](https://dev.reactive.network/callback-contracts), [supported networks](https://dev.reactive.network/origins-and-destinations). These descriptions are documentation, not evidence of live behavior in Covenant.

## M3-B implementation status

The shared financial logic is now in abstract `CreditManagerCore`. The existing `CreditManager` and `LocalCreditFactory` remain local-chain-only; `TestnetCreditManager` and `TestnetCreditFactory` are separate 84532-only wrappers. Testnet registration limits commitments and draws to 300e6 units; the manager increments its per-deployment 300e6 lifetime-principal counter only after market execution returns, in the same transaction. A rejected over-limit draw rolls back the market and vault calls. Repayment, default and cancellation do not restore lifetime capacity. There is no administrative cap increase.

The asset is a constructor-selected, immutable six-decimal token; this code does not certify that token as a faucet token or provide a global deployment registry. Each independently deployed manager has its own limit. Before any deployment, separately review the exact token and immutable dependencies. M3-C finalized collateral evidence and M3-D Reactive financial callback integration remain unimplemented, and M1-B live transport remains a gate.
