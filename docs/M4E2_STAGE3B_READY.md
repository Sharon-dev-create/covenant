# M4-E.2 Stage 3B — preparation validated; authorization pending

Stage 3A approved/closed: DemoMarket `0x2e1DF1C633972B4C8e2d9148484f592A5b48e244`, receipt `0x377359c66bdac5c651c7423a203fd22bc0700e44b48f0efd9d568fece65b3eb2`, cost 7122556786531 wei. No Stage 3B broadcast is authorized. The Stage 3A allowance is not carried forward.

## Validation and scope

`python3 script/check_m4_manifest.py deployments/m4e2.stage3b.pending.json stage3b-plan` checks only a fixed three-transaction sequence and reports preparation only. `stage3b-broadcast` additionally requires explicit operator approval, exact approved aggregate and per-transaction limits, unconsumed authorization and evidence; it currently rejects the pending manifest. Neither implies full financial readiness. The existing full `plan`/`wired` modes remain strict and reject unapproved callback gas. These are offline operational checks: the manifest, trace and approvals are recorded statements and `DeployM4` does not invoke the validator. Independently refresh current RPC values and compare the exact command before each manual send. No generic skip or force option was added.

The signer is `0xb108b6F40E5Aefdc8475b053BE4248C53eF07B0F`, Base snapshot block 64615009 balance 0.029797844201822551 ETH, latest/pending nonce 16/16, gas quote 6000000 wei. Token `0xC8013185D548990956B9b0CF4bee55C3BE3DF3e9`, oracle `0xeBC6B76b9cA1dA2934D89e43bd72Ef0ba9258680`, market `0x2e1DF1C633972B4C8e2d9148484f592A5b48e244`, and Unichain vault `0x21AB80a429b48Cc4dFBE35308096930472f56954` are actual verified deployments. Six predicted Base addresses had no code at the read-only check.

| Creator / nonce | Deployment | Conditional address | Fork runtime hash |
|---|---|---|---|
| signer / 16 | verifier | `0x62932522aD51c7674EfdC6eEEd9ff34d2cC9c8bb` | `0x2177b31f48a4094a183d4415517188e5694580226f50bcdebe7305024ba1d375` |
| signer / 17 | adapter | `0x4505Adc907a4706B46502f2a2120320eeA45D214` | `0x8159ae3bf694d3d99ede273b53938e0487eb304d7a030731adfab87c5f454998` |
| signer / 18 | demo factory | `0x7636Ef980CAcf50A85FD0544294A25c9E022a1f6` | `0xe8eefbb00dd1dd335136e7dcc36755a6acd93d0c47f3f723c3e609e32348782a` |
| demo factory / 1 | nested factory | `0x525d7D8a4856008dbc7C56C2380F5D9cBC3B1bC2` | `0xb6ebfad0925b141f6e09406eded75af8d994fdae4267c5a54ad84ca90a5f12e8` |
| nested factory / 1 | manager | `0xF3EB9c4bDD0cB5B538c8B9ccb6b81A7898798E81` | `0xb15816636f880a02935e8cf806b624778646d67346a77c233a86d9e39f2eedb0` |
| nested factory / 2 | liquidity vault | `0x87B3E5Ca30C3CCdD6182539Ffff004dbA47F3865` | `0x6ff13cdb7d603060ccd21c0d75de1ea7e01636a1cbb6cb39dc96876bf64cffc4` |

The deployed runtimes are **fork predictions**, generated with these constructor immutables; not live code. Artifact creation hashes and exact constructor schema are recorded in the pending manifest. The Base-fork trace `deployments/m4e2.stage3b.fork-trace.txt` and harness `docs/M4E2_STAGE3B_FORK_HARNESS.txt` simulate all three EOA creations at nonce 16/17/18 with nested creation order, actual Base dependencies and the Unichain vault address as a value. The test passed and checked the four distinct attestors, governance/emergency, 3-of-4 contract mechanism, six-decimal asset, 300e6 caps, zero lifetime principal/free/reserved and reciprocal bindings. Existing verifier signature validation is covered by local integration tests; this fork test does not produce live attestations or independently inspect source-chain consensus. All four attestors remain one developer trust domain.

The verifier/adapter/factory constructors perform required bindings in their creation sequence; no extra signer transaction is needed for their internal wiring. Later vault agreement binding, financial registry, Reactive, receiver, callbacks, reserves and demo operations are outside this stage. The verifier and adapter pin the predicted manager before it exists. Reserve the signer from unrelated Base transactions once this sequence starts. An unexpected nonce after either pin may strand existing deployments: stop, assess the actual immutable bindings and CREATE address reachability, and obtain separate recovery authorization; do not merely recompute and continue.

## Expenditure proposal — unapproved, operational caps

| Item | Execution gas evidence / buffered gas | Execution cap at 15m wei | Synthetic L1 | Operator quote | Estimated total | Proposed per-tx cap |
|---|---|---:|---:|---:|---:|---:|
| Verifier | 1978243 live estimate / 2571716 | 38575740000000 | 19264772918574 | 0 | 57840512918574 | 150000000000000 |
| Adapter | 332797 live estimate / 432637 | 6489555000000 | 3205133962319 | 0 | 9694688962319 | 80000000000000 |
| Factory, including all nested creations | 5910339 fork constructor trace / 8500000 assumed | 127500000000000 | 55416675775573 | 0 | 182916675775573 | 550000000000000 |

