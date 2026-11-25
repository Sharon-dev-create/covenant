# M2 credit engine preparation

Status: proposed for review. Implementation has not been authorized. Live Reactive transport, independent finality, external market integration and lender recovery remain unverified.

## Scope and existing boundaries

Base Sepolia is the authoritative ledger for agreements, reservation state, principal and interest. One borrower and lender sign one facility, backed by one identified Unichain ETH lot, with one successful non-revolving draw. The maximum initial and draw LTV is 50%, simple annual interest is 5%, and commitment fees are zero. Draw expiry and maturity are distinct. M2 preparation authorizes no financial activation, ETH release, liquidation or real-value use.

The existing CollateralVault has an immutable binder, accepts one exact-amount lock per agreement, and emits `CollateralLocked(agreementId,positionId,borrower,amount)`. It does not emit a terms hash or operation ID, verify signatures or release ETH. Its lot ID includes the immutable deployment chain ID. The existing LiquidityVault has an immutable manager and consumer, lender-owned `setCommitment`, manager-only `reserve`, `cancel` and `consume`, and returns the unused reservation to free cash on consumption. Its reservation ID is similarly bound to the vault deployment chain ID. These deployments cannot be reconfigured to an independently deployed manager or consumer.

Two integration gaps require a reviewed design before implementation. First, `consume` transfers an exact amount to the fixed consumer but does not call a repayment adapter or prove market repayment. The manager and consumer must coordinate atomically in one Base transaction, or a reviewed new vault interface is required. Second, the current vault has no way for a third-party payer or manager to credit a specific lender with repaid principal or interest. An ordinary deposit credits its caller, so sending tokens to the vault is surplus and cannot satisfy lender recovery. Define and test a narrowly authorized measured repayment-credit interface or a separate lender-owned repayment escrow before implementing the full lifecycle. Existing vaults stay unchanged in this specification milestone.

## Proposed CreditManager interface

All signatures below are conceptual. Exact ABI, type hashes and storage layouts are subject to review.

| Function | Caller and purpose |
|---|---|
| `register(terms, borrowerSignature, lenderSignature)` | Anyone submits two valid, deadline-bound EIP-712 authorizations. Consume borrower nonce once and record a Draft. |
| `stageLockIntent(operation, payload)` | Future authenticated ingress records the exact observed lock intent without granting credit. |
| `submitFinalizedLock(attestation)` | Anyone submits independently verified finalized evidence, bound to the same operation and payload. |
| `activate(agreementId)` | Anyone atomically verifies both facts, fresh valuation and lender commitment, then reserves the full signed cap. |
| `observeRisk(agreementId)` | Anyone asks the approved risk module to sample the bound position. A qualifying observation creates one pending epoch. |
| `executePending(agreementId, epoch)` | Authorized ingress or any local caller performs all live checks and the exact purpose-bound repayment. |
| `repay(agreementId, amount)` | Any payer supplies up to the accrued claim. Exact receipt is applied interest first and principal second. |
| `cancelUnused(agreementId)` | Borrower closes a Draft or Active facility before any successful draw. |
| `expireUnused(agreementId)` | Anyone closes an unused facility at or after its draw deadline. |
| `markDefault(agreementId)` | Anyone records default at or after maturity plus grace if debt remains. Cure remains available. |
| `agreement`, `debtAt`, `pendingOperation` | Read-only state and preview. Preview rounds consistently with state-changing accrual. |

Terms bind version, chain and manager, both vault addresses and deployment chain IDs, borrower and lender, borrower nonce, consent deadline, collateral lot and amount, asset, market, debtor, adapter and policy, cap, maximum 50% LTV, 5% APR, draw deadline, maturity and grace. Verify both signers, unique nonce, valid time ordering, supported immutable module configuration, and the lender's separate vault commitment. Specify supported EOA and contract-wallet signatures before implementation. Signed terms cannot be edited by an administrator.

