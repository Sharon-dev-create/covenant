# M2-E local financial verification (work in progress)

Verification base revision: `f87ce2bb21d441af65aa8a2b69fa52faf7e44f05`. The financial model is exercised by `test/CreditFinancialInvariant.t.sol`; all contracts, markets, collateral observations and oracle data in that test are local fixtures. This document is not an audit or a live integration attestation.

The handler independently tracks deposits, withdrawals, donations, drawdowns, repayments, lender free and reserved amounts, and each agreement's principal, recognized and paid interest, fractional carry and lifecycle. It compares these with manager and vault state after calls. A directed lifecycle covers draw, time advancement, partial payment, default and settlement. The updated model checks real local CollateralVault custody; cross-chain collateral observations remain deliberately mocked. The updated handler separately records ineligible calls and successful transitions, but Foundry resets that state between invariant runs, so campaign-wide successful-transition totals are not yet available. It does not yet comprehensively test adversarial token or adapter behavior, bounded arithmetic, or fuzzed repayment sequences beyond existing tests.

Two isolated scratch mutations produced counterexamples for `invariant_CashAndDebtMatchIndependentLedger`: adding one base unit to credited lender cash failed after register, activate, observe, execute and repay; adding one unit to created principal failed after registration, activation, observation and execution. The counterexamples were replayed with `--fuzz-seed 0x1234`; the failing traces were persisted by Foundry, so the seed on the replay should not be treated as proof of the original discovery seed. The mutations were only made in `/tmp` copies and are absent from the working tree.

Interest uses a denominator of 630720000 and carries fractional units between checkpoints; final settlement may round a nonzero fraction up by one base unit. The exact arithmetic and adversarial boundary coverage still require independent expansion before M2-E can be considered complete.

Existing tests cover execution competition, risk recovery, rollback, price and collateral rejection, repayment ordering, carry, default and reentrancy fixtures. Live Reactive callback authentication, source-chain finality, oracle trust and production market/adapter behavior remain unverified. Financial credit is local-only and cannot establish production safety.

## Verification results

After correcting an underflow in the test model's intermediate cash expression, `forge fmt --check` and `forge build --force` passed; `forge test -vvv` and `forge test --fuzz-runs 1000` each passed 82 tests, with no failures or skips. The financial invariant passed 1,000 runs at depth 128 with 128,000 handler invocations, zero reverts and zero discards (`FOUNDRY_INVARIANT_FAIL_ON_REVERT=true`, seed `0x1234`). An earlier full-suite run exposed the test-only expression error; no production change was needed.

| Handler | Invocations |
| --- | ---: |
| activate | 8,510 |
| advance | 8,774 |
| cancel | 8,569 |
| checkpoint | 8,455 |
| clearRecovered | 8,638 |
| deposit | 8,496 |
| donate | 8,655 |
| execute | 8,516 |
| expire | 8,623 |
| markDefault | 8,491 |
| observe | 8,402 |
| register | 8,561 |
| repay | 8,602 |
| revoke | 8,323 |
| withdraw | 8,385 |

These are Foundry invocation counts, **not** counts of successful operations: state-dependent handlers can return early. Consequently the requested actual transition counts and evidence that most calls are meaningful remain outstanding.

Coverage results (line / statement / branch / function): CollateralVault 100.00 / 91.43 / 70.00 / 100.00%; CreditLiquidityVault 100 / 100 / 100 / 100%; CreditManager 99.19 / 96.42 / 75.47 / 100%; LiquidityVault 98.91 / 95.20 / 72.73 / 100%; LocalCreditFactory 94.74 / 93.75 / 0 / 100%. Instrumentation disables optimizer and viaIR. Coverage measures executed source locations and does not prove financial security; factory branch reporting in particular is incomplete. Compiler emits four pre-existing name-collision warnings. Foundry reports optional invariant discovery methods reverting and build lint warns about external calls, timestamp comparisons, equality checks and deliberate precision-preserving arithmetic; these warnings cannot be dismissed solely because the tests pass.

## Outstanding security verification

**Informational — model scope, `FinancialHandler`**: the handler selects random agreements, and many ineligible operations return; there is no separate successful-transition counter. This limits evidence for rare lifecycle paths. Remediation: choose eligible operations, count transitions, and run the campaign again.

