# Integrated verification

The initial clean checkpoint was aa1e16f69f50f6c6bc184b8d4074767a7cd19d20. The referenced 84b45ac recorded M3-C and initial M3-D implementation; the current checkpoint contains the subsequent M3-D verification. Baseline: 162 tests passed, zero failed or skipped. No statement about how the earlier revision was created is inferred from Git metadata.

`M4DeploymentGuardsTest` simulates the full deployment order across chain-ID fixtures with mocked provider contracts, checks factory CREATE address prediction, verifies dependency bindings and checks invalid inputs. This is local simulation, not public chain deployment. `M4IntegratedInvariant` adds a bounded one-agreement reference ledger over initialization, request, pause, attempted paused callback, resume, execution/duplicate and repayment. Its directed test proves meaningful transitions occur; invocation counts alone do not prove that. It reconciles free/reserved cash, actual token cash, debt, authorized 200 principal, 800-to-600 market reduction and locked collateral. Requests do not change balances, failed paused attempts roll back, duplicates do not draw again. The larger existing M3-B aggregate-cap cases cover multiple agreements and non-replenishment; existing M3-D cases cover conflicting evidence, competing executors, and other callback outcomes. This model is bounded, not a proof for arbitrary inputs or live provider behavior.

## Gas observations

Optimized local `gasleft()` around the mock proxy and receiver call, with one-transaction fixtures and warm accesses, yielded:

| Path | Local gas |
|---|---:|
| Successful callback | 667,671 |
| Duplicate | 61,421 |
| Expired/obsolete | 131,998 |
| Recovered position | 172,364 |
| Temporary paused failure | 241,991 |
| Successful retry | 672,257 |

A local proxy fixture forwards 870,000 gas, modeling a 1,000,000 callback budget after historical 80,000 + 50,000 provider overhead; successful and retry paths pass. This is not an observed Omni forwarding rule or a worst-case bound; transaction warmness, actual proxy implementation, events, fee parameters and state affect gas. Current [Reactive economy documentation](https://dev.reactive.network/economy) describes a 900,000 gas cap for the Reactive transaction, a 100,000 minimum callback gas, and provider overhead and charges; the former is not a financial callback maximum. Failed calls may incur charges and provider debt can prevent execution. The financial contract allows 1,000,000–3,000,000 callback gas. One million is a local candidate only, not a verified live setting: inspect actual proxy parameters and supported limits, run fresh signer-specific simulations and live transport checks before approval. The 300,000 transport-probe setting is not appropriate evidence for this execution.

The financial campaign and coverage results belong in the final execution report; M4 artifacts do not imply a live callback, independent source finality, operational approvals or an audit.

## M4 local campaign results

On the M4 working tree, `forge fmt --check` and forced build passed. The full regression and the 1,000-fuzz-run suite each passed 203 tests (including inherited tests), with zero failures or skips. Both the existing financial invariant and focused callback invariant passed 1,000 runs at depth 128, 128,000 handler invocations and zero reverts, seed `0x4a`. Handler invocation totals include guarded no-ops; they do not count successful transitions. The directed integrated model separately executes one initialization, request, paused failed delivery, recovery, callback execution, duplicate and repayment with suspension active. Existing compiler naming/lint and Foundry optional invariant-discovery warnings remain; they were not suppressed. Coverage is optimizer-disabled and must not be interpreted as live-chain coverage.

`forge coverage --report summary` passed: total line 94.43%, statement 92.75%, branch 63.51%, function 95.26%; financial receiver line 95.92%/branch 78.95%, financial Reactive line 98.28%/branch 60%, registry line 95.35%/branch 42.86%. Coverage reflects local fixtures and is not evidence of provider compatibility.
