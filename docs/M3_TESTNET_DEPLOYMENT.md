# M3-A testnet deployment design

Design only. No financial testnet deployment is approved or performed. The M1-B transport live gate and independent collateral-finality policy remain open. The existing `CreditManager` and `LocalCreditFactory` must retain their chain-31337 restrictions and must not be deployed or patched on public testnets.

## Testnet-only boundary

Extract one abstract `CreditManagerCore` containing the existing implementation, with local `CreditManager` wrapper (31337 only) and separate `TestnetCreditManager` wrapper (84532 only); retain local factory semantics and add a separate 84532-only testnet factory. The core is not deployable by itself. Shared code must retain all financial checks and interfaces; narrowly scoped internal registration and draw hooks enforce testnet-only policies. See [the architecture decision](M3_INTEGRATION_SPEC.md#final-shared-engine-decision). A subclass of today's unmodified constructor cannot bypass its chain guard; no proxy is proposed as a workaround. Testnet addresses require new V3 signatures. The M2 1,000,000-unit and 365-day maxima remain absolute upper bounds.

For the proposed scenario, enforce **300 mock USDC maximum commitment per agreement and 300 mock USDC maximum aggregate lifetime principal** in the testnet manager, including direct permissionless entrypoints. This replaces the earlier 100-unit proposal, which could not accommodate the requested 300-unit commitment and 200-unit draw. This is a proposed new testnet-only restriction; no such policy exists in the local manager today. A successful 200-unit draw leaves 100 units of aggregate lifetime headroom. Use 0.001 test ETH locked on Unichain, a simulated 1,000 mock-USDC collateral valuation, 1,000 mock-USDC lender deposit, 800 mock-USDC simulated market debt, 200 mock-USDC exact repayment, 5% simple APR and a 50% maximum LTV. The 300-unit commitment is below the simulated 500-unit LTV ceiling. The borrower must separately hold enough mock tokens for principal plus accrued interest at settlement. The collateral remains locked: there is no release or recovery path.

## Dependency matrix and deployment order

| Stage | Network | Dependency and gate |
|---|---|---|
| Transport probe | Unichain/Base/Lasna | Complete three M1-B live routes and evidence before financial callbacks. Existing transport script deploys probes only; it is not a financial deployer. |
| Asset | Base 84532 | Verify a six-decimal faucet token, chain and issuer. If Circle test USDC is unavailable for the harness, use a clearly named faucet test token and do not call it canonical USDC. |
| Collateral | Unichain 1301 | New lock-only `CollateralVault`, scoped testnet binder and test ETH. Lot binding must use the final Base manager/agreement domain. Custody exists, but the current vault has no release. |
| Evidence | Base 84532 | Reviewed independent finalized-lock verifier and a quorum/operator/key policy; authenticated Omni delivery is not evidence of finality. Wire verifier into the manager's fixed `verify(id, lotId, borrower, amount)` interface. |
| Market | Base | Deterministic `TESTNET SIMULATED` market, fixed asset and fixed manager-authorized repayment adapter. Control, minting and oracle inputs are explicitly trusted test operators. |
| Valuation | Base | Fixed test oracle implementing `valueUSDC(amount)` with timestamp and one-hour freshness as required by M2. Stale or unavailable inputs reject execution. No production-price claim. |
| Manager/vault | Base | New testnet factory deploys manager and `CreditLiquidityVault`, verifies fixed wiring and code, and enforces demonstration caps. Deployer records bytecode, constructor parameters and transactions. |
| Orchestrator | Lasna 5318007 | New financial reactive contract subscribes to fixed registry; funded through system `depositTo`. Must be distinct from the probe's contract and authorized M1-B addresses. |
| Financial ingress | Base | New receiver pins Base proxy and final orchestrator address; fund through the Base proxy. Risk registry pins manager and test market. Configure the reactive route only after these addresses exist. |

Ordering is dependency-sensitive: deploy test token, simulated market/adapter, price and evidence verifier; deploy manager/vault via testnet factory; deploy risk registry; deploy Lasna financial orchestrator; deploy Base ingress bound to it; fund, verify wiring and subscribe. Unichain vault must be deployed and its binder configured before terms are signed and collateral locked; its address may be deployed before the Base pair, but the agreement/lot is derived only after manager address and signed terms are known. Verify adapter-manager binding after deployment; if this creates a constructor cycle, use deterministic address prediction and one-time, atomic factory initialization with rejection of uninitialized use. Do not assume the local factory can deploy this topology unchanged. Make initialization and rollback concrete and reviewable before implementation.

## Additional contract and transaction inventory

| Additional component | Network | Baseline deployment/configuration transactions |
|---|---|---|
| Six-decimal mock token/faucet | Base | 1 deployment if no suitable verified test-only token exists; mint/faucet transactions for lender and borrower. |
| Simulated market and adapter | Base | 2 deployments; test market position/risk setup and, if needed, one-time adapter-manager binding. |
| Simulated price oracle | Base | 1 deployment; one valuation/timestamp update, then refresh as needed. |
| Finality verifier | Base | 1 deployment; configure four signers, epoch/policy, authority and source vault, atomically in constructor where possible. |
| Testnet factory, manager and credit vault | Base | 1 factory deployment that creates manager and vault in its constructor; verify all bindings. If a different atomic deployment topology is selected, recalculate transaction count. |
| Risk signal registry | Base | 1 deployment bound to manager/market; one signal transaction for the scenario. |
| Financial reactive orchestrator | Lasna | 1 deployment; 1 reserve funding transaction; 1 route subscription/configuration transaction. |
| Financial authenticated ingress | Base | 1 deployment pinned to proxy/orchestrator/manager/registry; 1 callback-reserve funding transaction. |
| Collateral vault | Unichain | 1 lock-only vault deployment; binder configuration if not fixed in constructor; 1 bind and 1 lock transaction (0.001 test ETH). |

Thus the proposed baseline is **8 Base deployment transactions** (token, market, adapter, oracle, verifier, factory, registry and ingress), **1 Lasna**, and **1 Unichain**, when the factory creates manager and vault in its constructor; additional helper/deployer contracts or initialization transactions require a revised manifest. Configuration, faucet, approve, deposit, bilateral registration, commitment, activation, attestation, market distress, signal and borrower repayment each incur separate transactions as applicable; record the exact planned calls after implementation. The two reserve-funding transactions prepay future charges, rather than add a second reaction/callback cost.

Reuse the verified M1-B network addresses, provider interfaces, `OmniPayer` pattern and probe evidence. Reuse an existing probe deployment only as transport evidence: its fixed probe ABI and pinned sender/recipient cannot authorize financial messages. The financial orchestrator and ingress need their own authentication bindings and reserves. Existing local manager, factory and mock instances cannot be assumed deployable on the testnets.

### Predicted manager and immutable dependency cycle

Use one dedicated Base deployer with a verified nonce and deploy the token, market and oracle first. Immediately before deploying the verifier, adapter and factory, read pending deployer nonce `n`; precompute the factory at `CREATE(deployer, n+2)` and manager/vault at `CREATE(factory, 1)` and `CREATE(factory, 2)`, respectively. Deploy verifier at `n` and adapter at `n+1` with the predicted manager fixed in their constructors, then deploy the factory at `n+2`. These are **planned nonce-derived addresses**, never evidence of deployment: enforce expected addresses, code/bindings and no financial use before the manager exists; stop and recalculate if any nonce changes. The factory deploys manager and vault atomically and checks all immutable dependencies. Test prediction, wrong nonce/address, unauthorized adapter calls, predeployment use and failed-factory rollback. The described nonce ordering is an implementation assumption to verify, not an on-chain deployment already performed.

At minimum, supply 1,000 mock USDC to the lender and at least 200 plus any accrued interest to the borrower for Covenant repayment. A simple scenario may fund the borrower with 800 mock USDC as proceeds of the simulated 800-unit fixture loan, making total initial fixture inventory 1,800 mock USDC; the mock market's debt and token issuance mechanics must reconcile and be disclosed. The adapter transfers the lender-funded 200 units to the mock market during execution. Mock-token minting and valuation are controlled test inputs, not evidence of an external lending market.

## Required funding and cost evidence

M1-B's last preflight (not a current balance or quote) reported signer balances of 4.725 lREACT, 0.01 Unichain ETH and 0 Base ETH. Its provisional **transport-only** spend ceilings were 4.5 lREACT, 0.002 Unichain ETH and 0.004 Base ETH, with a 0.005 ETH Base wallet target. The proposed probe reserves were 3 lREACT plus 0.0005 ETH per destination receiver. These are not M3 estimates and must not be counted twice as extra spending: prepaid provider reserves pay later reaction/callback fees. The M3 financial orchestrator and ingress need their **own** Lasna and Base reserves, separately budgeted from observed gas and provider parameters, and the Base signer needs extra native ETH for financial deployments, configuration, signal and repayment transactions. The Unichain signer needs additional test ETH for actual collateral locked; that ETH remains locked because no release exists. Test-token deposits and simulated market inventory are additional faucet balances, not native-gas costs.

No reliable M3 gas, L1 data, operator-fee or reserve figures exist yet. After implementation, run non-broadcast signer-specific simulations, query OP Stack fee oracles for synthetic unsigned transaction bytes, include L1 data and operator charges, measure callback gas plus provider overhead, failure/retry reserves and contingency, and report per-network ceilings and expected remaining balances before seeking any broadcast authorization. Prior transport estimates alone do not establish that 4.725 lREACT or 0.005 Base ETH funds M3. Recheck actual balances, chain IDs, system/proxy implementation bytecode, fee parameters and keystore/public-address match immediately before execution.

## Acceptance gates

- M1-B records actual authenticated callback delivery and failure/retry reconciliation on all three routes.
- Source-finality policy, signer threshold/keys, rotation, conflict and revocation handling are approved and tested; absence or staleness fails closed.
- Testnet-only manager/vault preserve M2 invariants, V3 signatures, atomic rollback and expiry/default/repayment behavior; the lower aggregate cap cannot be bypassed by direct manager calls.
- Harness behavior is transparently simulated; exact market debt reduction, token receipts and lender credits are evidenced on-chain.
- Financial ingress has dual authentication, independently revalidates current registry and manager state, and handles competing direct execution, stale generations, duplicate delivery and failed callbacks safely.
- All deployments, funding and route activation require a separate expenditure plan and broadcast authorization. No collateral release, liquidation, lender recovery or real-value use is enabled.

## M3-B local implementation status

`TestnetCreditFactory` and `TestnetCreditManager` now enforce chain 84532 and deploy/bind manager and vault atomically, using the same nonce-based creation pattern as the local factory. A constructor-specified asset must be six-decimal and is immutable, but the contracts do not authenticate its issuer or enforce a global allowlist. The fixed 300e6 aggregate counter is scoped to each manager deployment; multiple managers do not share a cap. All tests use Foundry chain-ID simulation and are not live deployment evidence. The verifier, market, oracle and adapter supplied to the factory remain trust dependencies; actual M3 testnet components and funding require separate review and authorization.
