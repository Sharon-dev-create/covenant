// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {CreditLiquidityVault} from "./CreditLiquidityVault.sol";

interface ILocalCollateralVerifier {
    function verify(bytes32 agreementId, bytes32 lotId, address borrower, uint256 amount) external view returns (bool);
}

interface ILocalCollateralOracle {
    function valueUSDC(uint256 amount) external view returns (uint256 value, uint256 updatedAt);
}

/// @notice Local-only lifecycle harness. Its fixtures do not establish cross-chain finality.
contract CreditManager {
    error InvalidTerms();
    error InvalidAuthorization();
    error InvalidState();
    error InvalidCollateral();
    error InvalidPrice();
    error Reentrant();

    enum State {
        Absent,
        Draft,
        Active,
        Closed
    }

    struct Terms {
        address borrower;
        address lender;
        address collateralVault;
        uint256 collateralChainId;
        bytes32 lotId;
        uint256 collateralAmount;
        address market;
        address debtor;
        bytes32 policy;
        uint256 cap;
        uint256 nonce;
        uint64 consentDeadline;
        uint64 drawDeadline;
        uint64 maturity;
        uint64 grace;
        uint16 ltvBps;
    }

    struct Agreement {
        Terms terms;
        State state;
        bytes32 reservationId;
    }

    bytes32 public constant TERMS_TYPEHASH = keccak256(
        "Terms(address borrower,address lender,address collateralVault,uint256 collateralChainId,bytes32 lotId,uint256 collateralAmount,address market,address debtor,bytes32 policy,uint256 cap,uint256 nonce,uint64 consentDeadline,uint64 drawDeadline,uint64 maturity,uint64 grace,uint16 ltvBps)"
    );
    bytes32 private constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    uint256 private constant HALF_ORDER = 0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;
    uint256 public constant MAX_PRICE_AGE = 1 hours;

    address public immutable vault;
    address public immutable asset;
    address public immutable localCollateralVerifier;
    address public immutable localOracle;
    address public immutable localAdapter;
    mapping(bytes32 => Agreement) private agreements;
    mapping(address => mapping(uint256 => bool)) public usedNonce;
    mapping(bytes32 => bytes32) public lotAgreement;
    bool private entered;

    event AgreementRegistered(bytes32 indexed agreementId, address indexed borrower, address indexed lender);
    event AgreementActivated(bytes32 indexed agreementId, bytes32 indexed reservationId);
    event AgreementClosed(bytes32 indexed agreementId);

    constructor(
        address vault_,
        address asset_,
        address localCollateralVerifier_,
        address localOracle_,
        address localAdapter_
    ) {
        if (
            block.chainid != 31337 || vault_ == address(0) || asset_.code.length == 0
                || localCollateralVerifier_.code.length == 0 || localOracle_.code.length == 0
                || localAdapter_ == address(0)
        ) revert InvalidTerms();
        vault = vault_;
        asset = asset_;
        localCollateralVerifier = localCollateralVerifier_;
        localOracle = localOracle_;
        localAdapter = localAdapter_;
    }

    modifier nonReentrant() {
        if (entered) revert Reentrant();
        entered = true;
        _;
        entered = false;
    }

    function termsHash(Terms calldata terms) public pure returns (bytes32) {
        Terms memory normalized = terms;
        normalized.lotId = bytes32(0);
        return keccak256(abi.encode(TERMS_TYPEHASH, normalized));
    }

    function agreementId(Terms calldata terms) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                "AGREEMENT_V1",
                block.chainid,
                address(this),
                terms.borrower,
                terms.lender,
                terms.nonce,
                termsHash(terms)
            )
        );
    }

    function digest(Terms calldata terms) public view returns (bytes32) {
        bytes32 domain =
            keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("Covenant"), keccak256("1"), block.chainid, address(this)));
        return keccak256(abi.encodePacked("\x19\x01", domain, termsHash(terms)));
    }

    function register(Terms calldata terms, bytes calldata borrowerSignature, bytes calldata lenderSignature)
        external
        nonReentrant
        returns (bytes32 id)
    {
        if (
            terms.borrower == address(0) || terms.lender == address(0) || terms.collateralVault == address(0)
                || terms.collateralChainId == 0 || terms.collateralAmount == 0 || terms.market == address(0)
                || terms.debtor != terms.borrower || terms.policy == bytes32(0) || terms.cap == 0 || terms.ltvBps == 0
                || terms.ltvBps > 5000 || terms.consentDeadline < block.timestamp
                || terms.drawDeadline <= block.timestamp || terms.maturity <= terms.drawDeadline
        ) revert InvalidTerms();
        bytes32 expectedLot =
            keccak256(abi.encode("LOT_V1", terms.collateralChainId, terms.collateralVault, agreementId(terms)));
        // The derived lot field is normalized to zero in termsHash to avoid a circular ID.
        if (terms.lotId != expectedLot) revert InvalidTerms();
        if (usedNonce[terms.borrower][terms.nonce]) revert InvalidState();
        bytes32 signed = digest(terms);
        if (_recover(signed, borrowerSignature) != terms.borrower || _recover(signed, lenderSignature) != terms.lender) revert InvalidAuthorization();
        id = agreementId(terms);
        if (agreements[id].state != State.Absent || lotAgreement[terms.lotId] != bytes32(0)) revert InvalidState();
        usedNonce[terms.borrower][terms.nonce] = true;
        lotAgreement[terms.lotId] = id;
        agreements[id] = Agreement(terms, State.Draft, bytes32(0));
        emit AgreementRegistered(id, terms.borrower, terms.lender);
    }

    function activate(bytes32 id) external nonReentrant {
        Agreement storage agreement = agreements[id];
        Terms storage terms = agreement.terms;
        if (agreement.state != State.Draft || block.timestamp >= terms.drawDeadline) revert InvalidState();
        if (!ILocalCollateralVerifier(localCollateralVerifier)
                .verify(id, terms.lotId, terms.borrower, terms.collateralAmount)) revert InvalidCollateral();
        (uint256 value, uint256 updatedAt) = ILocalCollateralOracle(localOracle).valueUSDC(terms.collateralAmount);
        if (value == 0 || updatedAt == 0 || updatedAt > block.timestamp || block.timestamp - updatedAt > MAX_PRICE_AGE) revert InvalidPrice();
        if (terms.cap > value / 10000 * terms.ltvBps + (value % 10000) * terms.ltvBps / 10000) revert InvalidPrice();
        agreement.state = State.Active;
        agreement.reservationId = CreditLiquidityVault(vault).reserve(id, terms.lender, terms.cap);
        emit AgreementActivated(id, agreement.reservationId);
    }

    function cancelUnused(bytes32 id) external nonReentrant {
        Agreement storage agreement = agreements[id];
        if (msg.sender != agreement.terms.borrower) revert InvalidAuthorization();
        _close(id, agreement);
    }

    function expireUnused(bytes32 id) external nonReentrant {
        Agreement storage agreement = agreements[id];
        if (block.timestamp < agreement.terms.drawDeadline) revert InvalidState();
        _close(id, agreement);
    }

    function agreement(bytes32 id) external view returns (Terms memory terms, State state, bytes32 reservationId) {
        Agreement storage a = agreements[id];
        return (a.terms, a.state, a.reservationId);
    }

    function _close(bytes32 id, Agreement storage agreement) private {
        State previous = agreement.state;
        if (previous != State.Draft && previous != State.Active) revert InvalidState();
        agreement.state = State.Closed;
        if (previous == State.Active) CreditLiquidityVault(vault).cancel(agreement.reservationId);
        emit AgreementClosed(id);
    }

    function _recover(bytes32 hash, bytes calldata signature) private pure returns (address signer) {
        if (signature.length != 65) revert InvalidAuthorization();
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly ("memory-safe") {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }
        if (uint256(s) > HALF_ORDER || (v != 27 && v != 28)) revert InvalidAuthorization();
        signer = ecrecover(hash, v, r, s);
        if (signer == address(0)) revert InvalidAuthorization();
    }
}
