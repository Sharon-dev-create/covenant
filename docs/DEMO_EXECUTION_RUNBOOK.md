# Demonstration runbook — preparation only

Do not run transactions until M1-B live evidence, identities, costs and explicit broadcast authorization are approved. Never pass secrets in shell arguments. Use encrypted Foundry accounts and public chain-specific RPCs. Use fresh per-network nonces; record each receipt, deployment block, address, runtime hash and constructor values in a private working copy of the public-only manifest.

## Deployment simulations

Set only public configuration (replace placeholders):

```bash
export M4_SIGNER=0xPUBLIC_DEPLOYER
export BASE_RPC=https://sepolia.base.org
export UNI_RPC=https://sepolia.unichain.org
export LASNA_RPC=https://lasna-rpc.rnk.dev/
forge="$HOME/.foundry/bin/forge"
cast="$HOME/.foundry/bin/cast"
"$cast" chain-id --rpc-url "$BASE_RPC"  # 84532
"$cast" chain-id --rpc-url "$UNI_RPC"   # 1301
"$cast" chain-id --rpc-url "$LASNA_RPC" # 5318007
```

Copy the example manifest, fill in the public roles, approved policy, gas and reserves, then run `python3 script/check_m4_manifest.py YOUR_MANIFEST plan`. After deployments and address recording run the same command with `wired`; this is an offline structural check, not proof of approval, chain state or bytecode. The template intentionally fails.

For each step use `forge script script/DeployM4.s.sol:DeployM4 --rpc-url "$RPC" --sender "$M4_SIGNER" --sig 'FUNCTION_SIGNATURE' ARG...` with no `--broadcast` for simulation. The entrypoints in order are `deployCollateral(address)` on Unichain; `deployAsset(address)`, `deployOracle(address)`, `deployMarket(address,address)` on Base; `predicted(address,uint256)` using the current Base signer nonce + 2; `deployVerifier(address,address,address,address,address[4])`, `deployAdapter(address,address,address)`, `deployFactory(address,address,address,address,address,address)`, `deployRegistry(address,address)` on Base; `deployReactive(address)` on Lasna; `deployReceiver(address,address,address)` on Base. `deployFactory` needs expected outer address as its last argument; verifier/adapter need the predicted manager. Verify actual sender nonce after each confirmed deployment; abort on any intervening transaction. Use the public source, manager, roles and four approved attestors as arguments. Stop if any dependency is missing. View helpers `verifyCollateral`, `verifyBase`, `verifyLasna` check local-chain bindings; check remote-chain code independently. Configure on Lasna via `configure(address,address,address,address,uint64,address)` with registry, manager, receiver, approved gas and actual operator (operator must also be the script signer). Each financial contract needs a separate `fund(address,uint256)` on its own provider chain. Check provider current deposit/debt and charges; do not mistake reserve transfer for a fee already spent. An approved future operator must separately select encrypted account and explicitly authorize broadcast; these commands do not do so.

## Execution after separate authorization

1. Approve the token and simulated dependencies, roles, 3-of-4 attestors, finality policy and exact manifest. Mint 1,000 cMOCK to lender and at least 200 plus accrued interest to borrower (the 800-unit simulated borrower inventory in local fixtures is optional); mint authority controls this test asset. Amounts use 6 decimals.
2. Lender approves vault and deposits `1000000000`; borrower and lender register identical EIP-712 v3 terms with independent nonces. Both terms and derived lot ID must match the Unichain lock and attestation. Use [M2 signing vector](M2_SIGNING_VECTOR.md).
3. Lender calls vault `setCommitment(bytes32,uint256)` for the agreement with `300000000` after registration. Approved binder calls `bind(bytes32,address,uint256)` for the agreement, borrower calls `lock(bytes32)` with exactly 0.001 test ETH. Record receipt, block hash, transaction hash and log index; this ETH has no release. Attestors independently check the approved finality rule and sign the exact verifier domain and evidence in [attestation spec](COLLATERAL_ATTESTATION.md); submit 3 unique valid signatures via `acceptLock`. Callback authentication is not finality verification.
4. Call manager `activate(bytes32)` and verify the 300e6 reservation. Oracle operator calls `update(uint256)` with the approved simulated price (1,000,000e6 per ETH makes 0.001 ETH equal 1,000e6). Set the simulated market position initially healthy, then set the approved distressed position of 800e6 debt and 840e6 collateral; confirm the actual market `isDistressed` result and signed thresholds, or stop.
5. Call `RiskSignalRegistry.signal(bytes32)`. Save source receipt, block hash and log index. Watch Lasna `FinancialSignalObserved` and `FinancialCallbackRequested` and destination proxy receipt; require the receiver's `Disposition` Executed, the manager's `DrawExecuted` in that destination transaction and matching operation ID. Do **not** call manager execution directly in this demonstration. Source signal or request alone is not delivery. Record block timestamps and independent observation times; do not conflate timestamp deltas with measured wall-clock latency.
6. Check market debt 800e6 -> 600e6, manager principal 200e6, lender free/reserved 700e6/300e6 -> 800e6/0, lifetime principal 200e6 and locked collateral. Borrower approves manager and calls `repay(bytes32,uint256,uint256)` with principal plus actual `debtPreview` interest; check receipt, `DebtRepaid`, lender balances, fractional carry and no new lifetime capacity. Avoid assuming zero interest. Capture all receipts and reads.
7. Failed temporary callback: verify no executed disposition and unchanged balances, correct dependency, then use bounded operator `retry(triggerId)` after cooldown if request exists; if first Reactive request reverted, use `resignal` only as defined in [callback runbook](FINANCIAL_CALLBACK_RUNBOOK.md). Preserve every failure receipt and reconcile before retry. Skips and duplicates are terminal dispositions, not proof of a successful draw.
