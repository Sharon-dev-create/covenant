# M1-B transport verification

M1-B probes exercise Omni routing without custody or financial effects. Local tests use actual emitter logs, a mocked Lasna System and mocked destination proxies that replace the first ABI argument exactly as current Omni docs describe. These tests prove local contract logic only. Live results require separately authorized testnet execution and are still pending.

| Route | Origin | Reaction | Destination | Route ID |
|---|---|---|---|---:|
| A | Unichain Sepolia | Lasna | Base Sepolia | 1 |
| B | Base Sepolia | Lasna | Unichain Sepolia | 2 |
| C | Base Sepolia | Lasna | Base Sepolia | 3 |

`TransportEmitter` uses an operator, a unique client request key and a monotonic sequence within each emitter. Its operation ID commits to route, source chain and emitter, destination chain, sequence, source block and timestamp, and the fixed-size payload and its ABI hash. The event includes those fields except the source chain and emitter, which come from the log envelope. The receipt supplies block hash, transaction hash and log index. The payload is a 32-byte probe value.

`CovenantTransportReactive` installs one exact subscription per route: `(sourceChain, emitter, ProbeRequested_topic0, REACTIVE_IGNORE, route, REACTIVE_IGNORE)`. The route is **topic2**: topic1 carries the operation ID. `react()` validates event shape, topic widths, source identity, destination and operation digest before requesting a callback. It remembers each sequence and operation. Repeated observations of an identical operation request no further callback; a conflicting operation for the same sequence is rejected. Each route can be stopped permanently and cannot be reconfigured after stopping. A synchronous System revert rolls back the observation and initial attempt. Operator re-requests are separate from new source observations.

`TransportReceiver` pins the destination proxy and expected Lasna contract. It validates the exact callback shape, route, source, destination and digest. Each route and sequence has one successful receipt. Independent probes may arrive out of order and still be recorded. `highestSequence` is a high-water mark; gaps remain observable in `received(sequence)`. The callback path has no untrusted external calls. `receiveProbe` is non-reentrant by construction: it writes the receipt before emitting, and replay is rejected by `received[sequence]`. The only external-call surface is the payer's low-level transfer to the immutable service provider, which is not part of callback ingress.

Both probe contracts implement the documented payer wire surface locally: `receive()`, provider-only `pay(uint256)`, public `coverDebt()` and `_SERVICE_PROVIDER()`. Funding via `depositTo(address)` is preferred because it clears debt before adding reserves; direct transfers work because `receive()` exists and `coverDebt()` can apply the balance. Any debt blocks execution and failed callbacks are still charged.

## Accounts and cost envelope

Use dedicated encrypted Foundry keystores outside the repository. The Unichain account deploys emitter A and receiver B, emits A probes and controls B failure tests. The Base account deploys emitters B/C and receivers A/C, emits B/C probes and controls A/C failure tests. The Lasna account deploys the reactive contract, installs routes, authorizes re-requests and can stop subscriptions. The destination signers can each fund their respective receivers. One operator may hold all three testnet roles using separate accounts. No signer address was available, so no account balance checks were performed.

Local gas from the 2026-11-24 build: emitter deployment 385,724; receiver deployment 850,179–850,295; reactive deployment 1,334,154; successful `receiveProbe` 51,769; local `react()` 215,892–528,824 including the mock System's storage writes. The initial callback gas limit is 300,000, above the documented 100,000 floor. Observed destination reservations are 80,000 extra gas and 50,000 max payment gas, leaving roughly 170,000 before other proxy overhead. Lasna documents a 900,000 reactive transaction cap. Live System and proxy gas remains to be measured.

Read-only fork simulations on 2026-11-24 used a placeholder public signer and produced these estimates; no transaction was broadcast.

| Simulated deployment | Estimated gas | Estimated native amount |
|---|---:|---:|
| Unichain emitter | 501,144 | 0.000000501144501144 ETH |
| Unichain receiver | 1,104,448 | 0.000001104449104448 ETH |
| Base emitter | 501,182 | 0.000005513002 ETH |
| Base receiver | 1,104,343 | 0.000012147773 ETH |
| Lasna reactive contract | 1,734,103 | 0.346820600001734103 lREACT (Forge labels it ETH) |