Agreement ID is `keccak256(abi.encode("AGREEMENT_V1", baseChain, manager, borrower, lender, borrowerNonce, termsHash))`. Lot and reservation IDs use their existing vault formulas and deployment chain IDs. A draw ID binds manager, agreement and monotonically increasing risk epoch. Cross-chain operation IDs bind version, source chain, emitter, destination chain, receiver, kind, agreement, sequence and canonical payload hash. Evidence additionally binds canonical block hash, transaction hash and log index. Store operation ID and payload hash together. Exact duplicates are no-ops and conflicting reuse reverts. Consumed nonces, invalidated epochs and terminal agreements never reopen.

## Transitions and atomicity

| Transition | Preconditions and outcome |
|---|---|
| Absent → Draft | Valid bilateral consent and unused nonce. Store immutable terms and emit `AgreementRegistered`. |
| Draft → Active | Matching authenticated transport intent and finalized lock evidence identify the expected vault, lot, borrower and amount. Cap fits current LTV, commitment and free cash. Reserve the cap and emit `AgreementActivated` atomically. |
| Draft/Active → Closed unused | Borrower cancels, or anyone expires at the draw deadline. Invalidate pending epoch and return reservation if present. Emit `AgreementClosed`. No collateral release is enabled. |
| Active → Drawn | A current pending epoch passes all live checks before draw deadline. In one guarded Base transaction consume at most the cap, complete the bound market repayment, verify actual vault debit and market effect, return unused reservation, and book equal principal. Emit `DrawExecuted`. Any failure reverts all local effects. |
| Pending → Invalidated | Close or epoch expiry permanently invalidates that draw ID. A later qualifying observation uses a new epoch. |
| Drawn/Defaulted → same | Accrue and apply measured partial receipt to interest then principal. Emit `DebtRepaid`. |
| Drawn/Defaulted → Closed | Full measured payment clears principal, accrued interest and any final rounding unit. Emit repayment and close events. ETH remains locked in the current vault. |
| Drawn → Defaulted | Anyone acts at maturity plus grace with positive claim. Emit `AgreementDefaulted`. No write-off, seizure or assumed settlement. |

Registration/cancellation recovery for a lock made before registration remains a future release-protocol requirement from the architecture. The current vault cannot enact release or an early tombstone. Cancellation and draw race by Base transaction ordering. If execution wins, unused cancellation fails. If close wins, the epoch is invalid. Failed transfers, failed repayment, stale data and reentrancy revert atomically. Expiry cannot erase debt, and default cannot block cure.

## Valuation, debt and rounding

Normalize prices to the same scale. For ETH wei `W`, ETH/USD price `E` and USDC/USD price `U`, compute `floor(W * E * 10^6 / (10^18 * U))` using full-precision multiplication and division. Feed decimals, positive values, timestamp bounds, heartbeat, sequencer status and grace period must be validated. Do not trust future-dated or stale observations. A Base ETH reference values the economic asset and does not establish Unichain custody or settlement value.

Let `limit = floor(valueUSDC * min(signedLtvBps,5000) / 10000)`. Activation requires cap ≤ limit. On draw, `headroom = max(0, limit - principal - accruedInterest)` and spend is bounded by headroom, remaining contractual cap, reserved cash, current market debt and purpose-policy cap. Require a useful positive repayment and verified risk improvement or complete debt exit, with explicit tested market rounding tolerance.

For each accrual interval use denominator `D = 10000 * 365 days`, numerator `principal * 500 * elapsed + carry`, interest increment `floor(numerator / D)`, and `carry = numerator % D`. Accrue before each principal change with full-precision arithmetic. Do not compound accrued interest. On final payoff, charge one USDC base unit if carry is nonzero and clear it. Define the full-payoff quote and actual receipt in the same transaction to avoid leaving rounding dust. Repayments are capped at the claim and allocate to interest before principal. Any excess stays with the payer. Interest continues through default until a separately approved settlement policy says otherwise.

