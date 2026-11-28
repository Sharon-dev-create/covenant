# M4-E.2 Stage 3A — DemoMarket preparation

**Not authorized to broadcast.** The user approved Stage 2 closure, without carrying its unused allowance forward. The actual Unichain `CollateralVault` is `0x21AB80a429b48Cc4dFBE35308096930472f56954`; Base cMOCK is `0xC8013185D548990956B9b0CF4bee55C3BE3DF3e9`; Base oracle is `0xeBC6B76b9cA1dA2934D89e43bd72Ef0ba9258680`. Vault receipt/runtime/binder/zero state and Stage 1 token receipt/runtime were reread; Stage 2 spent 0.000019890655107390 Unichain ETH; snapshot balance 0.009915062365238172 ETH and nonce 5/5.

## Stage 3A: one market only

`DemoMarket(actualToken, approvedOperator)` is independent of the vault and manager. It has immutable asset/operator, initially zero debt and simulated collateral for all borrowers. Only the operator can `setPosition`, with bounded nonzero borrower and 100000e6 debt/collateral limits. Its `repay` decreases debt and transfers exact synthetic tokens atomically; adapter will bind to this market. This is explicitly simulated market behavior. Do not set a position, mint, configure oracle or deploy any other component in Stage 3A.

At Base block 64604201: chain 84532, signer `0xb108b6F40E5Aefdc8475b053BE4248C53eF07B0F`, balance 0.029804966758609082 ETH, latest/pending nonce 15/15, gas quote 6000000 wei. Operator previously confirmed keystore address. At nonce 15 the predicted market is `0x2e1DF1C633972B4C8e2d9148484f592A5b48e244`, code `0x` at the check. `eth_estimateGas` with actual token/operator was 356573; exact `DeployM4.deployMarket` signer-specific fork simulation succeeded, one creation, buffered gas 458389. Creation code hash `0x95ed49ab5db7cabfda074896b60ab9dad80c5f66eb321d463770dfffc00bae2b`; expected runtime hash after patching actual token and operator immutables `0x8eedb99eb7ed89d9b77469ab149c4a8ca8dd671df541801aa9c13454b50eb836`. Runtime immutable offsets asset 180,558 and operator 278,772 in this exact build. Verify exact artifact and recompute if compiler/source changes.

With max execution gas price 15000000 wei, buffered execution maximum is 6875835000000 wei. Documented fee oracle quoted 15720864770965 wei in synthetic signed-shape L1 data fees and zero operator fee at assumed gas limit 463545; combined illustrative amount 22596699770965 wei (0.000022596699770965 ETH). The oracle estimate uses public unsigned data and an assumed signature; it is not a hard fee cap. Proposed **0.00006 Base ETH** aggregate ceiling includes contingency; Unichain, Lasna, funding and reserves are zero. Expected signer balance if full ceiling is spent and no other transaction: at least 0.029744966758609082 ETH. Refresh fees, latest/pending nonce, chain, code and predicted address before an authorized broadcast; stop on drift, collision, fee overrun or unresolved transaction. No previous stage allowance carries forward.

## Command for review only — broadcast is not authorized

```bash
export M4_SIGNER=0xb108b6F40E5Aefdc8475b053BE4248C53eF07B0F
export BASE_RPC=https://base-sepolia-rpc.publicnode.com
"$HOME/.foundry/bin/forge" script script/DeployM4.s.sol:DeployM4 \
  --rpc-url "$BASE_RPC" --sender "$M4_SIGNER" \
  --sig 'deployMarket(address,address)' \
  0xC8013185D548990956B9b0CF4bee55C3BE3DF3e9 "$M4_SIGNER" \
  --account covenant-testnet --broadcast \
  --with-gas-price 15000000 --priority-gas-price 1000000 \
  --gas-estimate-multiplier 130
```

After separate authorization and operator broadcast, verify receipt status, chain, sender, nonce and one creation; exact constructor bytecode/arguments, expected deployed address and patched runtime; `asset`, `operator`, zero `debt`/`simulatedCollateral` for planned borrower, balance and actual execution/L1/operator fees; current latest/pending nonce. No market position or demo token issuance. If output is lost reconcile transaction/nonce/receipt/code before any further action; never repeat blindly.

## Stage 3B: distinct authorization and nonce lock

