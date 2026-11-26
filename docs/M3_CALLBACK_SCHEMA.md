# M3-A callback schema and execution contract

Status: proposed ABI for review; none of these financial messages or contracts exists yet. This is a new financial route, not the M1-B probe ABI. Encoding is Solidity ABI `abi.encode`, never packed encoding for identifiers. All chain IDs and addresses below are values checked against immutable deployment configuration.

## Origin signal: Base -> Lasna -> Base

```solidity
// Emitted by an immutable Base testnet RiskSignalRegistry, not by a user-provided market.
event RiskSignaled(bytes32 indexed agreementId, uint64 indexed generation, address indexed manager);
function signal(bytes32 agreementId) external returns (uint64 generation);
function latestGeneration(bytes32 agreementId) external view returns (uint64);
```

`signal` checks manager identity, Active state and the configured test market's current risk/debt, creates and emits a monotonically increasing generation only when no current signal is outstanding. While a signal remains outstanding, repeated `signal` calls return its existing generation without incrementing it or emitting another event. Any caller can signal. The registry is a hint and its fixture market is mutable; neither is financial authorization. A failed callback retains the signal and any previously committed pending operation; the orchestrator can re-request the same stored trigger so failed requests cannot permanently block liveness. Bound emissions and funding operationally to limit spam; a spammer still cannot choose a financial outcome. The current signal can be retired only after the manager is terminal, or after a permissionless on-chain recheck establishes recovery or insufficient external debt and clears any ineligible pending operation. The keeper may then issue a fresh signal after distress recurs; an arbitrary caller cannot supersede a still-eligible signal. Monotonic overflow reverts. Define an operator pause for request production, not for altering the manager's previously signed terms; scope and governance require review.

Subscribe once to `(84532, registry, keccak256("RiskSignaled(bytes32,uint64,address)"), IGNORE, IGNORE, uint256(uint160(manager)))`. Agreement and generation are topics 1 and 2, manager is topic 3. Registry and manager are pinned; the system-only `react(LogRecord)` validates address, chain, topic widths, signature and exact ABI shape. Use the documented Omni ignore sentinel rather than zero. Require one event signature and version; no untrusted emitter may choose the receiver. Store the semantic key and fixed callback data when requesting, retaining source block hash, tx hash and log index from the Omni envelope for audit. Logs do not themselves expose their own final tx hash or block hash to the emitting contract.

## Callback ABI and identity

```solidity
struct FinancialTriggerV1 {
    uint32 version;             // exactly 1
    uint256 originChainId;      // 84532
    address originRegistry;     // pinned Base registry
    uint256 destinationChainId; // 84532
    address manager;            // pinned testnet manager
    bytes32 agreementId;
    uint64 generation;
}
function onRiskSignal(address reactiveSender, bytes32 triggerId, FinancialTriggerV1 calldata trigger) external;
```

System request: `requestCallbackV_1_0((84532, ingress, callbackGasLimit, abi.encodeCall(onRiskSignal,(address(0),triggerId,trigger))))`. The first address slot is reserved for Omni's injected reactive-contract identity. `triggerId = keccak256(abi.encode("COVENANT_RISK_TRIGGER_V1", block.chainid, address(this), originChainId, originRegistry, destinationChainId, ingress, manager, agreementId, generation))`, computed by the Lasna orchestrator, where `block.chainid` is 5318007 and `address(this)` is that orchestrator. The Base ingress recomputes using immutable `reactiveChainId` and `expectedReactive`, not its own chain/address in those positions. It additionally verifies `msg.sender == pinnedBaseProxy`, `reactiveSender == expectedReactive`, `block.chainid == 84532`, every route/version/address and `latestGeneration(agreementId) == generation`. Exact domain tuple prevents cross-contract, chain and version replay. Immutable deployment addresses avoid mutable redirection; any change requires a new deployment and reviewed migration.

## Operation lifecycle and idempotency

