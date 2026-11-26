# Test plan

M2-D local tests cover exact-year interest, repeated checkpoints, carry, one-unit-short payoff, interest-first partial payments, default and cure, failed/malformed/fee transfers, duplicate payment IDs, payer isolation, multiple lenders and borrowers, and fuzzed equivalence of split and continuous accrual. Fixtures do not verify live market or finality behavior.

| Layer | Cases and acceptance |
|---|---|
| Unit | Nonce/domain checks, lender deposit and withdraw, exact reservation, stale/future/negative prices and grace checks, price deterioration and insufficient LTV, one-draw limits, purpose mismatch, adapter spend/return, interest carry, partial/full cure, commitment expiry and maturity default. Assert exact six-decimal balances and events. |
| Integration | Run the same activation, draw, repay and release sequence with dual facts delivered in both orders. Exercise duplicates, delayed confirmations, conflicting hashes, missing proof, wrong proxy/RC, duplicate and out-of-order epochs, invalidated old callbacks, failed adapter, payment failures and ETH recipient rejection. Compare cash and custody states before/after each failed transaction. |
| Concurrency | Permute two simultaneous draw attempts, reserves and free withdrawals vs capacity, cancellation vs pending execution, expiry vs draw, and cure vs default. Future settlement tests cover cure vs escrow and assignment vs cancellation in both orders. Assert the chain's serial order determines a single winner. |
| Fuzz | Amounts across decimal limits, round metadata, clock boundaries, interest checkpoint distributions, per-loan nonce and operation domains, repayment overflow/cap clipping, adversarial allowance and balance changes. Include small principal edge cases and ETH fallback reentrancy. |
| Invariant | Handler varies deposit, reservation, callback reorder, repayment, withdrawal and failed external calls. Check all accounting and lifecycle invariants with ghost balances, expected reverts, and reachability coverage so handlers cannot pass solely by reverting. |
| Fork | Pin Base blocks. Recheck proxy bytecode/implementation and token behavior, Aave addresses/reserve flags, borrow capacity, oracle and repay ABI. In an isolated fork seed relevant test assets, open WETH-backed debt in Aave reserve USDC, prove bounded adapter repayment and check health/debt deltas. Explicitly exercise Circle-USDC rejection before exploring conversion. |
| Live (future authorization) | Smoke test all three documented routes with harmless messages. Verify injection, funding/debt, failed callback visibility, recovery and application idempotency. Record source block/hash, source receipt and finality tags, Lasna reaction/request, destination receipt/app event, fee and gas. Then run harness scenario under cap with no real value. |

Regression gates require successful repayment/claim and rejected premature release through the normal callback entry points. Test destination rollback if an adapter spends but returns an invalid result. On an outage, terminal assertions remain pending, funds remain accounted for, and a valid retry can progress after repair. Run deterministic local suite on every change; keep RPC-dependent tests isolated with reproducible block metadata. No test was executed in M0.

## Proposed M2 financial integration regression cases

- Force failure after each step of `consume → exact approval → adapter → market → postflight`. Assert reservation, free cash, token balances, allowances, market state, draw ID, principal, interest and logs revert to their pre-call values. Successful draw creates principal only for the independently checked exact market repayment. Underpayment or unexpected return data reverts, and duplicate draw cannot spend again.
- Reject unauthorized credit calls, zero or reused payment IDs, nonexistent or unconsumed reservations, wrong payer authorization and attempts to select another lender. For every successful credit prove payer debit and vault receipt equal lender free-balance growth. Direct donations remain surplus and cannot credit or repay.
- Compare partial and full repayment, interest-first allocation, carry rounding, rejected overpayment and multi-lender isolation against an independent ghost ledger. Test failing, fee-charging, rebasing and reentrant token behaviors against the supported-asset rules.
- Have malicious adapters attempt cross-function reentrancy, retain tokens, lie about returns, over-spend or leave approvals. Test market debt changes and rounding around the selected exact amount. All invalid postconditions revert the complete Base transaction.
- Test stale, future, revoked-epoch, duplicate-signer, conflicting, cross-chain, cross-vault, cross-agreement and replayed attestations; require matching transport facts and finalized source identity. Exercise revocation of a staged statement and a conflict discovered after activation.
- Run all existing M1-A and M1-B tests unchanged as regression tests. Local mocks do not establish live transport or finality. Collateral release and real-value activation remain disabled.
- Verify factory nonce prediction, immutable bindings, prefunded addresses, front-running and entire-transaction rollback on constructor or verification failure. Test fresh-factory recovery.
- Enumerate 3-of-4 quorum intersections and test one versus two equivocators, cross-epoch non-equivocation, revocation, conflicting certificates and emergency pause. Label shared-key test committees simulated trusted attestations.

### M2-E reference-model coverage

The financial invariant handler and directed lifecycle test add independent lender cash and agreement debt accounting checks. The handler records successful transitions per run and checks actual local collateral custody. The final campaign used a recorded seed, 1,000 runs and depth 128 with `fail_on_revert` enabled; see `M2_SECURITY_VERIFICATION.md` for the executed totals and the distinction between handler invocations and successful transitions.

### M2-G arithmetic envelope and boundary regression gates

The original extreme-value reproduction is retained as `testOriginalExtremeClaimIsRejectedBeforeDebtCreation`: the unsupported agreement reverts at registration, before debt creation, nonce consumption, lot binding or liquidity reservation. `test/CreditArithmeticBoundary.t.sol` must cover:

- exact maximum commitment and principal, payoff after one year, and the six-decimal asset check;
- one base unit above the commitment and principal limits, including an over-limit draw that leaves the pending operation intact;
- maximum contractual term and one second beyond;
- invalid uint64 timestamp conversions, backwards timestamps and out-of-range chain clocks;
- maximum elapsed-time interest, repeated checkpoints, large accumulated interest and post-default partial/full payoff;
- fractional carry at maximum principal, exact payoff rounding and prevention of duplicate rounding adjustments;
- failed-registration preservation of both role nonces and lender liquidity;
- unchanged normal-value behavior.

Expected values are calculated independently from the rational accrual formula. Acceptance requires `forge fmt --check`, `forge build --force`, `forge test -vvv`, `forge test --fuzz-runs 1000`, the 1,000-run/128-depth invariant campaign with recorded seed and `fail_on_revert`, and coverage summary. Final executed results are recorded in `M2_SECURITY_VERIFICATION.md`. Local success is not an independent audit or a live transport attestation.

## M3-B verification scope

Retain all M2 regression and invariant tests and run the same core scenario on simulated 31337 and 84532 deployments. Test chain guards, asset decimals and immutable bindings, exact and above-limit agreements, successful/failed draw accounting, non-replenishment on repayment/default/cancellation, cross-chain and cross-manager signatures, and the factory creation rollback pattern. The injection harness tests the creation pattern, not a failure switch in the production factory. These tests do not verify live Base Sepolia or Reactive transport.
