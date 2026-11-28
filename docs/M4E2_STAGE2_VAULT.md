# M4-E.2 Stage 2 — collateral vault deployment preflight

**Pending separate Stage 2 broadcast authorization.** Stage 1 is operator-approved and closed: token `0xC8013185D548990956B9b0CF4bee55C3BE3DF3e9`, oracle `0xeBC6B76b9cA1dA2934D89e43bd72Ef0ba9258680`, known Base fee 13014395007204 wei. Receipts, initcode/constructor and runtimes were rechecked against `deployments/m4e2.stage1.verified.json`. The unused Stage 1 allowance cannot fund Stage 2. No collateral, funding transfer, bind or financial activation is included.

## Scope and safety

One `CollateralVault` on Unichain Sepolia 1301; constructor `binder=0xb108b6F40E5Aefdc8475b053BE4248C53eF07B0F` (explicitly approved); zero ETH value. `DeployM4.deployCollateral` checks chain 1301, approved binder and deployer M4_SIGNER. The vault itself does not restrict construction to 1301; it stores the actual deployment `block.chainid` immutably and includes it, its own address and agreement ID in `positionId`. The binder can bind a nonzero agreement once to a nonzero borrower and positive fixed amount; only that borrower can lock the exact amount once for the deterministic lot. Its public managed counter tracks locks and `totalReleased` is zero; no release, transfer, withdrawal or seizure function exists. Ether forced to the contract may cause balance to exceed `totalLocked`, reported as surplus. Existing vault invariants and no-release tests passed in the accepted 203-test suite; they do not establish production custody safety. The planned 0.001 test ETH deposit, even if later approved, is permanently locked and is not part of this stage.

## Current read-only preflight

Unichain public RPC `https://unichain-sepolia-rpc.publicnode.com`; chain ID 1301, observed block 68989256, candidate deployer balance 0.009934953020345562 ETH, nonce latest/pending 4/4, gas quote 1500000 wei. Signer public address/keystore correspondence was confirmed by the operator previously, not unlocked here. Current provider implementation/hash in the M4 financial readiness snapshot matched; provider reserve is unrelated to this deployment.

The `CollateralVault` constructor creation bytecode hash is `0x38a96808d7a557352a2cf4721398de77d713e06d5273d17dc533be5f24d4d4e8`; the expected runtime hash after patching the binder and chain 1301 immutable references in the exact compiled artifact is `0x5403b0445d1270d125ae86c25f4a6ca4daefd9ff1169a559e1aeb20c10f943c0`. The 32-byte binder occupies runtime immutable offsets 371 and 1047; the 32-byte chain ID occupies offset 1411 (compiler/bytecode-specific, verify against the exact artifact). Recompute hashes if artifacts change.

Signer-specific `eth_estimateGas` returned 445542. Existing `DeployM4.deployCollateral` completed an independent non-broadcast fork simulation, one creation, gas limit estimate 573138 with 130% multiplier, and predicted address `0x21AB80a429b48Cc4dFBE35308096930472f56954`; public `eth_getCode` at that address returned `0x`. This prediction is conditional on signer nonce 4. An EVM simulation and the fee oracle use public unsigned/synthetic data; no keystore was accessed.

At gas-price cap 4000000 wei, buffered execution maximum is 2292552000000 wei (0.000002292552 ETH). Documented OP-stack oracle quoted 15861088076880 wei (0.000015861088076880 ETH) L1 for synthetic signed-shape bytes, and zero operator fee at the simulated buffered gas. Aggregate illustrative execution cap plus L1 is 18153640076880 wei (0.000018153640076880 ETH). This is not a hard bound: calldata compression, final signature, oracle parameters and gas limits can vary. Proposed aggregate Stage 2 ceiling **0.00005 Unichain ETH**, with Base/Lasna expenditure **zero**, includes contingency; at the ceiling and no other spend, predicted signer balance >=0.009884953020345562 ETH. Refresh nonce, empty address, exact tx gas, fees and remaining ceiling immediately before any authorized broadcast; stop rather than exceed it.

## Operator command — do not execute until separately authorized

```bash
export M4_SIGNER=0xb108b6F40E5Aefdc8475b053BE4248C53eF07B0F
export UNI_RPC=https://unichain-sepolia-rpc.publicnode.com
"$HOME/.foundry/bin/forge" script script/DeployM4.s.sol:DeployM4 \
  --rpc-url "$UNI_RPC" --sender "$M4_SIGNER" \
  --sig 'deployCollateral(address)' "$M4_SIGNER" \
  --account covenant-testnet --broadcast \
  --with-gas-price 4000000 --priority-gas-price 1000000 \
  --gas-estimate-multiplier 130
```

Before send recheck account identity locally, chain ID, latest/pending nonce, predicted `cast compute-address`, target code, exact artifact hashes, dry-run and L1/operator fee. A gas cap does not limit data/operator fees and Forge's multiplier is not a hard upper bound on costs. Stop on pending/unexplained nonce, code collision, signer mismatch, unexpected creation, failed simulation, fee jump or projected ceiling overrun. If output is lost reconcile latest/pending nonce, transaction history, receipt, code and state before any further action; never repeat blindly.

After the operator's single send, independently verify public receipt success, chain, signer, nonce, exact creation bytecode and encoded binder, address, one creation, actual execution/L1/operator charges and latest/pending nonce. Compare code hash to patched runtime hash above; read `binder()`, `totalLocked()==0`, `totalReleased()==0`, `surplus()==0` and contract balance zero, and test a public deterministic `positionId` against `keccak256(abi.encode("LOT_V1",1301,actualVault,agreementId))`. Exact creation transaction and chain-specific patched runtime establish the private chain immutable; `positionId` validates its effect. Check that addresses and receipt are not duplicates. Record actual findings in Stage 2 evidence, do not alter financial state.

## Subsequent dependency group — not authorized

With the verified actual vault U, verified Base `DemoToken` T and `DemoOracle` O, next Base group is `DemoMarket(T,operator)`, then calculate outer demo factory F, nested factory N, manager P and vault V at the predicted Base nonce. `CollateralAttestationVerifier(U,P,governance,emergency,attestors)` and `DemoAdapter(T,market,P)` are deployed before `DemoDeploymentFactory(T,verifier,O,adapter)`; the factory must be at F. The latter creates N, which creates P then V in the same constructor transaction; manager and vault reciprocal bindings and dependencies are checked atomically. A signer nonce change changes F/N/P/V, invalidating already-pinned verifier and adapter; stop and replan, do not deploy against stale predictions. Later risk registry, financial Reactive, receiver, subscriptions, financial reserves and all participation/activation remain separately gated. No dependent deployment is approved by this report.


## Stage 2 verified and closed

Transaction `0x9f9aef17c74e69f63a3bcf455c64d53822bba128fda831b6257e3bf2028c0dfd` succeeded at block 68989688 using nonce 4. Actual vault `0x21AB80a429b48Cc4dFBE35308096930472f56954`; transaction initcode and binder, patched runtime, binder getter and 1301-specific lot derivation match. Contract balance, total locked, total released and surplus are zero. Receipt execution cost 661314000000 wei, L1 fee 19229341107390 wei and operator oracle at receipt block zero; total 19890655107390 wei, below 50000000000000 wei ceiling. Unichain signer closed at 9915062365238172 wei, latest/pending nonce 5/5. Stage 2 authorization closed; unused allowance is not carried forward. See `deployments/m4e2.stage2.verified.json`.
