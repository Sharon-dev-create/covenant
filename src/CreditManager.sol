// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {CreditLiquidityVault} from "./CreditLiquidityVault.sol";
import {ReservationState} from "./ProtocolTypes.sol";

interface IExecutionToken {
    function balanceOf(address) external view returns (uint256);
    function allowance(address, address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
}

interface ILocalMarket {
    function asset() external view returns (address);
    function debt(address borrower) external view returns (uint256);
    function isDistressed(address borrower) external view returns (bool);
    function health(address borrower) external view returns (uint256);
}

interface ILocalAdapter {
    function asset() external view returns (address);
    function market() external view returns (address);
    function repay(address borrower, uint256 amount) external returns (uint256);
}

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
    error InvalidExecution();

    enum State {
        Absent,
        Draft,
        Active,
        Closed,
        Drawn
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
        uint256 borrowerNonce;
        uint256 lenderNonce;
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
        "Terms(address borrower,address lender,address collateralVault,uint256 collateralChainId,bytes32 lotId,uint256 collateralAmount,address market,address debtor,bytes32 policy,uint256 cap,uint256 borrowerNonce,uint256 lenderNonce,uint64 consentDeadline,uint64 drawDeadline,uint64 maturity,uint64 grace,uint16 ltvBps)"
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
    mapping(address => mapping(uint256 => bool)) public usedBorrowerNonce;
    mapping(address => mapping(uint256 => bool)) public usedLenderNonce;
    mapping(bytes32 => bytes32) public lotAgreement;
    mapping(bytes32 => uint64) public riskEpoch;
    mapping(bytes32 => bytes32) public pendingDraw;
    mapping(bytes32 => bool) public completedDraw;
    mapping(bytes32 => uint256) public principal;
    mapping(bytes32 => uint256) public drawTimestamp;
    bool private entered;

