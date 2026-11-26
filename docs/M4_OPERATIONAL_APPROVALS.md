# M4-B operational approval package — pending

This is a proposed, testnet-only configuration. No roles, finality policy, cost ceilings or transactions are approved by this document. Candidate deployer `0xb108b6F40E5Aefdc8475b053BE4248C53eF07B0F` and encrypted Foundry label `covenant-testnet` were supplied previously; the current keystore-to-address match has not been checked here; fresh public balance observations are in [funding requirements](M4_FUNDING_REQUIREMENTS.md). The operator must confirm both before assignment.

## Roles and separation

All addresses below are **pending**, including the candidate deployer; all approvals are pending. “Can share” describes contract permissions, not an approval. Use encrypted keystores or hardware-backed signing, controlled local access and a custody/recovery process; never disclose secrets. The binder must be explicitly assigned even though it was not in the short role list.

| Role | Permissions and chain | Can share / custody and separation |
|---|---|---|
| Deployer | Create configured contracts on 1301, 84532 and 5318007; public address pending (candidate above). | Can use existing funded account after identity check. Nonce must stay controlled during predicted Base deployments. |
| Lender | Base: mint recipient, token approval, deposit, set commitment, sign EIP-712 as lender; address pending. | May share a test-only account including borrower under existing rules; independent lender nonce still applies. Separate identities give clearer consent evidence. |
| Borrower | Base: sign agreement, approve and repay; Unichain: lock 0.001 test ETH; address pending. | May share a test-only account with lender, with independent borrower nonce. Must retain repayment tokens and gas. |
| Binder | Unichain: immutable vault binder calls `bind`; address pending. | May share deployer. Wrong binding is irreversible for the agreement. |
| Token issuer | Base demo token `mint`; address pending. | May share deployer/operator; controls the entire simulated token supply. |
| Oracle operator | Base demo oracle `update`; address pending. | May share operator; fully controls simulated valuation. |
| Market operator | Base demo market `setPosition`; address pending. | May share operator; fully controls simulated debt and distress. |
| Four attestors | Sign source evidence for Base verifier; addresses 1–4 pending and **must be distinct**. Signing itself is off-chain. | At least three valid distinct signatures; protect each key. Four developer-controlled keys are one operational trust domain, not four independent organizations. |
| Attestor rotation/governance | Base verifier propose/activate rotation and unpause; address pending. | May share deployer/emergency authority, but separate custody reduces correlated compromise. Governance is immutable. |
| Emergency pause | Base verifier immediate pause; address pending. | May share governance; governance or emergency can pause, only governance unpauses. |
| Reactive operator/retry | Lasna `configure`, `retry`, `stop`; address pending. | May share deployer; configuration caller must be the operator. Stop is permanent for that instance. |
| Callback funding authority | Base proxy and Lasna system `depositTo`; address pending. | Permissionless deposit can be made by any funded account; may share deployer. Separate financial and probe reserves. |

Minimum practical configuration is four distinct ECDSA addresses for attestors, one of which could also perform every other role under the contracts' role rules, with distinct borrower/lender nonce namespaces and both signatures still supplied. Such consolidation is a **single trust domain** and is suitable only for a clearly disclosed synthetic demonstration. Check actual account custody, operational capacity and chain balances; it is not independent quorum security. A safer practical setup separates emergency/governance, lender/borrower and operational keys, subject to available accounts and approval.

## Governance and finality decisions

Contract-enforced: exactly four distinct attestor addresses; 3–4 distinct canonical signatures; acceptance expiry strictly in future and no more than 30 minutes from Base block time; source 1301/destination 84532, pinned vault and manager, EIP-712 domain and registered agreement binding; 24-hour delay for signer rotation; governance or emergency can pause, only governance unpauses; a conflicting accepted quorum freezes the agreement permanently. Pause blocks new approvals and verification-dependent activations/draws; repayment is unaffected. There is no emergency vault withdrawal, collateral release, debt forgiveness or conflict-clear function. Rotation invalidates previously accepted evidence until renewed under the new epoch. The signed struct lacks `issuedAt`: prohibit pre-signing by policy; the contract cannot enforce signing time.

Human decisions: exact signers and custody; immutable governance, emergency, binder, market/oracle and issuer roles; how finalized RPC evidence and source log identity are independently reconciled; permissible expiration and clock margin; policy version; response and rotation approval; the test token, factory and all dependency bytecode and immutable addresses; provisional callback gas and funded retries; separate M1-B and financial ceilings; irreversible 0.001 test ETH lock. Follow [source-finality runbook](SOURCE_FINALITY_RUNBOOK.md). Quorums have two signers of intersection; safety assumes at most one equivocating signer across quorums/epochs and honest signers verify the same source policy. Three compromised keys can sign false evidence; two unavailable keys halt progress. Shared custody defeats independence.

Incident: stop signing immediately, preserve public receipts/logs and conflicting evidence, have emergency or governance pause the verifier, and verify `paused()`. Reactive operator may stop its route if required; that stop is permanent, and stopping orchestration is not a substitute for pausing financial eligibility. Review already-executed debt separately: pause cannot reverse it and repayment remains available. Governance proposes replacement unique signers and policy, waits the full 24 hours and activates after checking configuration and custody. Reconcile canonical source, epoch, frozen agreements and debt before governance unpauses; frozen agreement conflicts cannot be cleared by rotation or unpause. Do not sign contradictory statements or claim an on-chain finality proof.

## Approval checklist

**Decide now:** named roles/public addresses and custody; source-finality policy and independent evidence sources; signer separation, rotation and incident procedure; mock asset/market/valuation; permanent lock; provisional cost methodology and limits.

**After M1-B live results and fresh measurements:** authenticated successful receipts for Unichain→Lasna→Base, Base→Lasna→Unichain and Base→Lasna→Base, including failed delivery/retry; verify provider addresses/implementation, gas forwarding and price; review address-specific simulations, all L1 data/operator fees, reaction/callback reserves and contingency; approve exact per-network ceilings and callback limit; verify signer and funded accounts. The live callback only authenticates the route, not source finality. Broadcast authorization is a **separate final decision** for the concrete reviewed expenditure plan.

The manifest validator rejects unresolved explicit approval fields and route evidence, but checks only local statements and cannot authenticate approvals, prevent someone bypassing the validator, validate RPC truth or authorize broadcast. `DeployM4.s.sol` can be run independently of the validator. The operator must enforce the process; contract-level enforcement is not introduced in this milestone.