These figures exclude subscription transactions, funding transactions, rollup L1 data fees and fee drift. The fee formula is `max(tx.gasprice, block.basefee) × coefficient / 1000 × (usedGas + extraGas)`. At the observed quotes a planning ceiling is about 0.10 lREACT per Lasna reaction at its cap, about 0.000002508 ETH per Base callback and 0.000000627 ETH per Unichain callback at 300,000 used gas. Plan up to 30 charged reactions or deliveries per budget line, including failures. Start with 3 lREACT prepaid reserves on Lasna and 0.001 ETH prepaid reserves on each receiver, with a planning wallet balance of 5 lREACT, 0.02 Base Sepolia ETH and 0.02 Unichain Sepolia ETH. If sourcing all 5 lREACT through the Base faucet, budget another 0.05 Base Sepolia ETH plus transaction fees at the documented 1 ETH → 100 lREACT rate. Requote fees, check reserves and debt, and confirm funding amounts before broadcast. Fund only via `depositTo(address)`. [Reactive economy](https://dev.reactive.network/economy) · [Lasna faucet](https://dev.reactive.network/reactive-mainnet) · [Base faucets](https://docs.base.org/get-started/get-funds) · [Unichain faucets](https://developers.uniswap.org/docs/unichain/tools/faucets)

## Deployment sequence

Copy `deployments/transport.testnet.example.json` to `deployments/transport.testnet.local.json` and populate public RPC URLs, signer addresses and encrypted keystore references in a private environment based on `.env.example`. Never put private keys, keystore passwords or credential-bearing URLs in manifests, logs or version control. Set either `<NETWORK>_KEYSTORE_ACCOUNT` or `<NETWORK>_KEYSTORE_PATH`; the driver derives the address from the keystore and refuses to broadcast if it does not match the configured public signer. Foundry prompts for the keystore password when signing is needed.

Before authorization, run the read-only preflight and simulations. The driver has a separate explicit `broadcast` mode for the same deployment steps after approval. Do each step in order, collect the receipt and runtime code hash, and substitute the resulting addresses for `RC`, `EA`, `EB`, `EC`, `RA`, `RB` and `RCV`. The destination receiver for route C is `RCV`.

```bash
for network in unichain base lasna; do
  bash script/transport.sh preflight "$network"
done

bash script/transport.sh simulate lasna 'deployReactive()'
bash script/transport.sh simulate unichain 'deployEmitter(uint8)' 1
bash script/transport.sh simulate base 'deployEmitter(uint8)' 2
bash script/transport.sh simulate base 'deployEmitter(uint8)' 3
bash script/transport.sh simulate base 'deployReceiver(uint8,address,address)' 1 "$EA" "$RC"
bash script/transport.sh simulate unichain 'deployReceiver(uint8,address,address)' 2 "$EB" "$RC"
bash script/transport.sh simulate base 'deployReceiver(uint8,address,address)' 3 "$EC" "$RC"

bash script/transport.sh simulate lasna 'fund(uint256,address,uint256)' 5318007 "$RC" 3000000000000000000
bash script/transport.sh simulate base 'fund(uint256,address,uint256)' 84532 "$RA" 1000000000000000
bash script/transport.sh simulate unichain 'fund(uint256,address,uint256)' 1301 "$RB" 1000000000000000
bash script/transport.sh simulate base 'fund(uint256,address,uint256)' 84532 "$RCV" 1000000000000000

bash script/transport.sh simulate lasna 'configure(address,uint8,address,address,uint64)' "$RC" 1 "$EA" "$RA" 300000
bash script/transport.sh simulate lasna 'configure(address,uint8,address,address,uint64)' "$RC" 2 "$EB" "$RB" 300000
bash script/transport.sh simulate lasna 'configure(address,uint8,address,address,uint64)' "$RC" 3 "$EC" "$RCV" 300000
```

Check the expected signer, chain, code and implementation hash before each approved broadcast. Funding and registration require actual deployed code. Before configuring a route, read the emitter's `route()`, `sourceChain()` and `destinationChain()`, plus the receiver's `sourceEmitter`, `expectedReactive`, `callbackProxy`, `route`, `sourceChain` and `destinationChain`. After registration, use `cast rpc rnk_getFilters --rpc-url "$REACTIVE_LASNA_RPC"` and look up each exact filter and active subscriber; the expected filter is chain/emitter/signature/IGNORE/route/IGNORE. Also read `routes(uint8)` on the reactive contract, plus `reserves(address)(uint256)` and `debt(address)(uint256)` on each provider. Confirm `_SERVICE_PROVIDER()` on each probe. Do not begin probes with debt or unbudgeted fees. [Omni registry RPC](https://dev.reactive.network/rnk-rpc-methods)

## Live route procedure

For each route, map `EMITTER`, `RECEIVER`, `SOURCE_RPC`, `DEST_RPC` and `SOURCE_ACCOUNT` to the deployed records. Run serially for initial verification. Record the before state using `sequence()(uint64)` on the emitter and `receivedCount()(uint64)`, `highestSequence()(uint64)` and `received(uint64)(bytes32)` on the receiver. Use a fresh client key such as `cast keccak "covenant-m1b:<route>:<trial>"` for each new emission, and `cast keccak "covenant-m1b:payload:<route>:<trial>"` for the fixed-size test value.

1. With deployment and probing authorized, submit `cast send "$EMITTER" 'emitProbe(bytes32,bytes32)' "$KEY" "$PAYLOAD" --account "$SOURCE_ACCOUNT" --rpc-url "$SOURCE_RPC"`. Record the origin transaction hash, event log, operation ID, sequence, source block number and hash, log index and block timestamp. Capture the observation time and query the finalized tag separately.
2. Find the reactive transaction by the `ProbeObserved` event indexed by operation ID. Confirm its origin block hash, transaction hash and log index against the origin receipt. Save the Lasna receipt, its block details, `CallbackRequested`, and the System's `CallbackRequest` including destination chain, sender, recipient and configuration.
3. Query `cast call "$SYSTEM" 'getCallbacks(uint256)((uint256,address,uint256,uint256,uint256,bytes)[])' "$LASNA_TX" --rpc-url "$REACTIVE_LASNA_RPC"` using the 32-byte transaction hash as the uint256. Use the destination transaction from the System result or locate the receiver's indexed `ProbeReceived` event. Save the destination receipt status, logs, block and timestamp. Confirm the callback proxy in the call trace if the RPC supports traces and the injected Reactive identity in `ProbeReceived`.
4. Match `received(sequence)` to the operation ID, check the count advanced exactly once, and check the event hash against the origin. A callback request, an empty result array or a successful outer receipt without matching receiver state does not establish delivery.
5. Record source-to-Lasna, Lasna-to-destination and end-to-end block timestamp deltas and independent wall-clock observations. Record cross-chain clock skew if observed. After one successful trial per route, collect five additional samples per route and report sample count, failures, median, minimum and maximum. Record separate delays until source and destination finalized tags include the corresponding canonical blocks. A five-minute observation window is a test cutoff, not a network SLA. Record timeouts explicitly.
6. For controlled failure choose route A and read its next sequence before emission. On Base, set `setFailureSequence(uint64)` to that sequence with the Base operator. Emit a fresh probe and record the failure, any `CallbackFailure`, System error bytes and unchanged receiver state. Clear the switch with sequence zero. After `requestStatus(bytes32)(uint8,uint256)` permits and the receiver still has no receipt, use the Lasna operator to call `retry(bytes32)` with the same ID. Record attempt 2 and its destination receipt. This is an application-level re-request, not documented protocol redelivery, and it never infers destination state.
7. With a separately budgeted replay attempt, wait for the second cooldown and re-request that same operation. Confirm duplicate rejection and unchanged receiver count. Confirm origin client-key duplication by simulating the same source call. Re-requests have a maximum of three total submissions with 60 seconds between them. If an initial reaction was never observed or rolled back, the application has no stored request to re-request. Investigate the provider, then emit a fresh independent probe if needed and record the original as undelivered.

Trial records must include status, operation ID, route, sequence, all transaction hashes and receipts, source log and block identifiers, Lasna callback request and result, destination before/after state, authenticated sender, reserve deltas, both latency measures and links to archived evidence. For a timed-out route, preserve pending evidence and investigate instead of marking it successful. [Callback diagnostics](https://dev.reactive.network/debugging)

## Stage 4 route A: observed live delivery

On 2026-11-27, the single authorized Unichain→Lasna→Base operation `0xba6121a90bdc1042973da308293dd32d10f50fb2c8dc20e6d93010cfc5e7c679`, sequence 1, succeeded at source transaction `0xa4a07537135d4b69289e1f7f23ca7cb5cbc4d86d22bea02b4f219e42db756175`; Lasna observation and callback request occurred in `0xd984c5b42f92d57cee57019f98dbee70c09769f22e69fa814858099e7d795f4a`; the successful Base callback was `0x2ae6871aca3d3d1d138e961beda2ace66e487b7be383ca8517887657d7d6fc42`. The Base RPC `trace_transaction` shows the verified callback proxy as the immediate receiver caller and the pinned Lasna contract as injected sender. `ProbeReceived` matched the source operation and payload hash; `received(1)` matched the ID and the receiver count changed 0→1. The route's source transaction cost 127651836503 wei, Lasna reserve decreased by 24866500000000000 wei, and receiver A reserve decreased by 891851400000 wei; debts were zero at observation. Reserve deltas are attributed to this operation based on the recorded baseline and observed single operation.

The source, reaction and destination block timestamps give source→reaction −1 s, reaction→destination 2 s, and source→destination 1 s. The negative delta demonstrates cross-chain clock skew; it is not negative real latency. The observer's first completed snapshot was recorded, but exact independent wall-clock delivery latency was not captured. This single successful test establishes observed authentication and one state transition for this operation only; it does not establish source-chain finality or universal reliability. Routes B and C, failure, retry and replay tests remain unverified. Full evidence is in `deployments/transport.stage4.verified.json`.

## Stage 4 route B: observed live delivery

On 2026-11-27, the single authorized Base→Lasna→Unichain operation `0x0c336e1fbb382d0b889630b603bfd3104dff5e314e3528834c388074cee96e0d`, sequence 1, succeeded at source transaction `0x59c0b3fbee0b16895fd124ca6988a75e8f60c228e2665567aada67ac3008132f`; Lasna observation and callback request occurred in `0x27483032311324c3d31cedd2e80271119f023d1f357f157f15478999f9fefdb1`; the successful Unichain callback was `0x77a7a1d332ef250dd40c66d6b2320c30ed4223aea4b1fbc1713f743f59ca23bb`. The Unichain RPC `trace_transaction` shows the pinned callback proxy as the receiver's immediate caller and the expected Reactive address injected in calldata. `ProbeReceived`, payload hash and `received(1)` matched, with receiver count 0→1. The source transaction cost 440168512962 wei, Lasna reserve decreased by 24869400000000000 wei, and receiver B reserve decreased by 222962850000 wei; debts were zero when observed.

Source→reaction, reaction→destination and source→destination block timestamp differences were −1, 3 and 2 seconds respectively. Cross-chain clock skew explains why these are not guaranteed wall-clock latency measurements. The completed observer snapshot was recorded but exact independent delivery observation time was not captured. This is a single-operation transport observation and does not establish independent source finality or universal reliability; route C and failure/retry/replay testing remain pending.

## Stage 4 route C: observed live delivery

On 2026-11-27, the single authorized Base→Lasna→Base operation `0xf6bb1508c83cd0ae0f5e1bebc7b646623f16faba763e15c4fa24e237697a350f`, sequence 1, succeeded at source transaction `0x8b6c5cebef837f76dbab02a678ef86483f6c09a44225562ca3031710cde924f4`; Lasna observation and callback request occurred in `0xe6f465eea22f3c27abc85adb8ba453a08d7a92fdc2e7ba60234ae9d5cb789692`; the successful Base callback was `0x9ec49521e7af77b0561b7aeb604e5ac5f8156d518a6e3621ea43735217c2e26d`. The Base `trace_transaction` shows the pinned callback proxy as immediate caller and the configured Reactive address injected in calldata. `ProbeReceived`, payload hash and `received(1)` matched, with receiver count 0→1. The source transaction cost 441822978512 wei, the Lasna reserve decreased by 24872300000000000 wei, and receiver C's reserve decreased by 891851400000 wei; debts were zero when observed.

Source→reaction, reaction→destination and source→destination block timestamp differences were −1, 2 and 1 seconds respectively. Cross-chain clock skew means these are not guaranteed wall-clock latency measurements. The completed observer snapshot was recorded but exact independent delivery observation time was not captured. This is a single-operation transport observation, not proof of independent source finality or universal reliability. No controlled failure, retry, replay or financial execution has been performed. The accepted duplicate route C reserve deposit remains separately documented in the Stage 3 manifest.


## Stage 5 controlled failure and duplicate source incident

Route C source transaction `0x6933a105356fa475ef8d57ed540e7800465ae30b1b423f6db81ee53856957fa6` (Base nonce 10) created operation `0x1359388bd2e63fbc5d00736913e75024cdf9ac6198d8ff690b426f343b0b85ef`. Reactive transaction `0xe7278733d9449d781b17478b739d9fb34ad8f03b81d885c63328a88353daf98b` observed it. Destination callback `0x4031aa516e058afd3537d5eaf531c44a336bdd9c2a0adab51977f1fb21e18d5e` called through the expected proxy with the expected injected sender; its receiver call reverted `ProbeFailure()` as configured. Receiver count remained 1 and `received(2)` was zero. The operator accepted the controlled failure evidence.

**OPERATIONAL DEVIATION — DUPLICATE SOURCE TRANSACTION ACCEPTED.** Base transaction `0xb85eabf98bdcbb26798221e9c1039c1f3cc4dc6e0bb797460e84ed52546c4f79` (nonce 11) repeated the original calldata and reverted `DuplicateOperation()` with no logs. Known fees were 148032000000 wei execution and 602403465534 wei L1; operator fee was not separately reported. The original successful source incurred 1055621578501 wei in known execution and L1 fees. The request mapping and Reactive observation still identify the original operation, with one request recorded and no additional callback request observed. Root cause of the duplicate submission is unconfirmed. The operator accepted the deviation without retrospectively authorizing it.

Provider `getCallbacks` returned an empty array despite the independently traced destination callback, leaving provider-record and automatic-redelivery eligibility unresolved. No manual retry or recovery is established. See `deployments/transport.stage5.pending.json`.
