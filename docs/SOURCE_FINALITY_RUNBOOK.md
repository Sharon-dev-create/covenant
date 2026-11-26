# Unichain collateral source-finality runbook

This is a proposed attestor procedure, not an approved finality policy or a cryptographic consensus proof. Before signing, governance must approve the source(s), finality criterion, failure rules and custody. Independent RPC providers reduce correlated operational error but may share infrastructure and do not independently prove consensus. A `finalized` RPC response is a provider assertion. Record UTC observation times, endpoint identity, raw public results, block/transaction hashes and all reconciliations. No secrets or private signing material belong in the evidence packet.

## Obtain and reconcile evidence

Set public variables `UNI_RPC`, `BASE_RPC`, `VAULT`, `MANAGER`, `VERIFIER`, `TX`, `AGREEMENT`, `BORROWER`; use actual approved deployment values, never placeholder addresses. For each approved independent RPC, run the following **read-only** commands (Foundry under `$HOME/.foundry/bin`):

```bash
C="$HOME/.foundry/bin/cast"
"$C" chain-id --rpc-url "$UNI_RPC"     # must be 1301
"$C" chain-id --rpc-url "$BASE_RPC"    # must be 84532
"$C" code "$VAULT" --rpc-url "$UNI_RPC"
"$C" receipt "$TX" --json --rpc-url "$UNI_RPC"
"$C" sig-event 'CollateralLocked(bytes32,bytes32,address,uint256)'
"$C" block finalized --json --rpc-url "$UNI_RPC"
"$C" call "$VAULT" 'positionId(bytes32)(bytes32)' "$AGREEMENT" --rpc-url "$UNI_RPC"
# Set LOT to that returned position ID; Locked has enum value 1.
"$C" call "$VAULT" 'positions(bytes32)(address,bytes32,uint256,uint8)' "$LOT" --rpc-url "$UNI_RPC"
"$C" call "$VAULT" 'borrowers(bytes32)(address)' "$AGREEMENT" --rpc-url "$UNI_RPC"
"$C" call "$VAULT" 'lockAmounts(bytes32)(uint256)' "$AGREEMENT" --rpc-url "$UNI_RPC"
"$C" call "$VERIFIER" 'sourceVault()(address)' --rpc-url "$BASE_RPC"
"$C" call "$VERIFIER" 'manager()(address)' --rpc-url "$BASE_RPC"
"$C" call "$VERIFIER" 'signerEpoch()(uint64)' --rpc-url "$BASE_RPC"
"$C" call "$VERIFIER" 'policyVersion()(uint64)' --rpc-url "$BASE_RPC"
"$C" call "$VERIFIER" 'paused()(bool)' --rpc-url "$BASE_RPC"
"$C" call "$VERIFIER" 'conflict(bytes32)(bool)' "$AGREEMENT" --rpc-url "$BASE_RPC"
```

1. Confirm source chain ID, reviewed vault deployment receipt/runtime hash, binder and destination verifier/manager code and immutable bindings. Get the receipt: `status` must be success, `to` must be the approved vault, and the receipt's transaction and block hashes must match the evidence. Confirm the log's emitting address equals the vault and its first topic equals `0x333254b79544214f6973ac66080e9865401322b179d340ca83dab03f99c01157` (the event signature above). Decode indexed agreement ID, lot ID and borrower and unindexed `uint256 amount`; check the exact log index, amount **1000000000000000 wei**, and intended borrower against signed agreement. Check `positionId`, `borrowers`, `lockAmounts` and the position state at the relevant source block; the lot must match the agreement's deterministic lot and registered terms.
2. Using the receipt's numeric `blockNumber`, call `cast block "$BLOCK_NUMBER" --json --rpc-url "$UNI_RPC"` and require its canonical `hash` equals the receipt's block hash. Get the provider's `finalized` block; its number must be at least the receipt block, and the approved policy must explicitly accept that provider's finalized semantics and any additional criteria. Re-read the numbered block after observing finality. Check all approved independent evidence sources agree on the block hash, receipt, log and finality. A numeric confirmation count without a defined policy is insufficient.
3. On Base read the manager agreement and normalized `termsHash` using the compiled ABI, and verify Draft/Active status, source chain, vault, lot, borrower and amount. Check verifier `sourceVault`, `manager`, current signer epoch and policy, `paused == false`, `conflict(agreementId) == false`, and all four on-chain signer addresses. Check source and destination chain/domain IDs and verifier address against the exact EIP-712 schema in [collateral attestation](COLLATERAL_ATTESTATION.md).
4. Populate all signed fields exactly: source block number/hash, transaction hash, **global receipt log index**, agreement/lot, borrower, collateral amount, terms hash, chain/vault/manager/verifier binding, current epoch and policy. Choose `expiresAt` after current Base block timestamp and at most 1,800 seconds from actual acceptance; use a prudent margin for submission and execution. The struct has no issuance time: require the signer to sign only after evidence reconciliation, and reject pre-signed evidence operationally. Three distinct current authorized signers independently reconcile the same evidence and digest before signing. Submit only after separate transaction approval.
5. Record evidence, signer identities (not keys), the digest, acceptance receipt, `EvidenceAccepted`, expiry and later `verify` result. A successful callback is not evidence of source finality.

If any RPC is unavailable, returns a different chain/hash/receipt/log, cannot report `finalized`, or required bindings/epoch/expiry disagree, **stop: do not sign**. Escalate, preserve results, and resume only after the approved policy resolves the inconsistency. If on-chain `conflict` is true, that agreement is permanently frozen in this implementation; governance cannot clear it. A pause prevents new attestations and eligible draws but does not reverse a completed transaction or prevent existing debt repayment.