Managed vault cash equals free plus reserved. Reservation creates no principal. Principal equals cumulative verified draw minus measured principal repayment, recovery and approved write-off. Recovery and write-off are disabled in this scope. Interest and principal are receivables until actual payment is credited to the correct lender. Unsolicited token and ETH transfers remain segregated surplus. Closing a funded agreement requires zero principal and interest, and closing an unused agreement requires zero reservation.

## Authentication and dependencies

M1-B live callback delivery, injected sender, ordering, redelivery and finality behavior remain unverified. Before any live activation, validate the exact proxy and reactive sender and require an independently authenticated finalized source assertion. A candidate is a reviewed 3-of-5 independent attestation quorum using independently operated rollup and Ethereum nodes, EIP-712 domain binding, signer epochs, rotation and replay protection. It introduces explicit quorum and node trust. It is a proposal, not an implemented or approved finality verifier. A raw RPC response or Reactive callback alone cannot satisfy this gate. Duplicate, delayed, missing, contradictory and reorged evidence must fail closed.

An approved oracle needs feed addresses, decimals, heartbeat, sequencer handling, USDC basis policy and manipulation bounds. The market adapter needs a verified asset-compatible market, precise debt and health semantics, bounded approvals and atomic rollback. Aave's observed Base Sepolia test USDC differs from Circle test USDC. A deterministic market and oracle fixture can exercise local mechanics while clearly labelled as such. Real lender recovery needs an independently specified and verified sale or prefunded settlement path and explicit shortfall accounting. There is no liquidation or ETH release in this preparation.

## Test plan

- Unit: bilateral consent, nonce/domain errors, vault consent, reserve accounting, activation guards, deadlines, fixed target, successful and failed draw, partial/full repayment, zero and boundary amounts, interest carry and final-unit rounding.
- Fuzz: full-range collateral and price decimals, overflow-safe valuation, stale/future timestamps, LTV boundaries, cap clipping, interest checkpoint partitions, repayment allocation and nonce/operation domains. Compare to an independent high-precision model.
- Stateful invariants: ghost-ledger free/reserved cash, measured receipts, principal and interest, single successful draw, terminal states, surplus isolation, no cross-agreement effects and no release. Require action coverage and track rejected operations rather than passing through empty handlers.
- Adversarial: duplicate and conflicting evidence, delayed and out-of-order intent/proof, invalid quorum, stale or reorged lock, concurrent draws, reserve exhaustion, deterioration between observation and execution, sequencer outage, forged callbacks, adapter under/over-spend, failed market call, token transfer anomalies and reentrancy.
- Lifecycle races: cancellation or expiry against execution in both orders, repayment against default, partial repayment after default, and repeated payoff. Missing destination evidence never infers success. Mock transport and oracle tests must be labelled local.

## Implementation sequence and acceptance gates

1. Review and approve this specification, particularly lender repayment credit, atomic adapter integration, signature support and collateral-event binding. No M2 contract implementation precedes review.
2. Specify a test-only architecture with deterministic market, oracle and proof inputs, and a deployable manager/vault/consumer wiring plan. Preserve existing contracts until a separately reviewed migration or replacement is authorized.
3. Implement consent, reservation and debt accounting locally, then add the atomic purpose-bound draw and cure paths. Independently validate formulas and all listed tests. Gate all live financial entry points.
4. Complete M1-B live transport verification separately. Validate sender identity, each route, failure visibility, re-request and reconciliation. This establishes transport behavior, not finalized-source proof.
5. Design, implement and review the independent finality verifier and event binding. Test reorg and quorum failures. Financial activation stays disabled until both transport and finality gates pass.
6. Verify the actual oracle and compatible market or conversion route. Prove real lender repayment credit and separately solve cross-chain recovery before any real-value scope is considered.

Acceptance requires passing unit, fuzz, invariant and adversarial suites with the specified accounting properties, an auditable fixture lifecycle, no arbitrary asset destination, and clear evidence that financial activation and collateral release remain disabled. Live transport, oracle, finality and recovery evidence are separate release gates.