For an unprocessed trigger, read `agreement(id)` and `pendingDraw(id)`. If Active and pending is zero, call `observeRisk(id)` and use the returned manager operation ID. If pending is nonzero, use it; do not derive or overwrite a manager operation. Read `autonomousRepayment` from the returned signed `Terms` and call `executePending(id, operationId, amount)`. The manager remains authoritative for its own epoch, debt, current risk, LTV, collateral, oracle freshness, deadline, allowed amount and one successful draw. Never trust a callback's amount or party/market addresses; they are deliberately absent.

### Defined callback dispositions

Authentication and structural checks precede every state change. The ingress records `Disposition(triggerId, agreementId, outcome, operationId)` for authenticated, well-formed requests; `operationId` is zero when no manager operation is known. Dispositions below are **destination-local**; the Lasna orchestrator does not automatically learn them and reconciles using the destination receipt, event and manager state. An operator must inspect that evidence before any re-request. A successful outer proxy transaction alone is insufficient.

| Condition | Destination behavior | Reconciliation / retry |
|---|---|---|
| Wrong proxy or injected reactive sender | Revert; write nothing. | Authentication failure; inspect proxy/RC configuration, do not retry unchanged. |
| Wrong chain, version, registry, manager, trigger hash, malformed encoding or invalid route | Revert; write nothing. | Invalid payload/configuration, investigate; no financial success. |
| Unknown agreement | Record terminal `SkippedUnknown`; no manager financial call. | A later registration is a different lifecycle: issue a fresh signal/generation after registration. |
| Identical trigger already `Executed` or terminally `Skipped` | Return successfully with `Duplicate` acknowledgement; do not repeat financial calls or overwrite the original disposition. | Reconcile the stored original disposition and `DrawExecuted`; duplicate is not a new execution. |
| Position recovered or market debt insufficient | After a successful current-state read, clear an existing ineligible pending operation through `clearRecoveredRisk`; record terminal `SkippedRecovered`. | No debt; after distress recurs, registry retires the prior generation and emits a fresh one. |
| Draw deadline passed or agreement expired | Record terminal `SkippedExpired`; no execution. | If still Active, `expireUnused` remains callable separately to return reservation; no new trigger can resurrect it. |
| Closed, settled, cancelled, defaulted or already Drawn by a competing executor | Record terminal `SkippedTerminal` or `AlreadyDrawn`; no new draw. | State `Closed` alone does not identify settlement versus cancellation; use manager events. For already Drawn, reconcile the actual `DrawExecuted` event; do not invent a deleted pending operation ID. |
| Stale registry generation | Record terminal `SkippedStale`; no financial call. | Reconcile the registry's current generation and request its existing trigger, if eligible. |
| Temporary oracle, verifier, market, token, adapter, gas or provider failure | Revert the complete callback and write no disposition. | Read manager and receipt state; repair dependency/funding and re-request the same trigger, subject to limits. A newly created pending operation rolls back; a previously committed one survives. |
| Current eligible signal and all financial checks succeed | Atomically call `observeRisk` if needed and `executePending` with the signed amount; after success store `Executed` and emit acknowledgement with manager operation ID. | Match `DrawExecuted`, principal, vault and market deltas. Retries of that trigger are duplicate acknowledgements. |

If current risk/debt cannot be read, treat it as a temporary failure rather than `SkippedRecovered`. A manager revert due to an ambiguous dependency failure is not caught and reclassified as success. To avoid check/use races, perform classification and execution in one transaction; manager revalidation remains decisive. A failed acknowledgement write also reverts the financial call. `processed[triggerId]` distinguishes absent, executed and each skipped reason; a conflicting payload with an existing ID reverts. The signal registry may retire a skipped generation only under its documented current-state checks. Unauthenticated or invalid callbacks cannot poison the disposition store.

## Finalized collateral attestation V1

This is a separate Base verifier interface, not the risk callback and not implemented yet:

