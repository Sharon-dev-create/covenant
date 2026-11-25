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
