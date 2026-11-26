# M4-B funding and read-only network requirements

Read-only observations on 2026-11-26 near 22:53 UTC: Base Sepolia 84532, signer 0 ETH, gas price 6,000,000 wei, proxy code 218 bytes; Unichain Sepolia 1301, signer 0.01 ETH, gas price 1,500,000 wei, proxy code 218 bytes; Lasna 5318007, signer 4.725 lREACT, gas price 100,000,000,000 wei, system code 239 bytes. The primary Base RPC returned HTTP 403; the previously documented `https://base-sepolia-rpc.publicnode.com` fallback succeeded. Sandboxed DNS had failed; read-only network access succeeded outside that sandbox. Reads used `latest` separately, not one atomic pinned block; observed block numbers were 64058454, 68881135 and 9331099 respectively. Code presence alone does not verify implementation. Base signer has a definite native gas shortfall (zero balance); exact amounts and combined funding sufficiency cannot be calculated until costs and allocations are approved. The previous 4.5 lREACT / 0.002 Unichain ETH / 0.004 Base ETH ceilings were **transport-only**, not combined project ceilings.

## A. M1-B isolated transport

| Chain | Transactions and reserves | Known / unresolved |
|---|---|---|
| Lasna | Deploy one probe reactive contract; configure subscriptions; deposit probe reaction reserve; reaction and retry activity. | Historical proposed ceiling 4.5 lREACT included 3 lREACT reserve; current gas, deposit, reaction charges and contingency pending. |
| Base | Deploy two emitters and two receivers; fund both callback reserves; origin signals and trials. | Historical ceiling 0.004 ETH included two 0.0005 ETH reserves; current execution, L1 data, operator fee, trials and contingency pending. |
| Unichain | Deploy one emitter and one receiver; fund receiver; origin signals and trials. | Historical ceiling 0.002 ETH included a 0.0005 ETH reserve; current execution, L1 data, operator fee, trials and contingency pending. |

## B. Integrated financial deployment

| Chain | Transaction inventory | Required amount |
|---|---|---|
| Unichain | One collateral vault deployment, binder setup transaction. | Current simulation, rollup L1 data and applicable operator charges, plus contingency: **pending**. |
| Base | Eight top-level deployments: mock token, oracle, market, verifier, adapter, demo factory with nested factory/manager/vault, risk registry, callback receiver. | Prior local constructor traces for six demo deployments total 9,188,999 gas; registry 842,951; receiver 1,135,346. These omit transaction intrinsic gas, L1 data, operator fees and current addresses. Current simulations and contingency: **pending**. |
| Lasna | One financial Reactive deployment, one configure/subscription transaction. | Prior local constructor trace 1,238,093 gas; current transaction and subscription costs, operator fee and contingency: **pending**. |

## C. Demonstration and retry

| Chain | Transactions / reserves | Amount |
|---|---|---|
| Base | Token mints, lender approval/deposit/commitment, bilateral registration, attestation submission, activation, oracle/market updates, risk signal, borrower approval/repayment; financial receiver reserve for initial callbacks, failure and retries. | Separate reserve and tx fees **pending**; add actual-address estimates, L1 data, applicable operator charges and contingency. 1,000 cMOCK lender inventory and borrower repayment inventory are minted test units, not ETH. |
| Lasna | Financial system reserve, reactions and operator retries (maximum three requests per trigger). | Separate lREACT reserve and operator transaction fees **pending**. Failed reactions may be charged. |
| Unichain | Borrower lock transaction and corresponding L1 data/operator charges. | Gas and contingency **pending**; locked value listed separately below. |

Prepaid provider reserves are transferred once and subsequently consumed by charges; do not add the full expected charge again as an extra expense unless separately budgeting replenishment. Factor expected failures, bounded retries, fee changes and provider debt in reserve sizing. Every role with its own account needs enough native gas; total wallet funds are not automatically shared among accounts.

## D. Permanently locked collateral

