# M1-B Stage 5 — pending failure, recovery and replay verification

**Read-only preflight completed; separate broadcast authorization is required. Recheck live conditions before every transaction.** No Stage 5 transaction has been executed. Stage 4 established one authenticated delivery on each route; it did not establish finality, failure recovery or replay behavior. The accepted duplicate Route C reserve deposit and both transaction records remain in `deployments/transport.stage3.verified.json`.

The 2026-11-27 Stage 4 final snapshot recorded signer balances: Base 0.029820619513304568 ETH, Unichain 0.009934953020345562 ETH, Lasna 3.761257462591 lREACT; latest/pending nonces 9/9, 4/4, 5/5 respectively. Provider reserves were Lasna 0.7253918 lREACT, Base A 0.0000191081486 ETH, Unichain B 0.00000477703715 ETH, Base C 0.0000391081486 ETH, with zero debts. These are **historical**, not fresh balances. The Stage 3 deposit incident was accepted, not retrospectively authorized. No recovery of that deposit is proposed.

## Supported mechanism and test matrix

The verified source pins Route C to Base emitter `0x4DbA40986CFeE57527B14708dAbe44acc4ED05cb` and Base receiver `0xc50F6471B3a46C9F235BE153bd0Ffc81ae679Aa9`. The receiver operator alone can set `failSequence`; a matching otherwise valid authenticated callback reverts `ProbeFailure`, leaving receipt mapping and counter unchanged. The Reactive operator alone can `retry(id)` on an active route after its stored 60-second cooldown; maximum three total requests. It reconstructs the original payload from stored fields. A retry is an application re-request, not proof of protocol redelivery. Provider automatic retry behavior and overlap have not been established: inspect callback records and do not re-request while delivery is pending or ambiguous.

| Check | Method | Present evidence |
|---|---|---|
| Controlled callback failure | Route C next sequence, provider failure event/trace and unchanged receiver | Pending live |
| Recover same operation | Clear failure, retry once after cooldown, authenticate callback and check exact operation/payload | Pending live |
| Destination duplicate | After success, third request for same ID; verify duplicate revert via proxy event/trace and unchanged state | Pending live |
| Reused source key | `eth_call` for same key, expect `DuplicateOperation` | Pending RPC simulation |
| Duplicate Reactive observation | Identical observation returns without another request; conflicting ID reverts | Local `testDuplicateSourceRequestReactionAndDelivery`, pending live |
| Wrong proxy/injected sender, route, source, payload | Local `testUnauthorizedDirectCallWrongProxyAndWrongInjectedSender`, `testRejectsWrongSourceRoutePayloadAndMalformedLog`, `testReceiverValidatesRouteSourceAndPayload` | Local tests only, not live |

A non-proxy direct call can only establish the first authorization check. Wrong injected sender and later validations cannot be isolated by an ordinary EOA call. Do not impersonate a proxy or Reactive sender on a public network. A callback request or five-minute timeout does not prove delivery or failure; an outer successful proxy transaction may wrap a failed inner callback. Obtain provider `CallbackFailure`/error and inner call trace or equivalent conclusive failure evidence, plus unchanged receiver state.

## Mandatory fresh preflight — read-only

Use the existing public signer and endpoints. Do not source `.env` or expose credentials. Run on the operator host. Verify all contract identities with chain ID plus address, compare runtime hashes and immutables against `deployments/transport.stage1.verified.json` and `deployments/transport.stage2.verified.json`, and provider implementation addresses and hashes with the Stage 4 records; investigate changes rather than assuming an identical hash validates all state.