```solidity
struct CollateralLockAttestationV1 {
    uint256 sourceChainId; address sourceVault;
    uint256 destinationChainId; address destinationVerifier; address destinationManager;
    uint256 sourceBlockNumber; bytes32 sourceBlockHash; bytes32 sourceTxHash; uint256 sourceLogIndex;
    bytes32 agreementId; bytes32 lotId; address borrower; uint256 collateralAmount;
    bytes32 termsHash; uint64 signerEpoch; uint64 policyVersion; uint64 expiresAt;
}
function acceptLock(CollateralLockAttestationV1 calldata a, bytes[] calldata signatures) external;
function verify(bytes32 agreementId, bytes32 lotId, address borrower, uint256 amount) external view returns (bool);
```

EIP-712 domain is `EIP712Domain(name="CovenantCollateralAttestation",version="1",chainId=84532,verifyingContract=<Base verifier>)`. The exact type string is:

```text
CollateralLockAttestationV1(uint256 sourceChainId,address sourceVault,uint256 destinationChainId,address destinationVerifier,address destinationManager,uint256 sourceBlockNumber,bytes32 sourceBlockHash,bytes32 sourceTxHash,uint256 sourceLogIndex,bytes32 agreementId,bytes32 lotId,address borrower,uint256 collateralAmount,bytes32 termsHash,uint64 signerEpoch,uint64 policyVersion,uint64 expiresAt)
```

 Hash all struct fields in the exact declared order and canonical Solidity widths using a fixed published type hash. Require source chain 1301, the configured source vault, destination 84532, this verifier and the configured manager, exact registered terms hash, deterministic lot/borrower/amount, nonzero canonical event identity and `block.timestamp <= expiresAt`. The four configured signer addresses are distinct; recover canonical low-s signatures, reject duplicates and nonmembers, and require at least three distinct current-epoch signers.

Derive `sourceEventId = keccak256(abi.encode("COVENANT_LOCK_EVENT_V1", sourceChainId, sourceVault, sourceBlockHash, sourceTxHash, sourceLogIndex))`; bind it and the agreement/lot to one accepted attestation digest. Re-submission of the identical digest is an idempotent no-op and `verify` remains usable for later activation/draw checks. Reject attempts to bind one event or lot to another agreement. A conflicting otherwise valid quorum certificate for the same agreement/lot or source event triggers an explicit conflict/freeze state and event with no activation; because a revert rolls back the freeze, conflict reporting must succeed while refusing to replace accepted evidence. A subsequently discovered conflict freezes future activation/draw and does not pretend to reverse an already completed cross-chain transaction.

A designated testnet governance authority proposes a new set of four distinct signers and policy version, records epoch and activation time, and activates it only after a publicly visible delay; emergency revocation immediately rejects new evidence from a revoked epoch. Historical accepted evidence remains subject to expiration, conflict and revocation checks at each `verify`. Rotation cannot reauthorize a consumed source event to a different lot; signers must not equivocate across epochs. Exact delay, authority/custody and operational incident response require human approval before deployment. A 3-of-4 quorum is a trusted attestation, not a source-chain proof: with at most one equivocator and honest cross-epoch non-equivocation, any two quorums intersect in at least one honest signer; two offline signers prevent progress and three compromised signers can attest false data. Four keys controlled by one developer are not independently operated.

Before signing, each independent attestor must apply the approved policy to the canonical source receipt, correct event/lot and source block finality; specify the RPC/node and L1-finalized rollup derivation evidence in the deployment policy. Reactive callback authentication proves transport provenance only and is not a finality assertion.

## Evidence and acceptance

For each attempt record source chain/registry, agreement, generation, source block hash/tx hash/log index and timestamp; Lasna transaction, subscription, trigger ID, callback request and timestamp; Base proxy/ingress, injected sender, receipt status and event, manager operation ID and `DrawExecuted`, token/debt deltas, vault accounting, and timestamp. Record timeouts and failures explicitly. Enforce both proxy and injected sender per [official callback documentation](https://dev.reactive.network/callback-contracts). Source event confirmation/finality remains a separate policy; a valid callback is not a proof of finalized collateral.

## M3-B boundary

The shared core and chain-restricted testnet manager/factory now exist locally. This callback ABI, risk registry, orchestrator, ingress and attestation verifier remain specifications only; no callback authorization or source finality guarantee has been implemented by M3-B.