**Informational — collateral fixture, `FinancialHandler.activate`**: local collateral observations are injected into a fixture. The updated stateful model checks the real local vault, while the cross-chain observation remains a fixture. Retain the live finality gate.

**Informational — arithmetic and adversarial coverage**: existing rational-interest fuzz and deterministic adversarial tests do not satisfy the complete requested independent boundary, repayment-sequence and cross-function adversarial review. Expand these before security review. No newly confirmed production vulnerability is asserted by these findings.


## Targeted follow-up at revision `abcf690c2b26f8954fb54e824ad3e1fef693caf6`

The revision records the prior test and documentation. The current working tree extends the test without production-contract changes. The handler selects an eligible agreement by scanning the current ledger and records per-selector calls, ineligible calls, verified transitions, financial operations and amounts. The counters reset per invariant run. Internal funding performed by activation or withdrawal is included in the cash ledger, but is not a separate externally invoked deposit counter. Random campaign totals for successful transitions remain unavailable; call counts are not substitutes.

The directed test emitted these successful transition counts: registrations 3, activations 3, reservations 3, cancellations 1, expiries 1, observations 2, pending clearances 1, executions 1, checkpoints 1, repayments 2 (one partial and one full; one after default), defaults 1, withdrawals 1 and donations 1. All corresponding directed handler invocations were eligible. The scenario executed 200,000,000 token base units and repaid 204,027,400; individual amounts and counters can be reproduced with `forge test --match-test testMeasuredRareTransitionsAndActualCustody -vvvv`.

A real `CollateralVault` is bound and locked for every agreement. The invariants check position ownership, lot binding, 1 ETH per agreement, total locked and actual ETH balance, including after draw, default and settlement. The directed test rejects rebinding and forces 1 ETH into the vault, which remains surplus. The collateral-verifier fixture still supplies the manager's observation: real cross-chain delivery and finality are not verified.

The new `testFuzzRepaymentLedgerSequence` passed 1,000 locally generated combinations of time, checkpoint, partial payment, donation, withdrawal and full payment, checking the independent ledger after each stage. Existing tests address default, transfer failure, duplicate identifiers and overpayment individually; these are not yet incorporated into the fuzzed sequence. The fixed-principal direct rational model and existing tests do not establish maximum-principal or maximum-elapsed arithmetic bounds. Final fractional settlement policy permits at most one base-unit adjustment per remaining fractional obligation; a complete independent boundary campaign remains outstanding.

Both fresh negative-control campaigns used seed `0x1234` after deleting scratch invariant and test-failure caches. Cash mutation `free[lender] += amount + 1` was detected after register, activate, observe, execute, repay; principal mutation `principal[id] = amount + 1` was detected after register, activate, observe, execute. The postcondition that otherwise aborts the handler was removed only in each corresponding mutated scratch test, allowing the invariant to produce a shrunk counterexample. Neither mutation nor that scratch-only test change is in the repository.

### Warning classification and limitations

- `CreditManager.sol:436,450,456,466` names shadow the `agreement` function: compiler naming warning, not an observed behavior defect.
- Timestamp checks enforce signed deadlines and oracle freshness, but depend on chain timestamp behavior near boundaries; accepted local design trade-off, production chain/finality review remains open.
- Strict balance comparisons in `CreditLiquidityVault.creditRepayment` and `CreditManager` enforce exact transfers and reject fee or rebasing behavior. This is an asset compatibility constraint, not a general ERC-20 guarantee.
- Reentrancy lint at external calls flags ordering that remains security-sensitive. Manager and vault entry points use guards and existing malicious fixture tests exercise some reentry; this is not a comprehensive cross-function proof and remains open for review.
- Division-before-multiplication warnings include quotient/remainder decomposition in LTV and interest calculations; the local bounded tests exercise arithmetic, but full supported bounds remain unresolved.
- Constructor zero-check lint at `CreditManager` is subject to constructor code/dependency checks; existing factory invalid-dependency tests pass. The factory's reported zero branch coverage remains an instrumentation or test-coverage limitation, not proof all branches are covered.
- Optional invariant-discovery calls revert because the test does not implement those optional selectors; Foundry successfully discovers the explicitly supplied target selectors. The forced-ETH helper intentionally uses `selfdestruct` only as a test fixture under Cancun semantics.

No new Critical or High production finding has been verified in this targeted work. This statement is not a security clearance; the outstanding test limitations prevent an M2-E completion verdict.