```bash
export PATH="$HOME/.foundry/bin:$PATH"
export BASE_RPC=https://base-sepolia-rpc.publicnode.com
export UNI_RPC=https://unichain-sepolia-rpc.publicnode.com
export LASNA_RPC=https://lasna-rpc.rnk.dev/
S=0xb108b6F40E5Aefdc8475b053BE4248C53eF07B0F
R=0xf95b88A5866b693Fc7a275128759810d77E7120d
EC=0x4DbA40986CFeE57527B14708dAbe44acc4ED05cb
RA=0xe77a43FeE185E9760A1A7818619C1b05fD678630
RB=0x4DbA40986CFeE57527B14708dAbe44acc4ED05cb
RC=0xc50F6471B3a46C9F235BE153bd0Ffc81ae679Aa9
BP=0x476F44b11F5C942c58f4c8E3d0300E5710743585
UP=0x775c9B990ADe401060B78D0e98684eEf8d2466C1
SYS=0x8888888888888888888888888888888888888888
SLOT=0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
for rpc in "$BASE_RPC" "$UNI_RPC" "$LASNA_RPC"; do
  cast chain-id --rpc-url "$rpc"
  cast block-number --rpc-url "$rpc"
  cast balance "$S" --rpc-url "$rpc"
  cast nonce "$S" --block latest --rpc-url "$rpc"
  cast nonce "$S" --block pending --rpc-url "$rpc"
  cast gas-price --rpc-url "$rpc"
done
for pair in "$BASE_RPC $BP" "$UNI_RPC $UP" "$LASNA_RPC $SYS"; do
  read -r rpc provider <<< "$pair"
  cast code "$provider" --rpc-url "$rpc" | cast keccak
  cast storage "$provider" "$SLOT" --rpc-url "$rpc"
  for getter in '_gasPriceCoeffPer1000()(uint256)' '_extraGas()(uint256)' '_maxChargeGas()(uint256)'; do cast call "$provider" "$getter" --rpc-url "$rpc"; done
done
```

Resolve the implementation address from the low 20 bytes of each slot and run `cast code IMPLEMENTATION --rpc-url RPC | cast keccak`; compare deployment/provider bindings to recorded evidence. Read payer reserves and debts:

```bash
for item in "$BASE_RPC $BP $RA" "$BASE_RPC $BP $RC" "$UNI_RPC $UP $RB" "$LASNA_RPC $SYS $R"; do
  read -r rpc provider payer <<< "$item"
  cast call "$provider" 'reserves(address)(uint256)' "$payer" --rpc-url "$rpc"
  cast call "$provider" 'debt(address)(uint256)' "$payer" --rpc-url "$rpc"
  cast call "$payer" '_SERVICE_PROVIDER()(address)' --rpc-url "$rpc"
done
for i in 1 2 3; do cast call "$R" 'routes(uint8)(address,address,uint64,bool)' "$i" --rpc-url "$LASNA_RPC"; done
cast rpc rnk_getFilters --rpc-url "$LASNA_RPC" > /tmp/covenant-stage5-filters.json
```

Inspect the full filter registry for **exactly** three active entries for R (IDs `0x07ba41e0ab10c747cab2ea4b571c8f18`, `0x3ff97ab0b1cf8044f5cf210cbd1dca85`, `0x004946d7f0515d4fda30bd53d0f4c216`): expected source chain/emitter and `ProbeRequested` topic0, route indexed topic2 1/2/3, wildcard topics1/3. Do not infer uniqueness from individual lookups. Check emitter `operator`, `route`, `sourceChain`, `destinationChain`, `sequence`, runtime hash; receiver `operator`, `callbackProxy`, `expectedReactive`, `sourceEmitter`, `sourceChain`, `destinationChain`, `route`, `_SERVICE_PROVIDER`, `receivedCount`, `highestSequence`, `failSequence`, `received(1)` and `received(next)`; Reactive `operator`, `_SERVICE_PROVIDER`, runtime hash, `observed(route,1)`, `observed(route,next)`, `requestStatus(existing ID)`, 300000 callback gas and active tuples. Use `cast call ADDRESS 'GETTER()(RETURN_TYPE)' --rpc-url RPC` and `cast code ADDRESS --rpc-url RPC | cast keccak`; see the Stage 1–4 manifests for exact expected values and operation IDs. Check receipt finality separately. Stop on nonzero debt, changed binding, unknown pending nonce, existing operation, mismatched state or insufficient funds.

Simulate the first action from the real public operator without signing:

```bash
cast estimate "$RC" 'setFailureSequence(uint64)' 2 --from "$S" --rpc-url "$BASE_RPC"
cast call "$RC" 'setFailureSequence(uint64)' 2 --from "$S" --rpc-url "$BASE_RPC"
```

Use sequence 2 only if the fresh C emitter sequence and receiver count both still equal 1, `failSequence` is 0, and `received(2)`/`observed(3,2)` are zero. Otherwise stop and reconcile. For the next transaction, estimate with its actual state and calldata. Retry simulation cannot be meaningful until the actual operation exists and cooldown passes; clearing simulation against failSequence=0 does not measure the eventual nonzero-to-zero write. Simulate source duplicate only after source receipt, using the exact already-used key. Evaluate exact synthetic unsigned calldata using the rollup GasPriceOracle `getL1Fee(bytes)` and `getOperatorFee(uint256)` as applicable; no signed bytes, secrets or keys. Requote immediately before each transaction and stop if the envelope is breached.

