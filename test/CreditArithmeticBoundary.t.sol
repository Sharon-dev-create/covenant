// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {CreditExecutionTest} from "./CreditExecution.t.sol";
import {CreditManager} from "../src/CreditManager.sol";
import {LocalOracleFixture, LocalLendingMarket} from "./mocks/LocalCreditFixtures.sol";

/// @dev Extreme local dependencies are deliberately mocked; not a claim about a live USDC supply.
contract CreditArithmeticBoundaryTest is CreditExecutionTest {
    uint256 private constant D = 630720000;
    uint256 private constant UNIT = 1_000_000;

    function testCarryBoundaryAndFinalRoundingCannotRepeat() public {
        manager.executePending(id, op, 200e6);
        uint256 start = block.timestamp;
        manager.accrueInterest(id);
        assert(manager.accruedInterest(id) == 0 && manager.interestRemainder(id) == 0);
        vm.warp(start + 3);
        manager.accrueInterest(id);
        assert(manager.accruedInterest(id) == 0 && manager.interestRemainder(id) == 600e6);
        manager.accrueInterest(id);
        assert(manager.accruedInterest(id) == 0 && manager.interestRemainder(id) == 600e6);
        vm.warp(start + 4);
        manager.accrueInterest(id);
        assert(manager.accruedInterest(id) == 1 && manager.interestRemainder(id) == 169280000);
        token.mint(borrower, 200e6 + 2);
        vm.prank(borrower);
        token.approve(address(vault), 200e6 + 2);
        vm.prank(borrower);
        manager.repay(id, 200e6 + 1, 1);
        assert(manager.principal(id) == 0 && manager.accruedInterest(id) == 1 && manager.interestRemainder(id) == 0);
        vm.warp(block.timestamp + 365 days);
        (uint256 p, uint256 interest, uint256 total) = manager.debtPreview(id);
        assert(p == 0 && interest == 1 && total == 1);
        vm.prank(borrower);
        manager.repay(id, 1, 2);
        assert(manager.totalInterestAccrued(id) == 2 && manager.totalInterestPaid(id) == 2);
        vm.prank(borrower);
        vm.expectRevert();
        manager.repay(id, 1, 3);
        assert(manager.totalInterestPaid(id) == 2);
    }

    /// @dev Original reproduction: the extreme claim could exceed uint256 and block all repayment.
    /// It is now rejected at registration, before any nonce, reservation or principal exists.
    function testOriginalExtremeClaimIsRejectedBeforeDebtCreation() public {
        uint256 extreme = type(uint256).max / 2;
        CreditManager.Terms memory t = _envelopeTerms(extreme, extreme, 900);
        (bytes memory bs, bytes memory ls) = _sign(t);
        vm.expectRevert(CreditManager.InvalidTerms.selector);
        manager.register(t, bs, ls);

        bytes32 rejected = manager.agreementId(t);
        (, CreditManager.State state,) = manager.agreement(rejected);
        assert(state == CreditManager.State.Absent);
        (uint256 rp, uint256 ri, uint256 rt) = manager.debtPreview(rejected);
        assert(manager.principal(rejected) == 0 && rp == 0 && ri == 0 && rt == 0);
        assert(!manager.usedBorrowerNonce(borrower, 900) && !manager.usedLenderNonce(lender, 901));
        assert(manager.lotAgreement(t.lotId) == bytes32(0));
    }

    function testEnvelopeConstantsAndAssetDecimals() public view {
        assert(manager.MAX_COMMITMENT() == 1_000_000 * UNIT);
        assert(manager.MAX_PRINCIPAL() == 1_000_000 * UNIT);
        assert(manager.MAX_TERM() == 365 days);
        assert(manager.APR_BPS() == 500);
        assert(manager.INTEREST_DENOMINATOR() == D);
        assert(manager.MAX_ACCRUAL_SECONDS() == uint256(type(uint64).max));
        assert(manager.MAX_SUPPORTED_CLAIM() < type(uint256).max);
        assert(IExecutionToken(manager.asset()).decimals() == 6);
    }

    function testMaximumCommitmentAndPrincipalSupported() public {
        uint256 max = manager.MAX_COMMITMENT();
        (bytes32 loan,) = _fundAndDraw(max, max, 930);
        assert(manager.principal(loan) == max);
        assert(manager.drawTimestamp(loan) == uint64(block.timestamp));
        assert(manager.lastAccrued(loan) == uint64(block.timestamp));
        (uint256 initialPrincipal, uint256 initialInterest, uint256 initialTotal) = manager.debtPreview(loan);
        assert(initialPrincipal == max && initialInterest == 0 && initialTotal == max);

        vm.warp(block.timestamp + 365 days);
        (uint256 p, uint256 interest, uint256 total) = manager.debtPreview(loan);
        assert(p == max && interest == max / 20 && total == max + max / 20);
        assert(total <= manager.MAX_SUPPORTED_CLAIM());

        uint256 payoff = total;
        uint256 freeBefore = vault.free(lender);
        _fundPayer(borrower, payoff);
        vm.prank(borrower);
        manager.repay(loan, payoff, 1);
        (, CreditManager.State state,) = manager.agreement(loan);
        assert(state == CreditManager.State.Closed);
        assert(manager.principal(loan) == 0 && manager.accruedInterest(loan) == 0);
        assert(manager.totalPrincipalPaid(loan) == max && manager.totalInterestPaid(loan) == max / 20);
        assert(vault.free(lender) == freeBefore + payoff);
    }

    function testOneBaseUnitAboveEachFinancialLimitRejected() public {
        uint256 max = manager.MAX_COMMITMENT();

        CreditManager.Terms memory overCap = _envelopeTerms(max + 1, max + 1, 940);
        (bytes memory bs, bytes memory ls) = _sign(overCap);
        vm.expectRevert(CreditManager.InvalidTerms.selector);
        manager.register(overCap, bs, ls);
        assert(!manager.usedBorrowerNonce(borrower, 940) && !manager.usedLenderNonce(lender, 941));

        CreditManager.Terms memory overPrincipal = _envelopeTerms(max, max + 1, 942);
        (bs, ls) = _sign(overPrincipal);
        vm.expectRevert(CreditManager.InvalidTerms.selector);
        manager.register(overPrincipal, bs, ls);
        assert(!manager.usedBorrowerNonce(borrower, 942) && !manager.usedLenderNonce(lender, 943));

        (bytes32 loan, bytes32 operation) = _prepareLoan(max, max, 944);
        vm.prank(borrower);
        vm.expectRevert(CreditManager.InvalidExecution.selector);
        manager.executePending(loan, operation, max + 1);
        assert(manager.principal(loan) == 0 && manager.pendingDraw(loan) == operation);
        vm.prank(borrower);
        manager.executePending(loan, operation, max);
        vm.clearMockedCalls();
        assert(manager.principal(loan) == max);
    }

    function testMaximumAgreementDurationAndOneSecondBeyond() public {
        uint64 drawDeadline = uint64(block.timestamp + 1000);
        CreditManager.Terms memory accepted = terms;
        accepted.borrowerNonce = 950;
        accepted.lenderNonce = 951;
        accepted.consentDeadline = uint64(block.timestamp);
        accepted.drawDeadline = drawDeadline;
        accepted.maturity = uint64(uint256(drawDeadline) + uint256(manager.MAX_TERM()));
        accepted = _withLot(accepted);
        (bytes memory bs, bytes memory ls) = _sign(accepted);
        bytes32 loan = manager.register(accepted, bs, ls);
        (CreditManager.Terms memory stored,,) = manager.agreement(loan);
        assert(stored.maturity - stored.drawDeadline == 365 days);

        CreditManager.Terms memory rejected = accepted;
        rejected.borrowerNonce = 952;
        rejected.lenderNonce = 953;
        rejected.maturity = uint64(uint256(rejected.maturity) + 1);
        rejected = _withLot(rejected);
        (bs, ls) = _sign(rejected);
        vm.expectRevert(CreditManager.InvalidTerms.selector);
        manager.register(rejected, bs, ls);
        assert(!manager.usedBorrowerNonce(borrower, 952) && !manager.usedLenderNonce(lender, 953));
    }

    function testInvalidTimestampConversionsRevert() public {
        manager.executePending(id, op, 200e6);
        assert(manager.checkedTimestamp(uint256(type(uint64).max)) == type(uint64).max);
        vm.expectRevert(CreditManager.InvalidTimestamp.selector);
        manager.checkedTimestamp(uint256(type(uint64).max) + 1);

        uint64 recorded = manager.lastAccrued(id);
        vm.warp(uint256(recorded) - 1);
        vm.expectRevert(CreditManager.InvalidTimestamp.selector);
        manager.debtPreview(id);
        vm.expectRevert(CreditManager.InvalidTimestamp.selector);
        manager.accrueInterest(id);

        vm.warp(uint256(type(uint64).max) + 1);
        vm.expectRevert(CreditManager.InvalidTimestamp.selector);
        manager.debtPreview(id);
        vm.expectRevert(CreditManager.InvalidTimestamp.selector);
        manager.accrueInterest(id);
        vm.prank(borrower);
        vm.expectRevert(CreditManager.InvalidTimestamp.selector);
        manager.repay(id, 1, 77);
        assert(manager.principal(id) == 200e6 && manager.accruedInterest(id) == 0);
    }

    function testMaximumElapsedAccrualAndRepeatedCheckpoints() public {
        manager.executePending(id, op, 200e6);
        uint256 start = uint256(manager.drawTimestamp(id));
        uint256 at = manager.MAX_ACCRUAL_SECONDS() - 2;
        vm.warp(at);

        uint256 elapsed = at - start;
        (uint256 whole, uint256 carry) = _rational(200e6, elapsed, 0);
        (uint256 p, uint256 interest, uint256 total) = manager.debtPreview(id);
        assert(p == 200e6 && interest == whole && total == p + whole + (carry == 0 ? 0 : 1));
        assert(interest <= manager.MAX_SUPPORTED_INTEREST());

        manager.accrueInterest(id);
        manager.accrueInterest(id);
        assert(manager.accruedInterest(id) == whole && manager.interestRemainder(id) == carry);
        assert(manager.totalInterestAccrued(id) == whole && manager.lastAccrued(id) == uint64(at));

        vm.warp(at + 2);
        (uint256 nextWhole, uint256 nextCarry) = _rational(200e6, at + 2 - start, 0);
        (, interest,) = manager.debtPreview(id);
        assert(interest == nextWhole);
        manager.accrueInterest(id);
        assert(manager.accruedInterest(id) == nextWhole && manager.interestRemainder(id) == nextCarry);
        assert(manager.totalInterestAccrued(id) == nextWhole);
        assert(uint256(manager.lastAccrued(id)) == manager.MAX_ACCRUAL_SECONDS());
    }

    function testLargeInterestPartialAndFullRepaymentAfterExtendedDefault() public {
        manager.executePending(id, op, 200e6);
        vm.warp(uint256(terms.maturity) + uint256(terms.grace));
        manager.markDefault(id);
        (, CreditManager.State state,) = manager.agreement(id);
        assert(state == CreditManager.State.Defaulted);

        uint256 at = manager.MAX_ACCRUAL_SECONDS() - 1000;
        vm.warp(at);
        (uint256 p, uint256 interest, uint256 total) = manager.debtPreview(id);
        assert(p == 200e6 && interest > 1e12 && total == p + interest + 1);
        assert(total <= manager.MAX_SUPPORTED_CLAIM());
        (uint256 whole, uint256 carry) = _rational(200e6, at - uint256(manager.drawTimestamp(id)), 0);
        assert(interest == whole && carry != 0);

        uint256 part = interest / 2;
        _fundPayer(borrower, total + 10);
        vm.prank(borrower);
        manager.repay(id, part, 1);
        assert(manager.principal(id) == 200e6 && manager.accruedInterest(id) == interest - part);
        assert(manager.totalInterestPaid(id) == part && vault.free(lender) == 400e6 + part);
        (, state,) = manager.agreement(id);
        assert(state == CreditManager.State.Defaulted);

        vm.warp(at + 1);
        (,, uint256 payoff) = manager.debtPreview(id);
        vm.prank(borrower);
        manager.repay(id, payoff, 2);
        (, state,) = manager.agreement(id);
        assert(state == CreditManager.State.Closed);
        assert(manager.principal(id) == 0 && manager.accruedInterest(id) == 0 && manager.interestRemainder(id) == 0);
        assert(manager.totalPrincipalPaid(id) == 200e6);
        assert(manager.totalInterestPaid(id) > interest);
        assert(vault.free(lender) == 400e6 + part + payoff);
        vm.prank(borrower);
        vm.expectRevert(CreditManager.InvalidState.selector);
        manager.repay(id, 1, 3);
    }

    function testFractionalCarryAtMaximumPrincipal() public {
        uint256 max = manager.MAX_COMMITMENT();
        (bytes32 loan,) = _fundAndDraw(max, max, 960);
        uint256 start = uint256(manager.drawTimestamp(loan));

        uint256[] memory intervals = new uint256[](3);
        intervals[0] = D - 1;
        intervals[1] = D;
        intervals[2] = D + 1;
        for (uint256 i; i < intervals.length; i++) {
            vm.warp(start + intervals[i]);
            (uint256 whole, uint256 carry) = _rational(max, intervals[i], 0);
            (uint256 p, uint256 interest, uint256 total) = manager.debtPreview(loan);
            assert(p == max && interest == whole && total == max + whole + (carry == 0 ? 0 : 1));
            manager.accrueInterest(loan);
            manager.accrueInterest(loan);
            assert(manager.accruedInterest(loan) == whole && manager.interestRemainder(loan) == carry);
            assert(manager.totalInterestAccrued(loan) == whole);
        }
        assert(manager.interestRemainder(loan) > 0);
    }

    function testExactPayoffRoundingIsAppliedOnceAtMaximumScale() public {
        uint256 max = manager.MAX_COMMITMENT();
        (bytes32 loan,) = _fundAndDraw(max, max, 970);
        uint256 start = uint256(manager.drawTimestamp(loan));
        vm.warp(start + 3);

        (uint256 whole, uint256 carry) = _rational(max, 3, 0);
        assert(carry != 0);
        uint256 payoff = max + whole + 1;
        _fundPayer(borrower, payoff);
        vm.prank(borrower);
        manager.repay(loan, payoff - 1, 1);
        assert(manager.principal(loan) == 0 && manager.accruedInterest(loan) == 1);
        assert(manager.interestRemainder(loan) == 0 && manager.totalInterestAccrued(loan) == whole + 1);
        assert(manager.totalInterestPaid(loan) == whole);

        vm.warp(start + 365 days);
        (uint256 p, uint256 interest, uint256 total) = manager.debtPreview(loan);
        assert(p == 0 && interest == 1 && total == 1);
        vm.prank(borrower);
        manager.repay(loan, 1, 2);
        (, CreditManager.State state,) = manager.agreement(loan);
        assert(state == CreditManager.State.Closed);
        assert(manager.totalInterestAccrued(loan) == whole + 1 && manager.totalInterestPaid(loan) == whole + 1);
        vm.prank(borrower);
        vm.expectRevert(CreditManager.InvalidState.selector);
        manager.repay(loan, 1, 3);
        assert(manager.totalInterestPaid(loan) == whole + 1);
    }

    function testRegistrationFailurePreservesNoncesAndLiquidity() public {
        uint256 freeBefore = vault.free(lender);
        uint256 reservedBefore = vault.reserved(lender);
        uint256 cashBefore = token.balanceOf(address(vault));
        uint256 commitmentBefore = vault.commitments(lender, id);

        CreditManager.Terms memory overCap = _envelopeTerms(manager.MAX_COMMITMENT() + 1, manager.MAX_COMMITMENT(), 980);
        (bytes memory bs, bytes memory ls) = _sign(overCap);
        vm.expectRevert(CreditManager.InvalidTerms.selector);
        manager.register(overCap, bs, ls);

        assert(vault.free(lender) == freeBefore && vault.reserved(lender) == reservedBefore);
        assert(token.balanceOf(address(vault)) == cashBefore && vault.commitments(lender, id) == commitmentBefore);
        assert(!manager.usedBorrowerNonce(borrower, 980) && !manager.usedLenderNonce(lender, 981));

        uint64 deadline = uint64(block.timestamp + 1000);
        CreditManager.Terms memory tooLong = terms;
        tooLong.borrowerNonce = 982;
        tooLong.lenderNonce = 983;
        tooLong.drawDeadline = deadline;
        tooLong.maturity = uint64(uint256(deadline) + uint256(manager.MAX_TERM()) + 1);
        tooLong = _withLot(tooLong);
        (bs, ls) = _sign(tooLong);
        vm.expectRevert(CreditManager.InvalidTerms.selector);
        manager.register(tooLong, bs, ls);
        assert(!manager.usedBorrowerNonce(borrower, 982) && !manager.usedLenderNonce(lender, 983));
        assert(vault.free(lender) == freeBefore && vault.reserved(lender) == reservedBefore);
    }

    function testNormalValueFinancialBehaviourUnchanged() public {
        manager.executePending(id, op, 200e6);
        vm.warp(block.timestamp + 365 days);
        (uint256 p, uint256 interest, uint256 total) = manager.debtPreview(id);
        assert(p == 200e6 && interest == 10e6 && total == 210e6);
        _fundPayer(borrower, total);
        vm.prank(borrower);
        manager.repay(id, 5e6, 1);
        assert(manager.principal(id) == 200e6 && manager.accruedInterest(id) == 5e6);
        vm.prank(borrower);
        manager.repay(id, 205e6, 2);
        (, CreditManager.State state,) = manager.agreement(id);
        assert(state == CreditManager.State.Closed);
        assert(manager.totalInterestPaid(id) == 10e6 && manager.totalPrincipalPaid(id) == 200e6);
    }

    function _envelopeTerms(uint256 cap, uint256 repayment, uint256 nonce)
        private
        view
        returns (CreditManager.Terms memory t)
    {
        t = terms;
        t.cap = cap;
        t.autonomousRepayment = repayment;
        t.borrowerNonce = nonce;
        t.lenderNonce = nonce + 1;
        t = _withLot(t);
    }

    function _withLot(CreditManager.Terms memory t) private view returns (CreditManager.Terms memory) {
        t.lotId = keccak256(abi.encode("LOT_V1", t.collateralChainId, t.collateralVault, manager.agreementId(t)));
        return t;
    }

    function _sign(CreditManager.Terms memory t)
        private
        returns (bytes memory borrowerSignature, bytes memory lenderSignature)
    {
        bytes32 signed = manager.digest(t);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xA11CE, signed);
        borrowerSignature = abi.encodePacked(r, s, v);
        (v, r, s) = vm.sign(0xB0B, signed);
        lenderSignature = abi.encodePacked(r, s, v);
    }

    function _fundAndDraw(uint256 cap, uint256 repayment, uint256 nonce)
        private
        returns (bytes32 loan, bytes32 operation)
    {
        (loan, operation) = _prepareLoan(cap, repayment, nonce);
        vm.prank(borrower);
        manager.executePending(loan, operation, repayment);
        vm.clearMockedCalls();
    }

    function _prepareLoan(uint256 cap, uint256 repayment, uint256 nonce)
        private
        returns (bytes32 loan, bytes32 operation)
    {
        CreditManager.Terms memory t = _envelopeTerms(cap, repayment, nonce);
        (bytes memory bs, bytes memory ls) = _sign(t);
        loan = manager.register(t, bs, ls);
        token.mint(lender, cap);
        vm.prank(lender);
        token.approve(address(vault), cap);
        vm.prank(lender);
        vault.deposit(cap);
        vm.prank(lender);
        vault.setCommitment(loan, cap);
        collateral.set(loan, t.lotId, borrower, 1 ether);
        vm.mockCall(
            address(oracle),
            abi.encodeCall(LocalOracleFixture.valueUSDC, (1 ether)),
            abi.encode(cap * 2, block.timestamp)
        );
        manager.activate(loan);
        market.setPosition(borrower, repayment, (repayment * 105) / 100);
        vm.mockCall(address(market), abi.encodeCall(LocalLendingMarket.isDistressed, (borrower)), abi.encode(true));
        vm.mockCall(address(market), abi.encodeCall(LocalLendingMarket.health, (borrower)), abi.encode(105e16));
        operation = manager.observeRisk(loan);
    }

    function _fundPayer(address payer, uint256 amount) private {
        token.mint(payer, amount);
        vm.prank(payer);
        token.approve(address(vault), amount);
    }

    /// @dev Independent rational calculation: floor((principal * elapsed + carry) / D) and its remainder.
    function _rational(uint256 principal, uint256 elapsed, uint256 carry)
        private
        pure
        returns (uint256 whole, uint256 remainder)
    {
        uint256 tail = (principal % D) * (elapsed % D) + carry;
        whole = (principal / D) * elapsed + (principal % D) * (elapsed / D) + tail / D;
        remainder = tail % D;
    }
}

interface IExecutionToken {
    function decimals() external view returns (uint8);
}