### Follow-up final checks

With the updated handler, the explicit-seed (`0x1234`) invariant campaign passed 1,000 runs at depth 128: 128,000 calls, zero handler reverts and zero discards. Invocation counts match the table above; these still include ineligible calls. The only subsequent code change was to the separate directed expiry test, not the invariant handler or assertion. `forge fmt --check`, forced build, the complete `forge test -vvv`, `forge test --fuzz-runs 1000`, and coverage all passed after that correction; each full suite ran 84 tests with no failures or skips. Coverage for the five financial contracts remains as reported above. No additional independent invariant seed was run.

## M2-F targeted review at `abcf690c2b26f8954fb54e824ad3e1fef693caf6`

The working tree contains the prior unstaged M2-E work plus the new boundary and adversarial tests; no production source was changed. Local financial readiness remains **conditional** on an explicit arithmetic-bound remediation and final review. The review is local, not an audit or evidence of live integration.

### Arithmetic bounds and finding

Let `U = 2^256 - 1` and `D = 630720000`. Registration does not impose a numerical cap. Activation limits `cap` to `floor(value * ltvBps / 10000)`, with `ltvBps <= 5000`, so a maximally valued accepted oracle response yields at most `floor(U/2)` principal, also constrained by reservation cash, signed draw, and market debt. The actual supplied local oracle fixture limits both multiplicands to `uint128`; with maximal values its maximum computed oracle valuation is `floor((2^128-1)^2/10^18)`, hence its maximum LTV bound is `57896044618658097711785492504343953926294709965899343556265` base units. This fixture bound is not enforced on arbitrary oracle implementations or via registration.

Carry is at most `D-1 = 630719999`. The decomposed tail product plus carry is at most `D*(D-1) = 397807717769280000`; its separate quotient products and additions are checked uint256 operations and have no unconditional maximum elapsed time. Interest and cumulative interest totals must individually fit U. A current full claim also requires principal plus whole interest plus any rounding unit to fit U. Repeated interest checkpoints and payments can eventually overflow cumulative recognized interest even when current payable debt fits. There is no on-chain elapsed-time cap or maximum supported accumulated interest smaller than the checked uint256 limits.

**Medium — extreme-amount repayment denial, `CreditManager.repay` and `debtPreview`.** Root cause: both form the complete principal-plus-interest claim in one uint256, before accepting even a partial payment. Preconditions: a signed, funded, activated and drawn agreement near the permissive LTV limit; a local mock oracle returns U and the market's risk functions are mocked. Impact: a sufficiently large but accepted outstanding claim causes preview and every repayment amount to revert; lender recovery is unavailable through this path. `testExtremeValidDrawCanBecomeUnpayableWhenClaimExceedsUint256` creates principal `floor(U/2)`, verifies claim `U-1` at D seconds, then verifies overflow and rollback one second later. The amounts far exceed demonstrated real USDC supply; no live-market exploit is asserted. Remediation requires an explicit enforceable value/time envelope or a wider debt representation and associated financial-model review. A cap alone does not solve arbitrarily long unpaid accrual; do not treat a proposed cap as an implemented fix.

The independent boundary regression also verifies zero elapsed, repeated checkpoints, carry immediately below and above a whole unit, principal extinction with remaining fractional interest, no further interest on zero principal, one final rounding unit, and rejection of a repeated settlement. It does not establish complete mathematical safety for all possible dependency values and uint256 timestamps.

### Combined sequences and operation evidence

The extended `testFuzzRepaymentLedgerSequence` checks ledger consistency around time advancement, checkpoint, partial payment, failed transfer, overpayment, duplicate payment ID, donation, withdrawal, default, repayment after default and full settlement. Failed operations snapshot principal, accrued interest, carry, last accrual, cumulative paid and accrued amounts, lender free cash, vault token balance, payment-used flag and agreement state. It passed 1,000 cases in a local targeted run.

`testDeterministicMultiAgreementCampaign` uses explicit seeds `[0,1,2]` for three different lenders and borrowers and checks the ledger after each register, activate, observe, execute, checkpoint and repayment. It records 3 successful registrations, activations, reservations, observations, executions and checkpoints; 3 partial and 3 full repayments; and one deliberate ineligible execution (4 execution calls total). These are deterministic scenario totals, not aggregated invariant campaign counts. Existing directed coverage separately includes cancellation, expiry, pending clearance and default.