## Proposed bounded execution — NOT authorized

Use only after refreshed preflight and explicit approval. Commands use the encrypted `covenant-testnet` account and send **zero value**. Gas prices are maxima for EVM execution, not caps on L1 data or operator fees. Three Base calls below have 120000/130000/120000 gas limits at 15000000 wei (0.00000555 ETH execution maximum in aggregate), plus variable L1 data/operator fees. Two Lasna retries have 300000 gas each at 200000000000 wei (0.12 lREACT execution maximum in aggregate). Proposed aggregate ceilings: Base signer **0.00005 ETH**, Lasna signer **0.15 lREACT**, Unichain signer **0**. Proposed existing-reserve charge allowances: Lasna **0.3 lREACT** and Route C **0.00002 ETH**; these are risk buffers, not deposits or measured costs. Do not count reserve charges twice as signer spending. Reactive and callback charges are provider assessed and these amounts are not on-chain fee caps; stop when fresh fee calculations, projected charges or receipts approach any allowance. Provider charges, especially failed callback and replay charges, are unmeasured. Preserve funding for financial deployment. Optional samples and funding are outside these core ceilings and need a separately reconciled budget.

Historical Stage 4 C source cost 0.000000441822978512 ETH including L1 fee; initial reaction charged 0.0248723 lREACT reserve; callback charged 0.0000008918514 ETH reserve. The average of the three reactions was 0.0248694 lREACT. These are empirical observations, not forecasts or proof that failure/retry has the same cost. A prior per-callback reserve planning bound of 0.000005016 ETH at 300000 gas would total 0.000015048 ETH for failure, recovery and replay if unchanged; refresh the provider formula and fee inputs. Zero top-up is proposed; if reserves are insufficient, stop and request a separate funding decision.

Set unique values and capture state immediately before each action:

```bash
SEQ=2
KEY=$(cast keccak 'covenant-m1b-stage5-route-c-controlled-failure-1')
PAYLOAD=$(cast keccak 'covenant-m1b-stage5-route-c-payload-1')
cast call "$EC" 'operations(bytes32)(bytes32)' "$KEY" --rpc-url "$BASE_RPC"
cast call "$RC" 'received(uint64)(bytes32)' "$SEQ" --rpc-url "$BASE_RPC"
cast call "$R" 'observed(uint8,uint64)(bytes32)' 3 "$SEQ" --rpc-url "$LASNA_RPC"
```

1. **Base, receiver C:** `cast send "$RC" 'setFailureSequence(uint64)' "$SEQ" --account covenant-testnet --rpc-url "$BASE_RPC" --gas-limit 120000 --gas-price 15000000 --priority-gas-price 1000000`. Verify receipt, signer/chain, `FailureConfigured`, and `failSequence()==SEQ` before continuing.
2. **Base, emitter C:** `cast send "$EC" 'emitProbe(bytes32,bytes32)' "$KEY" "$PAYLOAD" --account covenant-testnet --rpc-url "$BASE_RPC" --gas-limit 130000 --gas-price 15000000 --priority-gas-price 1000000`. Verify receipt and log; set `OP` to its indexed operation ID. Check `operations(KEY)==OP`, sequence and source identity; obtain `ProbeObserved` and attempt-1 `CallbackRequested` on Lasna and provider callback result. Confirm failure using proxy failure event/trace and unchanged C count/`received(SEQ)`. Reconcile reserves, debt, fees and timestamps. If missing or ambiguous, stop, do not retry. Five minutes is only a polling cutoff.
3. **Base, receiver C:** `cast send "$RC" 'setFailureSequence(uint64)' 0 --account covenant-testnet --rpc-url "$BASE_RPC" --gas-limit 120000 --gas-price 15000000 --priority-gas-price 1000000`. Verify receipt and `failSequence()==0`. If failure switch is left enabled after a disruption, pause other C probes and obtain authorization for this documented recovery action.
4. **Lasna, Reactive:** with OP from the receipt, `cast call "$R" 'requestStatus(bytes32)(uint8,uint256)' "$OP" --rpc-url "$LASNA_RPC"`. Confirm attempts=1, current Lasna block timestamp at or after retryAfter, route active, destination still empty, no pending/automatic callback, zero debt and sufficient reserve. Simulate `cast estimate "$R" 'retry(bytes32)' "$OP" --from "$S" --rpc-url "$LASNA_RPC"`. Then `cast send "$R" 'retry(bytes32)' "$OP" --account covenant-testnet --rpc-url "$LASNA_RPC" --gas-limit 300000 --gas-price 200000000000 --priority-gas-price 1000000`. Verify request attempt 2 and provider result; retrieve original payload and compare callback calldata, proxy caller and injected sender via trace. Require successful destination receipt, event, original OP and payload hash, count +1 and `received(SEQ)==OP`.
5. **Lasna, Reactive:** after retryAfter and complete confirmation there is no pending callback, simulate the same retry, then issue the identical `cast send` once for request attempt 3. Require a real destination duplicate rejection in provider failure event/trace and unchanged count and receipt. Check all reserves and debts. Do not retry a fourth time. If provider does not deliver a duplicate, mark destination replay live test inconclusive; local tests remain separate.