The illustrative total is **250451877656466 wei = 0.000250451877656466 ETH**. Propose **0.001 Base ETH aggregate**, per-transaction caps of **0.00015 / 0.00008 / 0.00055 ETH**, with 0.00022 ETH aggregate unallocated beyond their sum; none is approved. The aggregate offers ~0.000749548122343534 ETH over the mixed estimate. If entirely spent and no other Base activity, balance would be ~0.028797844201822551 ETH. No Unichain/Lasna spending, reserve deposits or participant funding is included. Factory L1 is quoted on exact synthetic constructor calldata with predicted dependency addresses and an 8.5m gas assumption; actual live-state gas is unavailable until verifier and adapter exist. Synthetic signature bytes, future nonce, fees and provider limits may change. Price cap limits execution fee only; it cannot hard-cap rollup data fees. Refresh every quote and stop before the corresponding cap or aggregate can be exceeded.

## Conditional commands — NOT authorized

These commands are for review. The operator must first approve the sequence and exact aggregate/per-transaction caps, record that authorization, pass `stage3b-broadcast`, refresh all on-chain assumptions and perform them sequentially. Do not use the signer for unrelated Base transactions. Stop after each transaction until receipt, chain, nonce, actual expenditure, runtime and bindings are independently verified. Never repeat a transaction because output is lost.

```bash
export M4_SIGNER=0xb108b6F40E5Aefdc8475b053BE4248C53eF07B0F
export BASE_RPC=https://base-sepolia-rpc.publicnode.com
F="$HOME/.foundry/bin/forge"
"$F" script script/DeployM4.s.sol:DeployM4 --rpc-url "$BASE_RPC" --sender "$M4_SIGNER" \
  --sig 'deployVerifier(address,address,address,address,address[4])' \
  0x21AB80a429b48Cc4dFBE35308096930472f56954 0xF3EB9c4bDD0cB5B538c8B9ccb6b81A7898798E81 \
  "$M4_SIGNER" "$M4_SIGNER" \
  '[0xb108b6F40E5Aefdc8475b053BE4248C53eF07B0F,0x6F4AE62FeE718db67652500807886052e98eA422,0xAc1a3B8c98883e8F1D5e014e547cc0E109Ead4c9,0x1243b643C14E8A916f3Cef5474B0E047Af0757A0]' \
  --account covenant-testnet --broadcast --with-gas-price 15000000 --priority-gas-price 1000000 --gas-estimate-multiplier 130
```

Only after verifier receipt and runtime/bindings/nonce 17 verification and a fresh actual-state simulation:

```bash
"$F" script script/DeployM4.s.sol:DeployM4 --rpc-url "$BASE_RPC" --sender "$M4_SIGNER" \
  --sig 'deployAdapter(address,address,address)' \
  0xC8013185D548990956B9b0CF4bee55C3BE3DF3e9 0x2e1DF1C633972B4C8e2d9148484f592A5b48e244 0xF3EB9c4bDD0cB5B538c8B9ccb6b81A7898798E81 \
  --account covenant-testnet --broadcast --with-gas-price 15000000 --priority-gas-price 1000000 --gas-estimate-multiplier 130
```

Only after adapter receipt and runtime/bindings/nonce 18 verification, actual dependency code checks and an actual-state factory simulation:

```bash
"$F" script script/DeployM4.s.sol:DeployM4 --rpc-url "$BASE_RPC" --sender "$M4_SIGNER" \
  --sig 'deployFactory(address,address,address,address,address,address)' \
  "$M4_SIGNER" 0xC8013185D548990956B9b0CF4bee55C3BE3DF3e9 0x62932522aD51c7674EfdC6eEEd9ff34d2cC9c8bb \
  0xeBC6B76b9cA1dA2934D89e43bd72Ef0ba9258680 0x4505Adc907a4706B46502f2a2120320eeA45D214 0x7636Ef980CAcf50A85FD0544294A25c9E022a1f6 \
  --account covenant-testnet --broadcast --with-gas-price 15000000 --priority-gas-price 1000000 --gas-estimate-multiplier 130
```

For each receipt check success, chain, signer, exact nonce and creation initcode/arguments, runtime with immutable patches, all constructor getters and actual execution/L1/operator charges. Factory verification additionally requires trace of the nested creation tree and manager/vault/asset/verifier/oracle/adapter reciprocal getters, caps and zero initial accounting. Check expected contracts have no previous code before each creation, latest and pending nonce match, and total actual + projected charges fit the approved limits.

## Later callback gate

Financial Reactive permits destination callback 1m–3m gas. Reactive's official docs state a 100000 destination minimum and a **separate** 900000 cap for Reactive execution, not a verified destination maximum; the destination proxy withholds `_extraGas` and `_maxChargeGas`. The previously measured 635819 local successful receiver trace omits real proxy overhead. At the latest Base provider snapshot coefficient was 1100, extraGas 80000 and maxChargeGas 50000. Failed callbacks are charged; size and fund separate reserves only after actual dependencies exist, target-chain simulations and a separately authorized bounded live callback/failure/retry measurement. No provider reserve or callback gas is approved. See https://dev.reactive.network/economy and https://dev.reactive.network/callback-contracts.
