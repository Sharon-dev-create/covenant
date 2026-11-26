# M2-E local financial verification (work in progress)

Verification base revision: `f87ce2bb21d441af65aa8a2b69fa52faf7e44f05`. The financial model is exercised by `test/CreditFinancialInvariant.t.sol`; all contracts, markets, collateral observations and oracle data in that test are local fixtures. This document is not an audit or a live integration attestation.

The handler independently tracks deposits, withdrawals, donations, drawdowns, repayments, lender free and reserved amounts, and each agreement's principal, recognized and paid interest, fractional carry and lifecycle. It compares these with manager and vault state after calls. A directed lifecycle covers draw, time advancement, partial payment, default and settlement. The model does not establish that collateral is actually locked: its collateral observations are deliberately mocked. It does not yet measure the number of successful transitions separately from handler invocations; ineligible calls can return without action. It does not yet comprehensively test adversarial token or adapter behavior, bounded arithmetic, or fuzzed repayment sequences beyond existing tests.

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

**Informational — collateral fixture, `FinancialHandler.activate`**: local collateral observations are injected into a fixture. The invariant does not show that the real `CollateralVault` maintains a lock under all credit transitions. Remediation: add an integrated vault model and checks; retain the live finality gate.

**Informational — arithmetic and adversarial coverage**: existing rational-interest fuzz and deterministic adversarial tests do not satisfy the complete requested independent boundary, repayment-sequence and cross-function adversarial review. Expand these before security review. No newly confirmed production vulnerability is asserted by these findings.