### Consolidated local trust-boundary review

`CollateralVault` accepts one binder-selected borrower and amount per agreement and has no release path; actual custody and forced-ETH surplus are covered locally. `LiquidityVault` separates lender free and reserved cash, requires exact token balance changes, and confines consumption to its fixed manager. `CreditLiquidityVault` credits the lender bound to the consumed reservation after exact receipt and payment-ID checks. `CreditManager` binds signed terms, role-specific nonces, chain and contract domains, requires risk revalidation and signed exact repayment, uses non-reentrant financial paths, and reconciles market debt and token balances. The fixed adapter, market, oracle and collateral verifier remain trust boundaries: their reported facts and implementation integrity are not established by mock tests. `LocalCreditFactory` checks its predicted manager and vault bindings but is restricted to chain ID 31337. Existing reentrancy, authorization, replay, pending recovery, default and settlement regressions reduce but do not eliminate implementation risk.

The extreme arithmetic finding remains open. No other newly reproduced Critical or High local issue is claimed; this review is not sufficient to certify absence of such issues. External authentication, Reactive delivery, source-chain finality, real market/oracle behavior, collateral release and lender recovery remain unverified and are separate gates.

During the M2-F verification run, HEAD changed from `abcf690c2b26f8954fb54e824ad3e1fef693caf6` to `70ecd70005c5fe8d872ce825d6cf61d781f7cda6` (recorded subject: `fuzz tests'`). The new revision records the four previously unstaged M2-E test and documentation files. The remaining M2-F changes were left unstaged; the available evidence does not establish how the commit was created.

M2-F final command results: formatting and forced build passed; the complete `forge test -vvv` and `forge test --fuzz-runs 1000` runs each passed 97 tests with zero failures and skips. Coverage completed successfully, with financial-contract percentages unchanged from the table above. The test count includes inherited execution regressions in the new boundary test contract. Foundry still emits the documented compiler, lint, invariant-discovery and coverage instrumentation warnings.

The final financial invariant campaign passed with seed `0x1234`, 1,000 runs, depth 128, 128,000 handler invocations, zero reverts and zero discards. Per-selector call counts are the same as the earlier seed table and remain distinct from the deterministic successful-transition counts.

## M2-G final arithmetic remediation and verification

Verification baseline `70ecd70005c5fe8d872ce825d6cf61d781f7cda6`; the manager remediation was committed externally during this work as `8ce97bd6227577bc4ded48037bd0eeb2dea5f9b` (subject `running invariant tests`) together with additional test/document work. Final local verification was run on that revision plus the uncommitted formatting and test refinements described below. This review is local testing, **not** an independent security audit.

### Vulnerability and root cause

The reproduced Medium finding was `testExtremeValidDrawCanBecomeUnpayableWhenClaimExceedsUint256`: a signed, activated and drawn agreement with principal `floor((2^256 - 1)/2)` formed a full claim of `2^256 - 2` after `D = 630720000` seconds, and one second later `debtPreview` and every repayment amount reverted on checked arithmetic. The root cause was the absence of a financial value envelope: registration accepted any cap, and the single-word `principal + interest + rounding` expression was assumed representable without proof over an unbounded principal and elapsed-time domain. A principal cap alone is insufficient because interest continues indefinitely after default.

### Implemented remediation

`CreditManager` now rejects an unsupported agreement inside `register`, before signatures are consumed, the lot is bound or liquidity is reserved: `cap <= 1e12`, `autonomousRepayment <= min(cap, 1e12)`, `maturity - drawDeadline <= 365 days`, and a checked uint64 chain timestamp. The constructor checks that the immutable asset reports six decimals. `_validateDraw` repeats the principal ceiling before any vault debit or market call. `drawTimestamp` and `lastAccrued` are uint64, and `checkedTimestamp` rejects values above `2^64 - 1`; `debtPreview`, checkpoints, repayments, default, activation, observation and expiry all use the checked representation. An elapsed interval is computed only after verifying `now >= lastAccrued`. Interest still accrues after maturity and default over the full uint64 range; no cutoff, saturation, forgiveness or truncation was added.

