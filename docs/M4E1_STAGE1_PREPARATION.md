# M4-E.1 — proposed first financial deployment stage

Financial deployment, ceilings, participant funding, callback gas and provider reserves remain unauthorized. Operator explicitly approved only the listed testnet roles, 3-of-4 policy, incident duties, synthetic scenario and the permanent 0.001 test-ETH lock subject to later funding and transaction authorization. Public role addresses match the earlier inventory; four distinct attestors are one developer-operated trust domain. The prior binder candidate is the deployer, but binder was not explicitly named in this approval. Do not treat it as formally approved. The source-finality runbook is approved subject to exact source/destination evidence and vetted provider/finality semantics; fail closed. Off-chain signer procedures, not the contract, prevent pre-signing.

## Stages and dependencies

1. Proposed Base foundational deployments: `DemoToken(authority)` and `DemoOracle(operator)`. Both have the approved deployer/operator constructor address and no deployed contract dependencies. The Unichain collateral vault is deferred pending explicit binder assignment, despite a measured constructor simulation.
2. Unichain `CollateralVault(binder)` once binder approved; Base market(token, operator), verifier(actual vault, predicted manager, governance, emergency, four attestors), adapter(token, market, predicted manager), then atomic demo factory/nested testnet factory/manager/vault. This reorders the initial proposal because verifier needs the actual vault, and adapter/verifier bind the future manager. Freeze and recheck Base deployer nonce throughout the final prediction window.
3. Base risk registry, Lasna financial Reactive and Base receiver, in dependency order.
4. Configure financial registry/manager/receiver subscription and separately fund the financial provider reserves only after callback gas and costs are explicitly approved.
5. Fund lender and borrower and prepare the live demonstration only after separate authorization; do not count transfers as both transfer and expenditure again.

## Stage 1 proposed expenditure — Base only

Public checks 2026-11-28: Base chain 84532, signer `0xb108b6F40E5Aefdc8475b053BE4248C53eF07B0F`, latest/pending nonce 13/13, 0.029817981153616286 ETH, 6000000 wei gas price. Token predicted at nonce 13 `0xC8013185D548990956B9b0CF4bee55C3BE3DF3e9`, oracle conditionally at nonce 14 `0xeBC6B76b9cA1dA2934D89e43bd72Ef0ba9258680`; both had no code at query time. These are predictions, not deployments. Recompute after each receipt.

| Contract | eth_estimateGas | Script dry-run buffered gas | Synthetic L1 estimate | Operator quote | Execution maximum at 15m wei |
|---|---:|---:|---:|---:|---:|
| DemoToken(D) | 438493 | 564046 | 3939165570096 wei | 0 | 8460690000000 wei |
| DemoOracle(D) | 204630 | 262419 | 2050009044429 wei | 0 | 3936285000000 wei |

Both actual `DeployM4.s.sol` functions ran in non-broadcast mode with candidate signer and 130% gas estimate multiplier; each simulated independently at the **current nonce 13**, so both returned the same simulated CREATE address. The oracle estimate and synthetic L1 quote must be refreshed at its actual later nonce. The oracle fee-oracle quote used synthetic signed-shape public transaction bytes, not a signed transaction. Total illustrative conservative execution+data is 18386149614525 wei (0.000018386149614525 ETH), before fee drift. Proposed **aggregate Stage 1 Base ceiling 0.00005 ETH** includes contingency; Unichain and Lasna Stage 1 expenditure zero. At that ceiling the Base wallet would retain at least 0.029767981153616286 ETH if no other spend. This is an operational stop limit, not a hard cap on L1 or operator fees; `--with-gas-price` caps execution max fee only and Forge's multiplier estimates, rather than hard-caps, future gas. Before each send, re-simulate and query current fee oracle and remaining allowance; stop if no safe headroom.

## Operator sequence — no authorization to broadcast yet

After separate Stage 1 deployment approval, run public `cast chain-id`, `balance`, `nonce --block latest`, `nonce --block pending`, `gas-price`; compare RPC code/provider bindings, expected empty CREATE address and candidate public signer. Run the corresponding command without `--broadcast --account` first, inspect the generated transaction, actual gas limit, fee cap and current L1/operator estimate, then broadcast only if within remaining ceiling. One transaction at a time; record stdout, receipt, nonce and fees. Do not repeat because output is lost.

The first independent transaction, after approval and a fresh preflight:

```bash
export M4_SIGNER=0xb108b6F40E5Aefdc8475b053BE4248C53eF07B0F
export BASE_RPC=https://base-sepolia-rpc.publicnode.com
"$HOME/.foundry/bin/forge" script script/DeployM4.s.sol:DeployM4 \
  --rpc-url "$BASE_RPC" --sender "$M4_SIGNER" \
  --sig 'deployAsset(address)' "$M4_SIGNER" \
  --account covenant-testnet --broadcast \
  --with-gas-price 15000000 --priority-gas-price 1000000 \
  --gas-estimate-multiplier 130
```

