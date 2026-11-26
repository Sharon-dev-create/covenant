// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {CreditManagerCore} from "../CreditManagerCore.sol";

/// @notice Testnet-only trusted 3-of-4 assertions; it does NOT verify source-chain consensus.
contract CollateralAttestationVerifier {
    struct CollateralLockAttestationV1 {
        uint256 sourceChainId;
        address sourceVault;
        uint256 destinationChainId;
        address destinationVerifier;
        address destinationManager;
        uint256 sourceBlockNumber;
        bytes32 sourceBlockHash;
        bytes32 sourceTxHash;
        uint256 sourceLogIndex;
        bytes32 agreementId;
        bytes32 lotId;
        address borrower;
        uint256 collateralAmount;
        bytes32 termsHash;
        uint64 signerEpoch;
        uint64 policyVersion;
        uint64 expiresAt;
    }

    struct Evidence {
        bytes32 digest;
        bytes32 facts;
        bytes32 eventId;
        bytes32 lotId;
        address borrower;
        uint256 amount;
        uint64 epoch;
        uint64 expiresAt;
    }
    bytes32 public constant ATTESTATION_TYPEHASH = keccak256(
        "CollateralLockAttestationV1(uint256 sourceChainId,address sourceVault,uint256 destinationChainId,address destinationVerifier,address destinationManager,uint256 sourceBlockNumber,bytes32 sourceBlockHash,bytes32 sourceTxHash,uint256 sourceLogIndex,bytes32 agreementId,bytes32 lotId,address borrower,uint256 collateralAmount,bytes32 termsHash,uint64 signerEpoch,uint64 policyVersion,uint64 expiresAt)"
    );
    bytes32 private constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    uint256 private constant HALF_ORDER = 0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;
    uint256 public constant MAX_VALIDITY = 30 minutes;
    uint256 public constant ROTATION_DELAY = 24 hours;
    uint256 public constant SOURCE_CHAIN = 1301;
    address public immutable sourceVault;
    address public immutable manager;
    address public immutable governance;
    address public immutable emergencyAuthority;
    address[4] public signers;
    address[4] public pendingSigners;
    uint64 public signerEpoch = 1;
    uint64 public policyVersion = 1;
    uint64 public pendingPolicy;
    uint256 public rotationAvailableAt;
    bool public paused;
    mapping(bytes32 => Evidence) private evidence;
    mapping(bytes32 => bytes32) public eventAgreement;
    mapping(bytes32 => bytes32) public lotAgreement;
    mapping(bytes32 => bool) public conflict;
    error Unauthorized();
    error InvalidEvidence();
    error InvalidSignatures();
    error Paused();
    error InvalidRotation();
    event EvidenceAccepted(bytes32 indexed agreementId, bytes32 indexed eventId, bytes32 digest, uint64 expiresAt);
    event EvidenceConflict(bytes32 indexed agreementId, bytes32 indexed existingEventId, bytes32 newEventId);
    event PauseChanged(bool paused);
    event RotationProposed(uint64 indexed nextEpoch, uint64 policy, uint256 availableAt);
    event RotationActivated(uint64 indexed epoch, uint64 policy);

    constructor(
        address sourceVault_,
        address manager_,
        address governance_,
        address emergency_,
        address[4] memory signers_
    ) {
        if (
            block.chainid != 84532 || sourceVault_ == address(0) || manager_ == address(0) || governance_ == address(0)
                || emergency_ == address(0)
        ) revert InvalidEvidence();
        _checkSigners(signers_);
        sourceVault = sourceVault_;
        manager = manager_;
        governance = governance_;
        emergencyAuthority = emergency_;
        signers = signers_;
    }

    function domainSeparator() public view returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256("CovenantCollateralAttestation"),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

    function digest(CollateralLockAttestationV1 calldata a) public view returns (bytes32) {
        return
            keccak256(abi.encodePacked("\x19\x01", domainSeparator(), keccak256(abi.encode(ATTESTATION_TYPEHASH, a))));
    }

    function acceptLock(CollateralLockAttestationV1 calldata a, bytes[] calldata signatures) external {
        if (paused) revert Paused();
        if (block.chainid != 84532) revert InvalidEvidence();
        if (
            a.sourceChainId != SOURCE_CHAIN || a.sourceVault != sourceVault || a.destinationChainId != block.chainid
                || a.destinationVerifier != address(this) || a.destinationManager != manager || a.sourceBlockNumber == 0
                || a.sourceBlockHash == bytes32(0) || a.sourceTxHash == bytes32(0) || a.agreementId == bytes32(0)
                || a.lotId == bytes32(0) || a.borrower == address(0) || a.collateralAmount == 0
                || a.signerEpoch != signerEpoch || a.policyVersion != policyVersion || a.expiresAt <= block.timestamp
                || uint256(a.expiresAt) > block.timestamp + MAX_VALIDITY
        ) revert InvalidEvidence();
        CreditManagerCore m = CreditManagerCore(manager);
        (CreditManagerCore.Terms memory t, CreditManagerCore.State state,) = m.agreement(a.agreementId);
        if (
            (state != CreditManagerCore.State.Draft && state != CreditManagerCore.State.Active)
                || t.collateralChainId != SOURCE_CHAIN || t.collateralVault != sourceVault || t.lotId != a.lotId
                || t.borrower != a.borrower || t.collateralAmount != a.collateralAmount || m.termsHash(t) != a.termsHash
        ) revert InvalidEvidence();
        bytes32 signedDigest = digest(a);
        _verifySignatures(signedDigest, signatures);
        bytes32 eventId = keccak256(
            abi.encode(
                "COVENANT_LOCK_EVENT_V1",
                a.sourceChainId,
                a.sourceVault,
                a.sourceBlockHash,
                a.sourceTxHash,
                a.sourceLogIndex
            )
        );
        CollateralLockAttestationV1 memory normalized = a;
        normalized.signerEpoch = 0;
        normalized.policyVersion = 0;
        normalized.expiresAt = 0;
        bytes32 facts = keccak256(abi.encode(normalized));
        Evidence storage old = evidence[a.agreementId];
        if (conflict[a.agreementId]) revert InvalidEvidence();
        if (old.digest == signedDigest) return;
        if (old.facts != bytes32(0) && old.facts != facts) {
            conflict[a.agreementId] = true;
            emit EvidenceConflict(a.agreementId, old.eventId, eventId);
            return;
        }
        if (
            (eventAgreement[eventId] != bytes32(0) && eventAgreement[eventId] != a.agreementId)
                || (lotAgreement[a.lotId] != bytes32(0) && lotAgreement[a.lotId] != a.agreementId)
        ) revert InvalidEvidence();
        eventAgreement[eventId] = a.agreementId;
        lotAgreement[a.lotId] = a.agreementId;
        evidence[a.agreementId] =
            Evidence(signedDigest, facts, eventId, a.lotId, a.borrower, a.collateralAmount, a.signerEpoch, a.expiresAt);
        emit EvidenceAccepted(a.agreementId, eventId, signedDigest, a.expiresAt);
    }

    function verify(bytes32 agreementId, bytes32 lotId, address borrower, uint256 amount) external view returns (bool) {
        Evidence storage e = evidence[agreementId];
        return block.chainid == 84532 && !paused && !conflict[agreementId] && e.digest != bytes32(0)
            && e.epoch == signerEpoch && block.timestamp < e.expiresAt && e.lotId == lotId && e.borrower == borrower
            && e.amount == amount;
    }

    function setPaused(bool value) external {
        if (value ? (msg.sender != emergencyAuthority && msg.sender != governance) : msg.sender != governance) {
            revert Unauthorized();
        }
        paused = value;
        emit PauseChanged(value);
    }

    function proposeRotation(address[4] calldata next, uint64 policy) external {
        if (msg.sender != governance) revert Unauthorized();
        if (policy == 0) revert InvalidRotation();
        _checkSigners(next);
        pendingSigners = next;
        pendingPolicy = policy;
        rotationAvailableAt = block.timestamp + ROTATION_DELAY;
        emit RotationProposed(signerEpoch + 1, policy, rotationAvailableAt);
    }

    function activateRotation() external {
        if (msg.sender != governance) revert Unauthorized();
        if (rotationAvailableAt == 0 || block.timestamp < rotationAvailableAt) revert InvalidRotation();
        signers = pendingSigners;
        policyVersion = pendingPolicy;
        signerEpoch++;
        delete pendingSigners;
        delete pendingPolicy;
        delete rotationAvailableAt;
        emit RotationActivated(signerEpoch, policyVersion);
    }

    function _checkSigners(address[4] memory group) private pure {
        for (uint256 i; i < 4; i++) {
            if (group[i] == address(0)) revert InvalidRotation();
            for (uint256 j; j < i; j++) if (group[j] == group[i]) revert InvalidRotation();
        }
    }

    function _verifySignatures(bytes32 hash, bytes[] calldata sigs) private view {
        if (sigs.length < 3 || sigs.length > 4) revert InvalidSignatures();
        uint256 bitmap;
        for (uint256 i; i < sigs.length; i++) {
            if (sigs[i].length != 65) revert InvalidSignatures();
            bytes32 r;
            bytes32 s;
            uint8 v;
            bytes calldata sig = sigs[i];
            assembly ("memory-safe") {
                r := calldataload(sig.offset)
                s := calldataload(add(sig.offset, 32))
                v := byte(0, calldataload(add(sig.offset, 64)))
            }
            if (uint256(s) > HALF_ORDER || (v != 27 && v != 28)) revert InvalidSignatures();
            address recovered = ecrecover(hash, v, r, s);
            uint256 index = 4;
            for (uint256 j; j < 4; j++) {
                if (signers[j] == recovered) {
                    index = j;
                    break;
                }
            }
            if (index == 4 || bitmap & (1 << index) != 0) revert InvalidSignatures();
            bitmap |= 1 << index;
        }
    }
}
