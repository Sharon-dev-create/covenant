// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {CreditLiquidityVault} from "./CreditLiquidityVault.sol";
import {ReservationState} from "./ProtocolTypes.sol";

interface IExecutionToken {
    function balanceOf(address) external view returns (uint256);
    function allowance(address, address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function decimals() external view returns (uint8);
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
    error InvalidRepayment();
    error InvalidTimestamp();

    enum State {
        Absent,
        Draft,
        Active,
        Closed,
        Drawn,
        Defaulted
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
        uint256 autonomousRepayment;
        uint256 maxHealth;
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
        "Terms(address borrower,address lender,address collateralVault,uint256 collateralChainId,bytes32 lotId,uint256 collateralAmount,address market,address debtor,bytes32 policy,uint256 cap,uint256 autonomousRepayment,uint256 maxHealth,uint256 borrowerNonce,uint256 lenderNonce,uint64 consentDeadline,uint64 drawDeadline,uint64 maturity,uint64 grace,uint16 ltvBps)"
    );
    bytes32 private constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    uint256 private constant HALF_ORDER = 0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;
    uint256 public constant MAX_PRICE_AGE = 1 hours;
    uint256 public constant APR_BPS = 500;
    uint256 public constant INTEREST_DENOMINATOR = 630720000;

    /// @notice Financial operating envelope: 1,000,000 six-decimal USDC units per agreement.
    uint256 public constant MAX_COMMITMENT = 1_000_000 * 1_000_000;
    uint256 public constant MAX_PRINCIPAL = 1_000_000 * 1_000_000;
    /// @notice Contractual term from draw deadline to maturity. Post-maturity accrual is not bounded by this value.
    uint64 public constant MAX_TERM = 365 days;
    /// @notice Timestamps are represented as uint64. Interest may accrue over the entire representable range.
    uint256 public constant MAX_ACCRUAL_SECONDS = uint256(type(uint64).max);
    /// @notice Tight upper bound on whole-unit interest for one maximum principal over the full uint64 range.
    uint256 public constant MAX_SUPPORTED_INTEREST = (MAX_PRINCIPAL / INTEREST_DENOMINATOR) * MAX_ACCRUAL_SECONDS
        + (MAX_PRINCIPAL % INTEREST_DENOMINATOR) * (MAX_ACCRUAL_SECONDS / INTEREST_DENOMINATOR)
        + ((MAX_PRINCIPAL % INTEREST_DENOMINATOR) * (MAX_ACCRUAL_SECONDS % INTEREST_DENOMINATOR)) / INTEREST_DENOMINATOR
        + 1;
    uint256 public constant MAX_SUPPORTED_CLAIM = MAX_PRINCIPAL + MAX_SUPPORTED_INTEREST;

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
    mapping(bytes32 => uint64) public drawTimestamp;
    mapping(bytes32 => uint64) public lastAccrued;
    mapping(bytes32 => uint256) public accruedInterest;
    mapping(bytes32 => uint256) public interestRemainder;
    mapping(bytes32 => uint256) public totalInterestAccrued;
    mapping(bytes32 => uint256) public totalInterestPaid;
    mapping(bytes32 => uint256) public totalPrincipalPaid;
    bool private entered;

    event AgreementRegistered(bytes32 indexed agreementId, address indexed borrower, address indexed lender);
    event AgreementActivated(bytes32 indexed agreementId, bytes32 indexed reservationId);
    event AgreementClosed(bytes32 indexed agreementId);
    event BorrowerNonceInvalidated(address indexed borrower, uint256 indexed nonce);
    event LenderNonceInvalidated(address indexed lender, uint256 indexed nonce);
    event RiskObserved(bytes32 indexed agreementId, bytes32 indexed operationId, uint64 epoch);
    event RiskCleared(bytes32 indexed agreementId, bytes32 indexed operationId);
    event DrawExecuted(bytes32 indexed agreementId, bytes32 indexed operationId, uint256 principal, uint256 timestamp);
    event InterestAccrued(bytes32 indexed agreementId, uint256 amount, uint256 remainder);
    event DebtRepaid(
        bytes32 indexed agreementId,
        bytes32 indexed paymentId,
        address indexed payer,
        uint256 interestPaid,
        uint256 principalPaid
    );
    event AgreementDefaulted(bytes32 indexed agreementId);

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
        (bool decimalsOk, bytes memory decimalsResult) = asset_.staticcall(abi.encodeCall(IExecutionToken.decimals, ()));
        if (!decimalsOk || decimalsResult.length != 32 || abi.decode(decimalsResult, (uint8)) != 6) {
            revert InvalidTerms();
        }
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
            keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("Covenant"), keccak256("3"), block.chainid, address(this)));
        return keccak256(abi.encodePacked("\x19\x01", domain, termsHash(terms)));
    }

    /// @notice Rejects any timestamp that cannot be represented by the uint64 storage representation.
    function checkedTimestamp(uint256 value) public pure returns (uint64 checked) {
        if (value > MAX_ACCRUAL_SECONDS) revert InvalidTimestamp();
        // Bounded by the check above; assignment truncates only values known to fit.
        assembly ("memory-safe") {
            checked := value
        }
    }

    function register(Terms calldata terms, bytes calldata borrowerSignature, bytes calldata lenderSignature)
        external
        nonReentrant
        returns (bytes32 id)
    {
        uint64 now_ = checkedTimestamp(block.timestamp);
        if (
            terms.borrower == address(0) || terms.lender == address(0) || terms.collateralVault == address(0)
                || terms.collateralChainId == 0 || terms.collateralAmount == 0 || terms.market == address(0)
                || terms.debtor != terms.borrower || terms.policy != bytes32(uint256(1)) || terms.cap == 0
                || terms.cap > MAX_COMMITMENT || terms.autonomousRepayment == 0
                || terms.autonomousRepayment > MAX_PRINCIPAL || terms.autonomousRepayment > terms.cap
                || terms.maxHealth == 0 || terms.ltvBps == 0 || terms.ltvBps > 5000 || terms.consentDeadline < now_
                || terms.drawDeadline <= now_ || terms.maturity <= terms.drawDeadline
                || uint256(terms.maturity) - uint256(terms.drawDeadline) > uint256(MAX_TERM)
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
        uint64 now_ = checkedTimestamp(block.timestamp);
        if (a.state != State.Active || now_ >= a.terms.drawDeadline || pendingDraw[id] != bytes32(0)) {
            revert InvalidState();
        }
        if (
            !_riskSatisfied(a.terms)
                || ILocalMarket(a.terms.market).debt(a.terms.borrower) < a.terms.autonomousRepayment
        ) revert InvalidExecution();
        uint64 epoch = ++riskEpoch[id];
        operationId = keccak256(abi.encode("DRAW_V1", block.chainid, address(this), id, epoch));
        pendingDraw[id] = operationId;
        emit RiskObserved(id, operationId, epoch);
    }

    function clearRecoveredRisk(bytes32 id) external nonReentrant {
        Agreement storage a = agreements[id];
        bytes32 operationId = pendingDraw[id];
        if (a.state != State.Active || operationId == bytes32(0)) revert InvalidState();
        if (
            _riskSatisfied(a.terms)
                && ILocalMarket(a.terms.market).debt(a.terms.borrower) >= a.terms.autonomousRepayment
        ) revert InvalidExecution();
        delete pendingDraw[id];
        emit RiskCleared(id, operationId);
    }

    function _riskSatisfied(Terms storage t) private view returns (bool) {
        ILocalMarket market = ILocalMarket(t.market);
        return market.isDistressed(t.borrower) && market.health(t.borrower) <= t.maxHealth;
    }

    /// @notice Local fixture execution. Signed terms specify risk threshold and exact repayment.
    function executePending(bytes32 id, bytes32 operationId, uint256 amount) external nonReentrant {
        Agreement storage a = agreements[id];
        Terms storage t = a.terms;
        uint64 now_ = checkedTimestamp(block.timestamp);
        if (
            a.state != State.Active || now_ >= t.drawDeadline || operationId == bytes32(0)
                || pendingDraw[id] != operationId || completedDraw[operationId]
        ) revert InvalidState();
        _validateDraw(id, a, amount, now_);
        _repayMarket(t, a.reservationId, amount);
        principal[id] = amount;
        drawTimestamp[id] = now_;
        lastAccrued[id] = now_;
        completedDraw[operationId] = true;
        delete pendingDraw[id];
        a.state = State.Drawn;
        emit DrawExecuted(id, operationId, amount, now_);
    }

    function _validateDraw(bytes32 id, Agreement storage a, uint256 amount, uint256 now_) private view {
        Terms storage t = a.terms;
        if (!ILocalCollateralVerifier(localCollateralVerifier).verify(id, t.lotId, t.borrower, t.collateralAmount)) {
            revert InvalidCollateral();
        }
        (uint256 value, uint256 updatedAt) = ILocalCollateralOracle(localOracle).valueUSDC(t.collateralAmount);
        if (value == 0 || updatedAt == 0 || updatedAt > now_ || now_ - updatedAt > MAX_PRICE_AGE) {
            revert InvalidPrice();
        }
        uint256 limit = value / 10000 * t.ltvBps + (value % 10000) * t.ltvBps / 10000;
        ILocalMarket market = ILocalMarket(t.market);
        ILocalAdapter adapter = ILocalAdapter(localAdapter);
        if (
            t.debtor != t.borrower || market.asset() != asset || adapter.asset() != asset
                || adapter.market() != t.market || !_riskSatisfied(t)
        ) revert InvalidExecution();
        (address lender, bytes32 agreementId_, uint256 reserved, ReservationState state) =
            CreditLiquidityVault(vault).reservations(a.reservationId);
        if (
            lender != t.lender || agreementId_ != id || state != ReservationState.Reserved
                || amount != t.autonomousRepayment || amount > MAX_PRINCIPAL || amount > reserved || amount > t.cap
                || amount > limit
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

    /// @notice Fractional carry uses denominator 630720000, exactly 10000 * 365 days / 500.
    function debtPreview(bytes32 id)
        public
        view
        returns (uint256 outstandingPrincipal, uint256 interest, uint256 totalPayable)
    {
        outstandingPrincipal = principal[id];
        uint256 remainder;
        (interest, remainder) = _previewInterest(id);
        totalPayable = outstandingPrincipal + interest + (remainder == 0 ? 0 : 1);
    }

    function accrueInterest(bytes32 id) external nonReentrant {
        State state = agreements[id].state;
        if (state != State.Drawn && state != State.Defaulted) revert InvalidState();
        _accrue(id);
    }

    function repay(bytes32 id, uint256 amount, uint256 paymentNonce) external nonReentrant {
        Agreement storage a = agreements[id];
        if (a.state != State.Drawn && a.state != State.Defaulted) revert InvalidState();
        if (amount == 0) revert InvalidRepayment();
        bytes32 paymentId =
            keccak256(abi.encode("REPAYMENT_V1", block.chainid, address(this), id, msg.sender, paymentNonce));
        if (CreditLiquidityVault(vault).repaymentUsed(paymentId)) revert InvalidRepayment();
        _accrue(id);
        uint256 p = principal[id];
        uint256 interest = accruedInterest[id];
        uint256 remainder = interestRemainder[id];
        uint256 payableTotal = p + interest + (remainder == 0 ? 0 : 1);
        if (amount > payableTotal) revert InvalidRepayment();
        if (amount == payableTotal && remainder != 0) {
            interest += 1;
            totalInterestAccrued[id] += 1;
            interestRemainder[id] = 0;
        }
        uint256 interestPaid = amount < interest ? amount : interest;
        uint256 principalPaid = amount - interestPaid;
        accruedInterest[id] = interest - interestPaid;
        principal[id] = p - principalPaid;
        totalInterestPaid[id] += interestPaid;
        totalPrincipalPaid[id] += principalPaid;
        // If principal is extinguished one unit short of payoff, crystallize the carry as interest.
        if (principal[id] == 0 && interestRemainder[id] != 0) {
            accruedInterest[id] += 1;
            totalInterestAccrued[id] += 1;
            interestRemainder[id] = 0;
        }
        if (principal[id] == 0 && accruedInterest[id] == 0) a.state = State.Closed;
        CreditLiquidityVault(vault).creditRepayment(a.reservationId, paymentId, msg.sender, amount);
        emit DebtRepaid(id, paymentId, msg.sender, interestPaid, principalPaid);
        if (a.state == State.Closed) emit AgreementClosed(id);
    }

    function markDefault(bytes32 id) external nonReentrant {
        Agreement storage a = agreements[id];
        uint64 now_ = checkedTimestamp(block.timestamp);
        if (a.state != State.Drawn || uint256(now_) < uint256(a.terms.maturity) + uint256(a.terms.grace)) {
            revert InvalidState();
        }
        _accrue(id);
        if (principal[id] == 0 && accruedInterest[id] == 0) revert InvalidState();
        a.state = State.Defaulted;
        emit AgreementDefaulted(id);
    }

    function _accrue(bytes32 id) private {
        uint64 now_ = checkedTimestamp(block.timestamp);
        (uint256 interest, uint256 remainder) = _previewInterestAt(id, now_);
        uint256 delta = interest - accruedInterest[id];
        accruedInterest[id] = interest;
        interestRemainder[id] = remainder;
        totalInterestAccrued[id] += delta;
        lastAccrued[id] = now_;
        emit InterestAccrued(id, delta, remainder);
    }

    function _previewInterest(bytes32 id) private view returns (uint256 interest, uint256 remainder) {
        return _previewInterestAt(id, checkedTimestamp(block.timestamp));
    }

    function _previewInterestAt(bytes32 id, uint64 now_) private view returns (uint256 interest, uint256 remainder) {
        interest = accruedInterest[id];
        remainder = interestRemainder[id];
        uint64 last = lastAccrued[id];
        if (now_ < last) revert InvalidTimestamp();
        uint256 p = principal[id];
        if (p == 0) return (interest, remainder);
        uint256 elapsed = uint256(now_ - last);
        uint256 denominator = INTEREST_DENOMINATOR;
        // Decompose both operands to avoid overflowing an intermediate product when the quotient fits.
        uint256 delta = (p / denominator) * elapsed + (p % denominator) * (elapsed / denominator);
        uint256 tail = (p % denominator) * (elapsed % denominator) + remainder;
        delta += tail / denominator;
        remainder = tail % denominator;
        interest += delta;
    }

    function activate(bytes32 id) external nonReentrant {
        Agreement storage agreement = agreements[id];
        Terms storage terms = agreement.terms;
        uint64 now_ = checkedTimestamp(block.timestamp);
        if (agreement.state != State.Draft || now_ >= terms.drawDeadline) revert InvalidState();
        if (!ILocalCollateralVerifier(localCollateralVerifier)
                .verify(id, terms.lotId, terms.borrower, terms.collateralAmount)) revert InvalidCollateral();
        (uint256 value, uint256 updatedAt) = ILocalCollateralOracle(localOracle).valueUSDC(terms.collateralAmount);
        if (value == 0 || updatedAt == 0 || updatedAt > now_ || now_ - updatedAt > MAX_PRICE_AGE) {
            revert InvalidPrice();
        }
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
        if (checkedTimestamp(block.timestamp) < agreement.terms.drawDeadline) revert InvalidState();
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
