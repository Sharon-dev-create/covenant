# M1-B Stage 4: proposed three-route smoke tests

**Preparation only.** Do not send the transactions without separate Stage 4 authorization. These test transport probes only. A callback request is not delivery, and authenticated delivery does not prove source-chain finality. The accepted duplicate route C reserve deposit and the already-configured route C transaction are recorded in the Stage 3 manifest.

## Preconditions and funding proposal

Recheck the three exact active subscriptions, payer balances/reserves/debt and provider implementation hashes immediately before execution. Each source account is the existing `covenant-testnet` signer. Test one route at a time. Stop on a failed receipt, wrong authentication, unexpected state/nonce or insufficient reserve; do not retry or top up without a separate reviewed plan.

Proposed **source transaction** ceilings for these three calls only: Base 0.00001 ETH aggregate; Unichain 0.000005 ETH; no Lasna signer transaction. Reserve consumption is separate: current Lasna reserve 0.8 lREACT, Base receiver A 0.00002 ETH, Unichain receiver B 0.000005 ETH, Base receiver C 0.00004 ETH (includes accepted additional deposit); all reported debt zero. These are prepaid reserves, not fresh deposits or cash recoverable for other uses.

At the observed 100 gwei Lasna price, coefficient 1 and 100,000 surcharge, 900,000 reaction gas has a planning charge of 0.1 lREACT. A 200 gwei assumption gives 0.2 per reaction; three would consume 0.6, leaving 0.2. This is a bound only under those stated fee and gas assumptions, not a live price guarantee. For a 300,000 callback budget, current coefficient 1.1 and 80,000 surcharge with 2x observed destination gas prices gives planning charges up to 0.000005016 ETH on Base and 0.000001254 ETH on Unichain. Before every source event, ensure reserve covers the next expected reaction and callback plus contingency; re-estimate if provider parameters or prices change. Failed processing can be charged. No retries, failure injection or replenishment are included in this initial smoke-test authorization proposal.

Current independent unsigned `eth_estimateGas` calls gave 72,398 gas each for A and B, 72,410 for C. With 130,000 gas-limit planning and max fee 4,000,000 wei on Unichain or 15,000,000 wei on Base, execution is at most 0.00000052 ETH for A and 0.00000195 ETH each for B/C. Earlier synthetic data-fee estimates at slightly smaller gas limits were about 0.00000000704 ETH A and 0.00000000842 ETH each B/C; refresh against exact unsigned bytes and nonce at execution. Sampled operator fees were zero. Caps do not hard-cap rollup L1 data fees; stop if refreshed total exceeds the proposed ceiling.

## Prepared source calls, only after separate authorization

```bash
export PATH="$HOME/.foundry/bin:$PATH"
export BASE_RPC=https://base-sepolia-rpc.publicnode.com
export UNI_RPC=https://unichain-sepolia-rpc.publicnode.com
export ETH_PRIORITY_GAS_PRICE=1000000
A=0xf95b88A5866b693Fc7a275128759810d77E7120d
B=0xf95b88A5866b693Fc7a275128759810d77E7120d
C=0x4DbA40986CFeE57527B14708dAbe44acc4ED05cb
KA=0xa6a0d3a618ef77ad31c2a968b3d0bbd7a1d4c35987fcf8c8f118f92743fba3a6
KB=0x3a36abd527eba4ef80aafbdcf2ae5531d649c12753067ff02fa4accc742bead4
KC=0x360d404815416a259cd6f3d4954e039cbe68a81b9d6d400f37e2d1f720425273
PA=0xf7e1c93465192ae2946aa568d6d000da1d03857f708eb107620d22062f938f12
PB=0x0e51da1144cc02b7e56739245e8fd9fbeaacd60068937c7cc5bf6ca1b35a9d37
PC=0xbe7ae50d3585fbe9b06f2a0c9491d02c6bc86bbcdc19b2eddce36dcff2bfc20e
```

Before each call, check `operations(key)` is zero, the emitter sequence, receiver count and receiver reserve/debt. Recheck fee estimates, block and nonce; the initial C estimate assumed Base nonce 8 after B's nonce 7.

```bash
cast send "$A" 'emitProbe(bytes32,bytes32)' "$KA" "$PA" --account covenant-testnet --rpc-url "$UNI_RPC" --gas-limit 130000 --gas-price 4000000
cast send "$B" 'emitProbe(bytes32,bytes32)' "$KB" "$PB" --account covenant-testnet --rpc-url "$BASE_RPC" --gas-limit 130000 --gas-price 15000000
cast send "$C" 'emitProbe(bytes32,bytes32)' "$KC" "$PC" --account covenant-testnet --rpc-url "$BASE_RPC" --gas-limit 130000 --gas-price 15000000
```

Execute one call, reconcile all evidence, then move to the next. Record the receipt, gas and rollup data/operator fee; source chain, block/hash, transaction and log index, operation ID, route, sequence, payload hash and source timestamp; Lasna observation receipt and callback request; destination transaction receipt, proxy caller and injected Reactive sender, receiver `ProbeReceived`, and before/after `received(sequence)` and `receivedCount()`. Require count to increment once and `received(sequence)` to equal the operation ID. Record block timestamps, observer wall-clock timestamps, clock skew and timeouts; an empty callback result is pending, never success. Query source finalized state separately. See [transport verification](TRANSPORT_VERIFICATION.md) for the exact callback-result and read commands.