For every send independently save receipt and all actual execution, L1 data and operator fees, state and nonce before and after. If output is lost, do not resend: reconcile latest/pending nonce, transaction history, receipt, logs, on-chain state and provider results first. Stop if uncertain or any fee/provider binding changes.

## Sampling and completion

Keep the recovered controlled operation separate from ordinary successes. For each route, up to five new fresh unique keys/payloads may be proposed in small serial batches **after separate authorization and refreshed funding assessment**. Stage 4 has one success per route. At 0.0248694 lREACT average, 15 additional initial reactions alone would use about 0.373041 lREACT of existing reserve, excluding failures and drift; Stage 4 bounds were 0.2 lREACT per reaction, so the historical 0.7253918 reserve cannot conservatively guarantee 15. Route B's historical 0.00000477703715 ETH reserve is also insufficient for five calls at the prior 0.000001254 ETH per-attempt bound. Do not automatically top up; stop and decide smaller batches.

For each sample capture source tx/block/hash/timestamp and receipt observation time; Lasna reaction tx/block/timestamp, observation time and request; destination callback tx/block/timestamp, receipt observation time and receiver transition; source execution, L1 and operator charges, Reactive reserve delta, callback reserve delta and debt. Start an independent UTC/monotonic observer before submission, poll e.g. every 5 seconds and record actual intervals, observation times and clock uncertainty. Block timestamps from different chains are not independent elapsed latency. Report median/min/max/count only for comparable samples with actual independent timing; do not fold in Stage 4 samples that lack it. Timeout remains unresolved, not a proven failure.

M1-B closure requires chain-specific receipts, matching origin identity and payload, reaction and callback evidence, authenticated proxy/injected sender, success/failure traces, exact-once state changes, replay distinction, fee/debt reconciliation and honest sample counts. Authentication does not establish source finality or independent consensus proof.

## Read-only preflight update

Public RPC reads independently confirmed the three chain IDs, signer balances and equal latest/pending nonces, all four zero debts and recorded reserves, all three exact active subscriptions, all seven runtime hashes and immutable bindings, and the recorded provider implementation hashes. Each emitter sequence and receiver count is 1; each failure switch is 0; each previous observed operation matches its destination receipt and has one request. Route C sequence 2 is unobserved and unreceived, and the proposed key is unused. See the pending manifest for block numbers and values. The operator terminal output was not attached; these are independent reads.

Signer-specific RPC estimates: set failure 28156 gas, fresh emit 55242 gas. The existing-operation retry cannot be simulated before the new operation exists; resetting from a nonzero value cannot be faithfully simulated against the present zero state. Using synthetic signed-shape transaction bytes and the Base fee oracle, the three L1 fees were 210110350168, 262037862550 and 210110350168 wei; quoted operator fees were zero. The 370000 aggregate gas limit at 15000000 wei plus these illustrative fees is 6232258562886 wei, below the proposed 50000000000000 wei Base ceiling. These are quotes, not hard caps. Recheck fee, bindings, pending nonces, reserves and operation state before each transaction.

Reactive documentation says the relay retries failed destination **submission** every block; it does not establish automatic redelivery after an executed receiver revert. Check relay status and callback records, and after clearing failure reconcile receipt and receiver state before deciding whether a manual retry is safe. If automatic recovery occurs record it separately; it does not demonstrate manual retry.
