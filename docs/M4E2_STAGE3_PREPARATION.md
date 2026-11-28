# M4-E.2 Stage 3 — dependent Base financial contracts, preparation only

Stage 2 is verified and its authorization is closed; no Stage 3 transaction, participant funding, callback or activation is authorized. Actual dependencies: Unichain vault `0x21AB80a429b48Cc4dFBE35308096930472f56954`, Base cMOCK `0xC8013185D548990956B9b0CF4bee55C3BE3DF3e9`, Base oracle `0xeBC6B76b9cA1dA2934D89e43bd72Ef0ba9258680`. Binder and all candidate operational roles are the explicitly approved testnet signer `0xb108b6F40E5Aefdc8475b053BE4248C53eF07B0F`; four attestors are distinct but a single developer-controlled trust domain. Governance/emergency/source-finality policies still require live operational execution and fail-closed checks.

## Exact dependency order, conditional predictions

At the read-only Base nonce 15 / pending 15, assuming **exactly** one creation each and no intervening transaction:

| Nonce | Contract | Constructor dependencies | Conditional CREATE address |
|---:|---|---|---|
| 15 | `DemoMarket` | actual cMOCK, approved operator | `0x2e1DF1C633972B4C8e2d9148484f592A5b48e244` |
| 16 | `CollateralAttestationVerifier` | actual vault, predicted manager, governance, emergency, four attestors | `0x62932522aD51c7674EfdC6eEEd9ff34d2cC9c8bb` |
| 17 | `DemoAdapter` | actual cMOCK, actual market, predicted manager | `0x4505Adc907a4706B46502f2a2120320eeA45D214` |
| 18 | `DemoDeploymentFactory` | actual token, verifier, oracle, adapter | `0x7636Ef980CAcf50A85FD0544294A25c9E022a1f6` |

Outer factory creates nested `TestnetCreditFactory` `0x525d7D8a4856008dbc7C56C2380F5D9cBC3B1bC2`, which creates manager `0xF3EB9c4bDD0cB5B538c8B9ccb6b81A7898798E81` and liquidity vault `0x87B3E5Ca30C3CCdD6182539Ffff004dbA47F3865` atomically in one creation transaction, checking asset, verifier, oracle, adapter and reciprocal manager/vault/consumer bindings. All addresses in the table and nested paths are predictions, not deployments. `DeployM4.predicted` and `deployFactory` enforce expected CREATE and selected bindings, but cannot reverse earlier deployments if a later step fails. Validate bytecode and getters, receipts and nonce after each deployment. **The verifier and adapter permanently bind predicted manager P; a subsequent signer nonce drift makes the predicted factory impossible at its intended nonce and can strand those deployments.** No unrelated Base signer transaction can occur after pinning; re-estimate and re-predict before every step. Any nonce change or loss of access requires stopping and a new plan.

## Current read-only estimates and incomplete budget

Base block 64601383 signer balance 0.029804966758609082 ETH, nonce 15/15, current gas quote 6000000 wei. Simulated constructor calls use the public signer and actual token/vault; a synthetic L1 quote uses unsigned public bytecode and hypothetical signature shape. The market and verifier estimates do not establish a successful sequential broadcast. Values can change, L1/operator fees are not hard-capped by gas prices.

| Transaction | Gas evidence | Synthetic L1 fee | Planning cost using 15m wei max execution price |
|---|---|---:|---:|
| Market | 356573 eth_estimateGas; assumed limit 463545 | 11103367166837 wei | 18056542166837 wei |
| Verifier | 1978243 eth_estimateGas with actual vault and conditional manager; assumed limit 2571716 | 51120968568104 wei | 89696708568104 wei |
| Adapter | actual market does not exist; local constructor trace 329018; **assumed**, not simulated, limit 500000 | 9303678949580 wei with hypothetical addresses | 16803678949580 wei |
| Outer factory including nested creations | dependencies do not exist; local constructor trace 5910339; **assumed**, not simulated, limit 8500000 | 160860346534722 wei with hypothetical addresses | 288360346534722 wei |

Operator fee oracle returned zero under these assumptions. Sum of illustrative planning costs is **0.000412917276219243 Base ETH**, excluding fee drift and uncertainty; this is not a measured end-to-end quote or a hard maximum. A **0.001 Base ETH** aggregate expenditure ceiling is a provisional discussion figure only, not yet a safe verified ceiling or an authorization request ready for acceptance. It would allow ~2.4x this partial estimate; query actual-address gas and data fees and account for fee volatility, verifier and adapter nonce pinning, all transaction receipts and contingency before requesting approval. Unichain/Lasna signer expenditure, deposits, issuance and participant funding are outside this group. Recompute every limit and prediction; never add the unused Stage 1 or Stage 2 allowance.

## Remaining work before authorization

The `DeployM4` market script was simulated at actual Base nonce 15 using the verified token: predicted market matches, Forge buffered gas 458389, no broadcast. The verifier script also simulated successfully against the actual collateral vault and conditional manager, buffered gas 2549960, but because both independent simulations ran at nonce 15 its simulated verifier address was the market prediction; repeat at actual nonce 16 after market verification. Adapter cannot be meaningfully simulated against the actual market until it exists; the factory cannot be meaningfully simulated until verifier and adapter exist. Resolve whether to seek a staged conditional spending approval or separate substage ceilings, while not disguising unavailable simulations as measurements. After group deployment, registry, financial Reactive, callback receiver, subscription configuration, 1m–3m callback gas, new reserves, lender/borrower funding, oracle setup, attestation and financial execution remain separately gated. The current full financial manifest validator correctly rejects pending callback gas; do not bypass it. No broadcast command is supplied for Stage 3.
