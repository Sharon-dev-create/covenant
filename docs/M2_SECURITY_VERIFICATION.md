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