    event AgreementRegistered(bytes32 indexed agreementId, address indexed borrower, address indexed lender);
    event AgreementActivated(bytes32 indexed agreementId, bytes32 indexed reservationId);
    event AgreementClosed(bytes32 indexed agreementId);
    event BorrowerNonceInvalidated(address indexed borrower, uint256 indexed nonce);
    event LenderNonceInvalidated(address indexed lender, uint256 indexed nonce);
    event RiskObserved(bytes32 indexed agreementId, bytes32 indexed operationId, uint64 epoch);
    event DrawExecuted(bytes32 indexed agreementId, bytes32 indexed operationId, uint256 principal, uint256 timestamp);

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
                terms.borrowerNonce,
                termsHash(terms)
            )
        );
    }

    function digest(Terms calldata terms) public view returns (bytes32) {
        bytes32 domain =
            keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("Covenant"), keccak256("2"), block.chainid, address(this)));
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
        if (usedBorrowerNonce[terms.borrower][terms.borrowerNonce] || usedLenderNonce[terms.lender][terms.lenderNonce]) revert InvalidState();
        bytes32 signed = digest(terms);
        if (_recover(signed, borrowerSignature) != terms.borrower || _recover(signed, lenderSignature) != terms.lender) revert InvalidAuthorization();
        id = agreementId(terms);
        if (agreements[id].state != State.Absent || lotAgreement[terms.lotId] != bytes32(0)) revert InvalidState();
        usedBorrowerNonce[terms.borrower][terms.borrowerNonce] = true;
        usedLenderNonce[terms.lender][terms.lenderNonce] = true;
        lotAgreement[terms.lotId] = id;
        agreements[id] = Agreement(terms, State.Draft, bytes32(0));
        emit AgreementRegistered(id, terms.borrower, terms.lender);
    }

    function invalidateBorrowerNonce(uint256 nonce) external {
        if (usedBorrowerNonce[msg.sender][nonce]) revert InvalidState();
        usedBorrowerNonce[msg.sender][nonce] = true;
        emit BorrowerNonceInvalidated(msg.sender, nonce);
    }

    function invalidateLenderNonce(uint256 nonce) external {
        if (usedLenderNonce[msg.sender][nonce]) revert InvalidState();
        usedLenderNonce[msg.sender][nonce] = true;
        emit LenderNonceInvalidated(msg.sender, nonce);
    }

    function observeRisk(bytes32 id) external nonReentrant returns (bytes32 operationId) {
        Agreement storage a = agreements[id];
        if (a.state != State.Active || block.timestamp >= a.terms.drawDeadline || pendingDraw[id] != bytes32(0)) {
            revert InvalidState();
        }
        if (!ILocalMarket(a.terms.market).isDistressed(a.terms.borrower)) revert InvalidExecution();
        uint64 epoch = ++riskEpoch[id];
        operationId = keccak256(abi.encode("DRAW_V1", block.chainid, address(this), id, epoch));
        pendingDraw[id] = operationId;
        emit RiskObserved(id, operationId, epoch);
    }

    /// @notice Local fixture execution only. The borrower authorizes the bounded action.
    function executePending(bytes32 id, bytes32 operationId, uint256 amount) external nonReentrant {
        Agreement storage a = agreements[id];
        Terms storage t = a.terms;
        if (msg.sender != t.borrower) revert InvalidAuthorization();
        if (
            a.state != State.Active || block.timestamp >= t.drawDeadline || operationId == bytes32(0)
                || pendingDraw[id] != operationId || completedDraw[operationId]
        ) revert InvalidState();
        _validateDraw(id, a, amount);
        _repayMarket(t, a.reservationId, amount);
        principal[id] = amount;
        drawTimestamp[id] = block.timestamp;
        completedDraw[operationId] = true;
        delete pendingDraw[id];
        a.state = State.Drawn;
        emit DrawExecuted(id, operationId, amount, block.timestamp);
    }

    function _validateDraw(bytes32 id, Agreement storage a, uint256 amount) private view {
        Terms storage t = a.terms;
        if (!ILocalCollateralVerifier(localCollateralVerifier).verify(id, t.lotId, t.borrower, t.collateralAmount)) {
            revert InvalidCollateral();
        }
        (uint256 value, uint256 updatedAt) = ILocalCollateralOracle(localOracle).valueUSDC(t.collateralAmount);
        if (value == 0 || updatedAt == 0 || updatedAt > block.timestamp || block.timestamp - updatedAt > MAX_PRICE_AGE) revert InvalidPrice();
        uint256 limit = value / 10000 * t.ltvBps + (value % 10000) * t.ltvBps / 10000;
        ILocalMarket market = ILocalMarket(t.market);
        ILocalAdapter adapter = ILocalAdapter(localAdapter);
        if (
            t.debtor != t.borrower || market.asset() != asset || adapter.asset() != asset
                || adapter.market() != t.market || !market.isDistressed(t.borrower)
        ) revert InvalidExecution();
        (address lender, bytes32 agreementId_, uint256 reserved, ReservationState state) =
            CreditLiquidityVault(vault).reservations(a.reservationId);
        if (
            lender != t.lender || agreementId_ != id || state != ReservationState.Reserved || amount == 0
                || amount > reserved || amount > t.cap || amount > limit
        ) revert InvalidExecution();
        if (amount > market.debt(t.borrower)) revert InvalidExecution();
    }

    struct ExecutionSnapshot {
        uint256 debt;
        uint256 health;
        uint256 managerBalance;
        uint256 adapterBalance;
        uint256 marketBalance;
    }

    function _repayMarket(Terms storage t, bytes32 reservationId, uint256 amount) private {
        ILocalMarket market = ILocalMarket(t.market);
        ILocalAdapter adapter = ILocalAdapter(localAdapter);
        IExecutionToken token = IExecutionToken(asset);
        ExecutionSnapshot memory before_ = ExecutionSnapshot(
            market.debt(t.borrower),
            market.health(t.borrower),
            token.balanceOf(address(this)),
            token.balanceOf(localAdapter),
            token.balanceOf(t.market)
        );
        if (token.allowance(address(this), localAdapter) != 0 || token.allowance(localAdapter, t.market) != 0) {
            revert InvalidExecution();
        }
        CreditLiquidityVault(vault).consume(reservationId, amount);
        if (token.balanceOf(address(this)) != before_.managerBalance + amount) revert InvalidExecution();
        _approve(localAdapter, amount);
        uint256 reported = adapter.repay(t.borrower, amount);
        _approve(localAdapter, 0);
        uint256 afterDebt = market.debt(t.borrower);
        if (
            reported != amount || afterDebt != before_.debt - amount
                || token.balanceOf(t.market) != before_.marketBalance + amount
                || token.balanceOf(address(this)) != before_.managerBalance
                || token.balanceOf(localAdapter) != before_.adapterBalance
                || token.allowance(address(this), localAdapter) != 0 || token.allowance(localAdapter, t.market) != 0
                || (afterDebt != 0 && market.health(t.borrower) <= before_.health)
        ) revert InvalidExecution();
    }

    function _approve(address spender, uint256 amount) private {
        (bool ok, bytes memory result) = asset.call(abi.encodeCall(IExecutionToken.approve, (spender, amount)));
        if (!ok || (result.length != 0 && (result.length != 32 || abi.decode(result, (uint256)) != 1))) {
            revert InvalidExecution();
        }
        if (IExecutionToken(asset).allowance(address(this), spender) != amount) revert InvalidExecution();
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
        delete pendingDraw[id];
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