Before any second transaction, check successful receipt, creation address, transaction chain/signer, `cast code`, compare the token runtime hash against the compiled exact `DemoToken` artifact and read `authority()`, `decimals()==6`, `symbol()==cMOCK`, `totalSupply()==0`. Record block, constructor args, all receipt fees including L1 and operator, fresh balance and latest/pending nonce. If successful, recompute next CREATE address using `cast compute-address "$M4_SIGNER" --nonce CURRENT_NONCE` and separately re-simulate `deployOracle(address)` with actual current nonce. Only after those checks provide/execute its independently authorized command:

```bash
"$HOME/.foundry/bin/forge" script script/DeployM4.s.sol:DeployM4 \
  --rpc-url "$BASE_RPC" --sender "$M4_SIGNER" \
  --sig 'deployOracle(address)' "$M4_SIGNER" \
  --account covenant-testnet --broadcast \
  --with-gas-price 15000000 --priority-gas-price 1000000 \
  --gas-estimate-multiplier 130
```

Verify receipt, actual address, operator getter, zero initial valuation, runtime bytecode using deployed immutable substitution rather than comparing unpatched artifact blindly. Stop on chain/signer/nonce mismatch, deployment code collision, changed provider, unexpected transaction, failed receipt, implementation mismatch, shortfall, fee spike, uncertainty or projected ceiling overrun. No later dependent deployment command is authorized by this package.

## Participant funding and callback gate

Lender Base transactions: token approval, vault deposit and commitment, plus possible agreement registration if lender submits it. Borrower Base transactions: possibly registration, repayment token approval and manager repayment; exact signatures/roles in `DEMO_EXECUTION_RUNBOOK.md`. Borrower Unichain pays exactly 0.001 ETH lock plus lock gas and L1/operator fees; binder pays its own bind transaction. Off-chain attestors need no gas unless separately acting as submitter. Current lender and borrower balances are zero; exact minimum safe Base funding cannot yet be measured because vault, agreements, final allowance and receipt state do not exist. Unichain minimum is greater than 0.001 ETH; gas-dependent amount is pending. Do not present provisional allocations as verified or transfer funds.

The deployed financial contract allows destination callback gas between 1000000 and 3000000, but supported provider upper limit is not established. Official Reactive documentation specifies a 100000 callback minimum and a separate 900000 Reactive transaction cap. Current Base provider `_extraGas=80000`, `_maxChargeGas=50000`, coefficient 1100; fee formula and live values must be rechecked. Local receiver/manager trace 635819 gas is not real-proxy forwarding evidence. After dependencies exist, simulate actual callback and provider overhead, obtain provider-supported destination limit, size a bounded failure/retry reserve, and separately authorize configuration and financial callback trials. No callback gas/reserve approved now. See https://dev.reactive.network/economy and https://dev.reactive.network/callback-contracts.


## M4-E.2 scoped authorization and refreshed first preflight

The operator approved covenant-testnet `0xb108b6F40E5Aefdc8475b053BE4248C53eF07B0F` as collateral binder; `CollateralVault.bind` permits the binder to set an agreement borrower and positive lock amount once and has no release or withdrawal function. Vault deployment remains unauthorized. The operator authorized only Base DemoToken and DemoOracle deployments, aggregate 0.00005 ETH including execution, L1 and operator fees; no other networks, deposits or funding. The full deployment validator remains gated and this is not financial callback/activation authorization.

At Base block 64592894, signer balance was 0.029817981153616286 ETH, latest/pending nonce 13, gas quote 6000000 wei, and predicted token `0xC8013185D548990956B9b0CF4bee55C3BE3DF3e9` had no code. Constructor issuer is the approved operator. Exact existing DeployM4 script simulation produced one DemoToken creation, 564046 buffered gas at 15000000 wei max fee, no broadcast. `eth_estimateGas` was 438493; synthetic L1 quote 5453591805252 wei, operator quote zero; execution cap plus illustrative data is 13914281805252 wei. Token creation artifact hash `0xf73653a323a7adb15f67f928d9389292a95c9b0b013d5b920e62dd77674532eb`, runtime hash `0xc07a8af57b1ab30f5903e1348b2712f035d2cf3e18fbe808252d5cf0f1f09ba9`; no runtime immutable references. `authority` is constructor-set storage with no setter, not declared Solidity `immutable`. Recheck hashes, nonce and fees immediately before broadcast.


## M4-E.2 Stage 1 verified

Base DemoToken `0xC8013185D548990956B9b0CF4bee55C3BE3DF3e9` transaction `0x645fa98bbd596b914bae5c9004c9463a589b3f77659ed6527257d304db06b996` (nonce 13) and DemoOracle `0xeBC6B76b9cA1dA2934D89e43bd72Ef0ba9258680` transaction `0x46ee624c1dcde7e5706d4db8a98e9d1c98f45a8368f4dd0bafef2c599fdec189` (nonce 14) have successful receipts, expected constructor code and issuer/operator, and verified runtime hashes including oracle immutable substitutions. Token name/symbol/decimals match and supply is zero; oracle price and update timestamp are zero. Receipt execution and L1 fees plus historical operator oracle zero total 8922518412052 wei and 4091876595152 wei, respectively: aggregate 13014395007204 wei under 50000000000000 wei. No reserve deposits, participant funding, mints or oracle configuration were authorized. Stage 2 requires separate authorization. See `deployments/m4e2.stage1.verified.json`.
