# Architecture

Unichain Sepolia owns ETH custody. Base Sepolia owns all financial decisions and credit accounting. Lasna observes exact emitter/topic pairs and routes constrained intents. Contracts use fixed counterpart addresses per deployment and immutable economic terms per agreement.

| Component | Chain | Responsibilities and trust boundary |
|---|---|---|
| CollateralVault | Unichain | `lock(terms, authorization)` takes exact ETH and binds lot to Base agreement. Accepts release intent only from an isolated callback receiver, then approves release with matching finalized proof. `claim(id, recipient)` pays once and only on borrower authority. No admin sweep of custody. |
| LiquidityVault | Base | Deposit and withdraw free USDC by lender. Manager alone reserves, returns or atomically spends per lot. Credit returned principal and revenue to lender after measured transfer. Separate gas balances. |
| CreditManager | Base | Verifies consent, confirms lock, reserves, activates, changes lifecycle, executes, repays, defaults and publishes terminal release authorization. Owns agreement, purpose, cap, cumulative draw, debt and operation records. |
| CovenantReactive | Lasna | Authenticated log handling, deterministic routing, callback requests, and bounded retry coordination. Holds reaction funding only. |
| RepaymentAdapter | Base | Only manager can call an immutable allowlisted adapter for this purpose. Reads account risk and debt, approves exact spend, invokes fixed market call, validates spend and repayment effect, clears allowance, returns unused tokens within the Base transaction. |
| CollateralOracle | Base | Converts fresh Base-local ETH/USD and USDC/USD prices into USDC units. Separate deterministic test deployments can inject scenario prices. |
| RiskManager | Base | Read-only pre/postflight policy over agreement, current oracle, current market debt and health, and draw limits. |
| Finality verifier | Base and Unichain | Verifies a domain-bound finalized-source event assertion independently of the Reactive callback. MVP candidate is an explicitly trusted threshold signer set reading finalized blocks. Production proof system remains open. |

CreditManager stores matching lock intent and finalized assertion in either order, or accepts each through retry. Apply activation only when both are present, consent/terms match, reservation is possible, and the oracle is fresh. Release uses symmetric gates over the irreversible Base decision. The signers validate exact event and payload, source receipt canonicality, finalized inclusion and deployment domains. Store both attestations and callback intents as facts; neither grants generic transfer authority. The two inputs must match op ID and payload hash. A malicious signer quorum plus transport compromise can defeat this trust model. Define and test key rotation, thresholds, independence and outage behavior before live testing. An authorized callback may stage a fact early but cannot finalize it early. If either input is absent, custody stays locked.

Borrower and lender sign typed terms bound to the Base manager, version, both chains and contract addresses, borrower, lender, unique nonce, lock amount, target market/account/token, LTV, cap, expiry/maturity and fee/rate parameters. Borrower account is the market debtor. Use typed-domain signatures, signature deadlines, explicit nonce consumption and deterministic hashes using `abi.encode`:

- Agreement `H("AGREEMENT_V1", baseChain, manager, borrower, lender, borrowerNonce, termsHash)` where termsHash excludes the derived ID.
- Lot `H("LOT_V1", uniChain, vault, agreementId)`. This is computed before lock and unique on both sides.
- Draw `H("DRAW_V1", baseChain, manager, agreementId, riskEpoch)`. Also enforce one ever-successful draw by agreement.
- Cross-chain operation `H("OP_V1", version, sourceChain, emitter, destChain, receiver, kind, agreementId, sequence, payloadHash)`. Hash the canonical operation fields excluding the ID itself. Bind proof additionally to block hash, tx hash and log index. Event receipt identity alone is insufficient as a business nonce.
- Settlement `H("SETTLEMENT_V1", baseChain, manager, agreementId, defaultSequence)`.

Base terminal state is irreversible before a release event. ETH stays in custody if Base never approves release or delivery stalls. Register a signed draft on Base before submitting the lock, and allow the borrower to request Base draft cancellation at any time before activation. The contract must allow the borrower to register and immediately close an unused signed draft in one Base transaction if ETH was locked first, even after the draw deadline. Require the same signatures, nonce and exact terms, and create a terminal tombstone with no draw authority. A previously used nonce must resolve to the same recorded agreement before any release can apply. A cancelled draft can publish a release authorization for its exact deterministic lot even before receiving its lock. Unichain can stage that authorization before lock, preventing the later deposit or allowing claim if it already landed. No unilateral Unichain timeout exit.