The version 3 EIP-712 type hash, domain, normalized lot derivation, agreement ID, role-specific nonces, deterministic signing vector, autonomous execution authorization, exact market repayment, atomic principal creation, interest-first allocation, fractional carry, measured lender credit, repayment after default, collateral custody and rollback behavior are unchanged.

### Mathematical safety proof

With `P <= 1e12 < 2^40`, `t <= 2^64 - 1`, carry `R < D` and `D = 630720000`, every decomposed product in `_previewInterestAt` is far below `2^256`: the tail `(P mod D) * (t mod D) + R < D^2 < 3.98e17`, and the quotient products are below `2^76`. The carry recurrence telescopes, so cumulative recognized interest at any number of checkpoints equals `floor(P * (now - draw) / D)`, bounded by `MAX_SUPPORTED_INTEREST = 29247120867753601621956`. The full claim including one final rounding unit is at most `MAX_SUPPORTED_CLAIM = 29247120868753601621956`, about `2.5e-56` of `2^256 - 1`. Principal paid is bounded by the original principal and paid interest by accrued interest. Vault free/reserved and total buckets use checked uint256 arithmetic and exact token receipts; no supported lifecycle value wraps. The 365-day limit is contractual term only, not the interest accrual bound.

### Regression and verification results

`testExtremeValidDrawCanBecomeUnpayableWhenClaimExceedsUint256` was converted into `testOriginalExtremeClaimIsRejectedBeforeDebtCreation`, which asserts `InvalidTerms`, absent agreement, zero principal/claim, unused nonces and an unbound lot. Additional tests cover the envelope constants and six-decimal asset, maximum commitment/principal with one-year payoff, one base unit above each limit, over-limit draw rejection with the pending operation preserved, maximum term and one second beyond, invalid and backwards timestamp conversions, maximum elapsed accrual with repeated checkpoints, large interest with partial and full repayment after extended default, fractional carry at maximum principal, exact payoff rounding applied once, failed-registration nonce and liquidity preservation, and unchanged normal-value behavior. Expected values are independently calculated with the rational formula rather than copied from contract outputs.

Executed commands and results:

- `forge fmt --check`: passed after formatting the two changed Solidity files.
- `forge build --force`: Solc 0.8.29, 25 files, successful with warnings (classified below).
- `forge test -vvv`: 108 tests passed, 0 failed, 0 skipped across 9 suites.
- `forge test --fuzz-runs 1000`: 108 tests passed, 0 failed, 0 skipped; the fuzzed ledger sequence ran 1,000 cases.
- Financial invariant campaign with `FOUNDRY_INVARIANT_RUNS=1000`, `FOUNDRY_INVARIANT_DEPTH=128`, `FOUNDRY_INVARIANT_FAIL_ON_REVERT=true`, `--fuzz-seed 0x1234`, `--match-contract CreditFinancialInvariant`: 5 tests passed, 128,000 handler invocations, zero reverts and zero discards. Per-selector counts match the earlier table; these are invocations, not successful transitions.
- `forge coverage --report summary`: CreditManager 98.88% lines (265/268), 96.50% statements (441/457), 75.00% branches (42/56), 100% functions (29/29); CreditLiquidityVault 100/100/100/100; project total 95.42% lines, 93.31% statements, 72.27% branches, 94.38% functions. Coverage measures executed locations, not security.

The two earlier scratch negative controls (one extra unit of credited lender cash; one extra unit of created principal) were detected by the independent ledger invariant and remain prior evidence; they were not re-run during this remediation. No new Critical or High local defect was reproduced after the fix.

### Warning review

Compiler still emits the four pre-existing `agreement` name-shadowing warnings and the test-only `selfdestruct` deprecation warning. Foundry lint still reports pre-existing external-call/reentrancy, strict-balance-equality, constructor zero-check, division-before-multiplication and test timestamp-mutation advisories; the strict comparisons are deliberate six-decimal asset compatibility constraints. The initial guarded uint64 cast introduced an `unsafe cast` lint, so `checkedTimestamp` was rewritten to assign only after an explicit bound check; no new compiler warning remains. No warning was suppressed or treated as proof of safety.

### Remaining findings and gates

No material local financial security defect remains known after this remediation, but this is not a security clearance. Remaining external gates are M1-B live callback authentication/delivery/re-request evidence, source-chain finality attestation, production oracle and market/adapter suitability, collateral release/liquidation design, lender recovery, and real-value authorization. Local fixtures do not establish any of those facts.