Assuming market is verified at Base nonce 15 and no intervening transaction, top-level verifier nonce 16 `0x62932522aD51c7674EfdC6eEEd9ff34d2cC9c8bb`, adapter nonce 17 `0x4505Adc907a4706B46502f2a2120320eeA45D214`, and outer demo factory nonce 18 `0x7636Ef980CAcf50A85FD0544294A25c9E022a1f6`. Nested `TestnetCreditFactory` is CREATE nonce 1 of outer: `0x525d7D8a4856008dbc7C56C2380F5D9cBC3B1bC2`; its CREATE nonces 1 and 2 are manager `0xF3EB9c4bDD0cB5B538c8B9ccb6b81A7898798E81` and liquidity vault `0x87B3E5Ca30C3CCdD6182539Ffff004dbA47F3865`. Verifier binds source vault, predicted manager, governance, emergency and four attestors; adapter binds token, market and same predicted manager. Factory creates the nested factory, which deploys manager then vault in one transaction and checks reciprocal manager/vault/consumer and dependency bindings. No post-creation configuration call is needed for those constructor bindings. Later separate registry/Reactive/receiver/configure/funding/financial-use transactions consume further nonces and are not Stage 3B.

`testFullPredictedSequenceOnFork` in `docs/M4E2_STAGE3_FORK_HARNESS.txt` passed on a read-only Base fork at nonce 15: market, verifier, adapter and outer factory plus nested manager/vault created in order, with predictions and reciprocal bindings checked. It is one isolated local test using prank and actual Base token/oracle code, actual Unichain vault address as a value; the Base fork cannot verify Unichain code. It is not a transaction-by-transaction fee quote, deployment or live verification. Repeat after actual market is deployed at nonce 16, including actual inputs and full remaining sequence. `eth_estimateGas` for verifier using actual vault and conditional manager returned 1978243. Adapter/factory actual RPC constructor simulations remain unavailable until their dependencies exist; L1 oracle queries on synthetic predicted inputs are not deployment simulations.

Illustrative Stage 3B cost at a 15m wei execution cap: verifier 2571716 assumed gas + 74857584723461 wei synthetic L1 = 113433324723461 wei; adapter 500000 assumed gas + 15586603111747 wei synthetic L1 = 23086603111747 wei; factory 8500000 assumed gas + 269491928025735 wei synthetic L1 = 396991928025735 wei; aggregate **0.000533511855860943 Base ETH**, operator fee quote zero. Assumed gas limits for adapter/factory are not signer-specific deployment estimates. Previous 0.001 Base ETH idea is an unapproved placeholder, not a verified sufficient ceiling. Requote once dependencies exist and assess an adequate execution envelope and fee contingency.

Before pinning P: confirm all constructors and actual addresses; reserve the signer exclusively for nonce 16/17/18; ensure no pending transactions; simulate full remaining sequence; reconcile sufficient funds and every required policy and expenditure approval. If nonce changes after deploying a verifier/adapter, **stop**; do not blindly recompute a new P, because existing immutable pins can strand deployed contracts. Review whether the pinned addresses can still be satisfied and seek a separate recovery decision.

The full financial deployment manifest validator still returns `callback gas not approved`; callback gas and reserves are intentionally later-stage gates. This market-only preflight does not claim the full manifest validates and does not authorize or bypass its checks. No financial callback, collateral lock, lender funding, minting or execution is authorized.

To reproduce the isolated fork harness from the repository root, create a temporary Foundry project under `/tmp` with `src` linked to this repository, put the accompanying harness in its `test/Sequence.t.sol`, set Solidity 0.8.29, Cancun, optimizer 200, and run `forge test --root /tmp/PROJECT --fork-url https://base-sepolia-rpc.publicnode.com --match-test testFullPredictedSequenceOnFork -vvv`. The recorded harness intentionally asserts nonce 15; once the market exists, adapt the local harness to the real nonce-16 remaining sequence rather than forcing nonce state or presenting stale predictions.


## Scoped validator remediation

Stage 3A has an explicit, narrowly scoped offline validation mode; see `M4_STAGE_VALIDATION.md`. The user has authorized the one market deployment under its 0.00006 ETH ceiling. The stage validator checks the fixed action and public evidence, and prints the exact allowed command; independently refresh all RPC state before any manual broadcast. The full financial validator is unchanged and continues to reject unapproved callback gas; a scoped pass is not full system approval. Stage 3B remains a separate authorization and nonce-integrity gate.


## Stage 3A deployment verified and closed

The authorized market `0x2e1DF1C633972B4C8e2d9148484f592A5b48e244` was created in Base transaction `0x377359c66bdac5c651c7423a203fd22bc0700e44b48f0efd9d568fece65b3eb2`, nonce 15, block 64611095. Public receipt, exact creation code and arguments, patched runtime hash, asset, operator and zero initial borrower debt/collateral match. Execution fee 2115642000000 wei, L1 fee 5006914786531 wei, historical operator oracle zero; total 7122556786531 wei under the 60000000000000 wei ceiling. Closing Base balance 29797844201822551 wei, nonce latest/pending 16/16. Stage 3A authorization is exhausted; unused allowance is not carried forward. See `deployments/m4e2.stage3a.verified.json`. Stage 3B remains separate and its validator mode is not implemented.