Borrower must provide **0.001 test ETH** on Unichain in addition to gas and contingency. The current vault has no release function. Do not treat this as a recoverable balance. The exact shortfall is `max(0, approved allocation for that signer - verified signer balance)` for each chain/account; allocations and fresh balances are pending.

## Provider parameters and callback gas

The provisional 1,000,000 financial callback gas value is a local simulation candidate only. The contract permits 1,000,000–3,000,000; the current official [Reactive economy](https://dev.reactive.network/economy) documents 100,000 minimum callback gas and a **separate 900,000 Reactive transaction gas cap**, not a maximum destination callback gas. The proxy reserves `_extraGas` and `_maxChargeGas` before forwarding, and charges the receiver in destination native currency. Reaction charges are in lREACT; failures may still be charged. Read-only latest-state calls on 2026-11-26 returned Base/Unichain coefficient 1100, extra gas 80,000, max charge gas 50,000 and Lasna coefficient 1000, extra gas 100,000, max charge gas 50,000. These are point-in-time values, not a guarantee at deployment. See [network verification](NETWORK_VERIFICATION.md).

Before approving a limit or reserve, obtain official supported callback upper limit, current proxy implementation and live `_extraGas`, `_maxChargeGas`, coefficient and fee formula; determine actual forwarded gas and provider charges from a successful, authenticated callback receipt and failed/retry receipts; get current Lasna reaction charges; simulate the actual financial receiver with actual addresses and conservative gas; include all transaction/L1 data/operator charges, a defined number of retries and contingency. If any upper limit, forwarding or billing behavior remains undocumented or unverified, the financial callback configuration remains blocked. The [callback documentation](https://dev.reactive.network/callback-contracts) documents dual authentication and explicitly says callback requests do not by themselves establish successful delivery.

## Exact read-only checks for the operator

These commands use only public addresses and do not unlock the keystore or send transactions:

```bash
C="$HOME/.foundry/bin/cast"
A=0xb108b6F40E5Aefdc8475b053BE4248C53eF07B0F
BASE=https://sepolia.base.org
UNI=https://sepolia.unichain.org
LASNA=https://lasna-rpc.rnk.dev/
BP=0x476F44b11F5C942c58f4c8E3d0300E5710743585
UP=0x775c9B990ADe401060B78D0e98684eEf8d2466C1
SYS=0x8888888888888888888888888888888888888888
for RPC in "$BASE" "$UNI" "$LASNA"; do
  "$C" chain-id --rpc-url "$RPC"
  "$C" balance "$A" --ether --rpc-url "$RPC"
  "$C" gas-price --rpc-url "$RPC"
done
"$C" code "$BP" --rpc-url "$BASE"
"$C" code "$UP" --rpc-url "$UNI"
"$C" code "$SYS" --rpc-url "$LASNA"
for FIELD in '_gasPriceCoeffPer1000()(uint256)' '_extraGas()(uint256)' '_maxChargeGas()(uint256)'; do
  "$C" call "$BP" "$FIELD" --rpc-url "$BASE"
  "$C" call "$UP" "$FIELD" --rpc-url "$UNI"
  "$C" call "$SYS" "$FIELD" --rpc-url "$LASNA"
done
```

Require chain IDs 84532, 1301, 5318007 respectively; nonempty code alone does not establish the intended implementation. Pin block number and record code hash and proxy implementation slot/implementation code; compare official [origin/destination configuration](https://dev.reactive.network/origins-and-destinations). Read current balances and gas quote at the same time. For deployed contracts, read `reserves(address)` and `debt(address)` from their exact provider. Obtain OP Stack L1 data and operator-fee estimates with the documented oracle methods on synthetic unsigned public transaction bytes; verify current oracle semantics and fee parameters and do not transmit keys or signed transactions. Historical estimates are not substitutes.

To verify the encrypted Foundry account locally without printing its key, run interactively:

```bash
"$HOME/.foundry/bin/cast" wallet address --account covenant-testnet
```

The operator enters the keystore password at the local prompt; compare the resulting address with `0xb108b6F40E5Aefdc8475b053BE4248C53eF07B0F`. Do not provide the password or private key to this workflow.
