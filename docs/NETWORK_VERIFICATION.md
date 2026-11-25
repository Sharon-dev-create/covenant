# Network and integration verification

Evidence collected 2026-11-24, read-only. Code presence proves existence, while delivery, current interface behavior, proxy implementation and signer authorization require additional checks. Captured block heights are examples of the observed state and can be reproduced against an archival RPC.

| Item | Official reference and on-chain observation | Implication |
|---|---|---|
| Lasna Omni | 5318007 (`0x512577`), lREACT, `https://lasna-rpc.rnk.dev/`. System `0x8888888888888888888888888888888888888888`: 239 runtime bytes at `0x8b9c89`. [Lasna](https://dev.reactive.network/reactive-mainnet) | Chain and system address confirmed. |
| Unichain Sepolia | 1301 (`0x515`), `https://sepolia.unichain.org`. Listed origin and destination. Proxy `0x775c9B990ADe401060B78D0e98684eEf8d2466C1`: 218 bytes at `0x4180a23`. Observed safe `0x41808f6` and finalized `0x41802a2`. [Unichain](https://developers.uniswap.org/docs/unichain/technical-information/network-information), [Reactive routes](https://dev.reactive.network/origins-and-destinations) | Support documented; verify actual bidirectional delivery and proof latency. |
| Base Sepolia | 84532 (`0x14a34`). Listed origin and destination. Proxy `0x476F44b11F5C942c58f4c8E3d0300E5710743585`: 218 bytes at `0x3c271a1` and `0x3c271a2`. [Reactive routes](https://dev.reactive.network/origins-and-destinations) | Chain/proxy present. Base-to-Base callback through Lasna needs a live smoke test. |
| Circle Base Sepolia USDC | `0x036CbD53842c5426634e7929541eC2318f3dCF7e`: 1,798 bytes, `decimals()` returns decimal 6 at the same two Base blocks. [Circle address list](https://developers.circle.com/stablecoins/usdc-contract-addresses) | Canonical test token for demo inventory. |
| Aave V3 Base Sepolia | `0x8bAB6d1b75f19e9eD9fCe8b9BD338844fF79aE27`: 1,853 bytes at both Base blocks. `getReservesList()` returned six reserves below. [Aave address book](https://github.com/aave-dao/aave-address-book/blob/main/src/AaveV3BaseSepolia.sol) | Circle USDC absent from listed reserves at observed heights. Aave market uses a distinct six-decimal test USDC. |
| Omni API | `subscribe`, `unsubscribe`, system-only `react`, typed V1.0 callback, destination proxy + injected RC identity. [Docs](https://dev.reactive.network/reactive-contracts), [source](https://github.com/Reactive-Network/reactive-lib-omni) | Documented interface. Pin library and validate it against funded live behavior. |
| Finality, retries, billing | Omni documents its own consensus finality, REACT reaction reserves, ETH destination billing, callback result lookup and observable failure. [Consensus](https://dev.reactive.network/), [Economy](https://dev.reactive.network/economy), [Debugging](https://dev.reactive.network/debugging) | Source reorg policy and automatic replay guarantees remain unverified. Require application proof/guards and retries. |
| ETH valuation | Unichain custody is native ETH. Candidate approaches are verified Base-local reference feeds, Unichain feed with finality-proven observations, or authenticated signed pricing with explicit signer trust. Uniswap V3 infrastructure is documented, but pool depth/cardinality and manipulation cost are unverified and no TWAP chosen. [Chainlink](https://docs.chain.link/data-feeds/price-feeds/addresses), [Uniswap V3](https://developers.uniswap.org/docs/protocols/v3/deployments/v3-unichain-deployments) | No fresh official feed pair verified for this testnet design. Deterministic oracle for demo. |
| Settlement | Circle lists both testnets as CCTP supported, domains Unichain 10 and Base 6. [Circle CCTP domains](https://developers.circle.com/cctp/concepts/supported-chains-and-domains) | Route documentation covers USDC. ETH sale, slippage, bridge receipts and attribution remain unverified. |

Aave reserve list, in returned order:

```text
0xba50cd2a20f6da35d788639e581bca8d0b5d4d5f
0x0a215d8ba66387dca84b284d18c3b4ec3de6e54a
0x54114591963cf60ef3aa63befd6ec263d98145a4
0x4200000000000000000000000000000000000006
0xd171b9694f7a2597ed006d41f7509aad4b485c4b
0x810d46f9a9027e28f9b01f75e2bdde839da61115
```

Aave source exposes supply, borrow, health-factor reads, and `repay(asset, amount, rateMode, onBehalfOf)`. A third-party payer can repay a valid position with the correct reserve token and finite amount and allowance. Opening requires borrower-controlled collateral/borrowing or legitimate delegation, reserve flags, liquidity and a usable oracle. M0 verified pool existence and the reserve list. Actual supply/borrow availability, acquisition of its test token, health changes and third-party repayments were not exercised. Do a pinned fork open-and-repay trial and trace events before claiming integration. Supporting it with Circle USDC would additionally require verified conversion, rates, liquidity, and exact-cost accounting, or changing the signed facility asset. No qualifying direct Circle-USDC lending route was verified. [Aave pool interface](https://github.com/aave-dao/aave-v3-origin/blob/main/src/contracts/interfaces/IPool.sol)

## Read-only RPC command record

- `command -v forge cast python3` found `/usr/bin/python3` only. `curl` JSON-RPC to `https://sepolia.base.org` initially returned DNS failure in the sandbox. Approved Python urllib JSON-RPC to the same Base endpoint returned HTTP 403. The same parallel Python run verified Unichain and Lasna above.
- Approved Python urllib JSON-RPC to `https://base-sepolia.gateway.tenderly.co` and `https://base-sepolia-rpc.publicnode.com` returned the same code sizes, decimals and Aave reserve list at their respective pinned blocks above. `https://base-sepolia.drpc.org` returned Base chain ID, Circle decimals, and proxy/USDC code sizes, then HTTP 408 before completing Aave verification.
- Requests used `eth_chainId []`, `eth_blockNumber []`, `eth_getCode [address, block]`, and on Unichain `eth_getBlockByNumber [tag, false]` with tags safe and finalized. Base used `eth_call [{to, data}, block]` with `0x313ce567` for Circle decimals and `0xd1946dbc` for Aave reserve list. Read-only checks did not exercise the destinations or spend funds.

Local Python validation passed for all 12 requested documents, relative links, reserve address formats, scaffold paths and demo arithmetic. `forge config` exited 127 because Forge was unavailable in PATH. No Solidity build or tests were run.

## M1-B Omni RPC evidence

Retrieved 2026-11-24 from public RPCs with read-only calls. The preflight pinned code, implementation slot and provider fee configuration reads to the indicated block. Gas-price quotes came from `eth_gasPrice` during the preflight.

| Network | Public RPC | Chain ID | Provider | Pinned block | Gas quote, wei | Coefficient / 1000 | Extra gas | Max payment gas |
|---|---|---:|---|---:|---:|---:|---:|---:|
| Unichain Sepolia | `https://sepolia.unichain.org` | 1301 | `0x775c9B990ADe401060B78D0e98684eEf8d2466C1` | 68688575 | 1,500,000 | 1100 | 80,000 | 50,000 |
| Base Sepolia | `https://base-sepolia-rpc.publicnode.com` | 84532 | `0x476F44b11F5C942c58f4c8E3d0300E5710743585` | 63095679 | 6,000,000 | 1100 | 80,000 | 50,000 |
| Lasna | `https://lasna-rpc.rnk.dev/` | 5318007 | `0x8888888888888888888888888888888888888888` | 9153587 | 100,000,000,000 | 1000 | 100,000 | 50,000 |

| Network | Provider runtime Keccak-256 | EIP-1967 implementation | Implementation runtime Keccak-256 |
|---|---|---|---|
| Unichain Sepolia | `0xe9180319ff981b2d5933544a0ae074e451a6e82a7e1da45c1452539e15338f52` | `0xd00a7f9034337d900e68b20c0da45c3a4f1bf784` | `0x58346a43df5dfbbb297192e5cebf1617cdef9eade8463ae8896d481819649858` |
| Base Sepolia | `0xe9180319ff981b2d5933544a0ae074e451a6e82a7e1da45c1452539e15338f52` | `0x49e4ac6954e39c006b0a31955a26a9655c7ce059` | `0x58346a43df5dfbbb297192e5cebf1617cdef9eade8463ae8896d481819649858` |
| Lasna | `0xcd91126ed666997bcf1522fd3f502aea129c440b353b8a8f3aa73636938010ad` | `0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb` | `0x6732df14f3b0b592f99d2aea73414a1905bbb22f4506d814ceabcc374dff0722` |

Separate finalized-tag reads reported Unichain block `0x41813cd` with hash `0xece14241124313ef1fb9bea1954c85eb8353c6556378adffc1a6e3dbdff901e8`, Base block `0x3c2ab30` with hash `0x9108a3ad69e5212939b7af3d8f50dacf6e736f288d8b455ba0f708f41eaf281e`, and Lasna block `0x8babd5` with hash `0xfc511377e9eaf2b980e1c3adf8a97f6d60e35e01901c81f9d4436c4517ab9037`. These are observations from each RPC. They provide no evidence about which source confirmations Omni waits for before observing events. No user signer addresses were available for balance reads.

The initial sandbox request failed DNS and the first escalated batch had timeouts. Parallel read-only retries and `bash script/transport.sh preflight` succeeded on all three networks. Chain and provider addresses match the routing table. Code and fee reads do not verify a Covenant subscription, injected sender, callback, delivery SLA, or automatic redelivery. All three live routes remain pending. [Reactive routing table](https://dev.reactive.network/origins-and-destinations) · [Fee getters and limits](https://dev.reactive.network/economy) · [Live verification procedure](TRANSPORT_VERIFICATION.md)

### 2026-11-24 recheck before remediation

The read-only preflight was run again with the public RPCs. All chain IDs, provider addresses, runtime hashes, implementation hashes and fee parameters were unchanged; only the observed heights moved.

| Network | Rechecked block | Gas quote, wei | Coefficient / 1000 | Extra gas | Max payment gas |
|---|---:|---:|---:|---:|---:|
| Unichain Sepolia | 68,705,984 | 1,500,000 | 1100 | 80,000 | 50,000 |
| Base Sepolia | 63,182,850 | 6,000,000 | 1100 | 80,000 | 50,000 |
| Lasna | 9,169,813 | 100,000,000,000 | 1000 | 100,000 | 50,000 |

Official documentation was retrieved on 2026-11-24 from the pages listed in [Reactive integration](REACTIVE_INTEGRATION.md). The site has no printed version identifier; the retrieval date and the pinned library commit `3ade0dcf1d27e67e5783ef807e73a1b9e0c0cce8` are the version record. No signer account was available, so no balance reads were performed. These reads still do not prove delivery, finality depth, retry behavior or live authentication.
