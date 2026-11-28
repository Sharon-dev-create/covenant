# M4-E.2 Stage 3B — nonce-sensitive financial deployment preparation

**Not authorized and not ready for broadcast.** Stage 3A DemoMarket `0x2e1DF1C633972B4C8e2d9148484f592A5b48e244` is independently verified; actual token `0xC8013185D548990956B9b0CF4bee55C3BE3DF3e9`, oracle `0xeBC6B76b9cA1dA2934D89e43bd72Ef0ba9258680` and source vault `0x21AB80a429b48Cc4dFBE35308096930472f56954`. No market position, issuance, funding or collateral lock is included.

## CREATE plan — predictions, not deployments

Base signer `0xb108b6F40E5Aefdc8475b053BE4248C53eF07B0F` nonce 16/16 at block 64611532; reserve it exclusively during the sequence. All top-level calls are zero-value creations; three signer nonces are consumed:

| Signer nonce | Creation and immutable constructor inputs | Conditional address |
|---:|---|---|
| 16 | `CollateralAttestationVerifier(actualUnichainVault, predictedManager, signerGovernance, signerEmergency, [signer,attestor2,attestor3,attestor4])` | `0x62932522aD51c7674EfdC6eEEd9ff34d2cC9c8bb` |
| 17 | `DemoAdapter(actualToken, actualMarket, predictedManager)` | `0x4505Adc907a4706B46502f2a2120320eeA45D214` |
| 18 | `DemoDeploymentFactory(actualToken, actualVerifier, actualOracle, actualAdapter)` | `0x7636Ef980CAcf50A85FD0544294A25c9E022a1f6` |

The outer factory's CREATE nonce 1 is nested factory `0x525d7D8a4856008dbc7C56C2380F5D9cBC3B1bC2`; nested factory CREATE nonce 1 is manager `0xF3EB9c4bDD0cB5B538c8B9ccb6b81A7898798E81` and nonce 2 is liquidity vault `0x87B3E5Ca30C3CCdD6182539Ffff004dbA47F3865`. Factory and all three nested creations occur atomically within the outer factory transaction. Verify `manager.vault`, `manager.asset`, `manager.localCollateralVerifier`, `localOracle`, `localAdapter`, vault `asset`, `manager` and `consumer`, verifier source and manager and adapter token/market/manager. Four attestors are distinct and developer-controlled in one trust domain. Verifier accepts three or four unique authorized signatures, has 1800-second max remaining validity, 24-hour rotation, initial epoch/policy 1 and pause false. The manager allows at most 300e6 cMOCK per agreement and lifetime principal per deployment, and cMOCK has six decimals. Initial manager lifetime principal and vault free/reserved and token balance should be zero. No additional top-level initialization transaction is required for these constructor bindings; later source binder, registry, financial callbacks and funding remain separately gated.

Verifier and adapter each permanently pin predicted manager before the manager exists. A nonce-16 or nonce-17 receipt cannot be undone if a later signer nonce changes or the factory fails. Before the first manager-bound creation, review all constructor values, actual on-chain dependency runtimes, exact predicted CREATE addresses, all available simulations, budgets and approvals. Stop on any pending or unexpected transaction. If the nonce changes after either immutable is deployed, do not recompute and continue blindly; the existing manager pin may be unsatisfiable and contracts may be stranded. Analyze actual CREATE address reachability and ask for separate recovery authorization.

## Isolated fork simulation

`docs/M4E2_STAGE3B_FORK_HARNESS.txt` ran `testStage3BRemainingSequenceOnFork` against a fresh Base fork at nonce 16: **1 passed, 0 failed**. It used actual deployed Base token, oracle and market and supplied the verified Unichain vault address as a cross-chain value. It locally created verifier/adapter/factory in exact nonce order, checked all predicted addresses, four signers, epoch/policy, governance, manager/vault reciprocal bindings, six decimals, 300e6 limits, zero lifetime principal and initial vault cash. A separate trace measured constructor execution: verifier 1,961,508 gas, adapter 329,018, outer factory including nested manager/vault 5,910,339. These are fork traces, not network transactions or complete L1-inclusive cost. The Base fork does not verify Unichain consensus or code at U. Independently validate that dependency on Unichain. Repeat after every relevant state or nonce change.

Verifier and adapter `eth_estimateGas` calls against live Base succeeded with actual token, market and vault address plus conditional P; actual `DeployM4` functions each simulated without broadcast. Both independent script simulations ran at the current nonce 16, so the adapter returned the verifier's temporary nonce-16 address rather than the future actual nonce-17 address. Re-simulate adapter after verifier receipt. Factory cannot be simulated by a direct live-state RPC until the verifier and adapter actually exist; the full sequential local fork test supplies conditional integration evidence, not a current signer-specific factory estimate.

## Itemized provisional expenditure proposal — not approved

At Base snapshot block 64611532 gas quote 6000000 wei, signer balance 0.029797844201822551 ETH, latest/pending 16/16. Illustrative max execution prices 15000000 wei per gas; unsigned synthetic L1 fee quotes and 130% gas estimates for live-state constructors. Factory gas limit 8500000 is an assumption, not a live-state estimate. Operator-fee oracle quoted zero. No L1/operator charge is hard-capped by transaction gas price.

| Transaction | Signer-specific gas / assumed gas limit | Execution maximum wei | Synthetic L1 wei | Operator quote wei | Illustrative total wei |
|---|---:|---:|---:|---:|---:|
| Verifier | 1978243 / 2571716 | 38575740000000 | 29837262468136 | 0 | 68413002468136 |
| Adapter | 332797 / 432637 | 6489555000000 | 5134004826925 | 0 | 11623559826925 |
| Outer factory + nested creates | unavailable until dependencies / 8500000 assumption | 127500000000000 | 88766798601466 | 0 | 216266798601466 |
| Total | — | — | — | — | 296303360896527 |

Discussion-only candidate **0.001 Base ETH** for the three Stage 3B transactions allows approximately 0.000703696639103473 ETH over these mixed measured/assumed figures. It is not an approved ceiling or guaranteed sufficient: factory actual-state gas and live postdependency L1 prices remain unknown, and fees may change. No Unichain or Lasna fees, provider reserves, participant funding, token issuance or collateral lock are included. Requote before each transaction; each transaction must fit the remaining scoped limit including L1/operator charges. Do not carry Stage 3A unused allowance.

## Updated validation and authorization status

The strict `stage3b-plan` preparation and `stage3b-broadcast` authorization modes now exist. Full `plan` and `wired` validation continue to require separate callback gas approval. The figures above are historical; see [the current Stage 3B readiness package](M4E2_STAGE3B_READY.md) for the refreshed estimates, conditional commands and gates. The current manifest does not authorize a broadcast. Factory live-state simulation remains dependent on the preceding deployments.
