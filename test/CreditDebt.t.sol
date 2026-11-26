// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {CreditExecutionTest} from "./CreditExecution.t.sol";
import {CreditManager} from "../src/CreditManager.sol";
import {TransferFailed, InexactTransfer, ReentrantCall} from "../src/ProtocolTypes.sol";

contract CreditDebtTest is CreditExecutionTest {
    function _draw() private {
        vm.prank(borrower);
        manager.executePending(id, op, 200e6);
    }

    function _fund(address payer, uint256 amount) private {
        token.mint(payer, amount);
        vm.prank(payer);
        token.approve(address(vault), amount);
    }

    function testInterestPreviewBeforeDrawAndRepeatedAccrual() public {
        (uint256 p, uint256 i, uint256 total) = manager.debtPreview(id);
        assert(p == 0 && i == 0 && total == 0);
        _draw();
        vm.warp(block.timestamp + 365 days);
        (p, i, total) = manager.debtPreview(id);
        assert(p == 200e6 && i == 10e6 && total == 210e6);
        manager.accrueInterest(id);
        manager.accrueInterest(id);
        assert(manager.accruedInterest(id) == 10e6 && manager.totalInterestAccrued(id) == 10e6);
    }

    function testInterestFirstPartialAndFurtherAccrual() public {
        _draw();
        _fund(borrower, 250e6);
        vm.warp(block.timestamp + 365 days);
        vm.prank(borrower);
        manager.repay(id, 5e6, 1);
        assert(manager.principal(id) == 200e6 && manager.accruedInterest(id) == 5e6);
        vm.prank(borrower);
        manager.repay(id, 55e6, 2);
        assert(manager.principal(id) == 150e6 && manager.accruedInterest(id) == 0);
        assert(manager.totalInterestPaid(id) == 10e6 && manager.totalPrincipalPaid(id) == 50e6);
        assert(vault.free(lender) == 460e6);
        vm.warp(block.timestamp + 365 days);
        (uint256 p, uint256 i, uint256 total) = manager.debtPreview(id);
        assert(p == 150e6 && i == 7500000 && total == 157500000);
    }

    function testFractionalCarryAndOneUnitShortOfFullPayoff() public {
        _draw();
        _fund(borrower, 200e6 + 1);
        vm.warp(block.timestamp + 1);
        (uint256 p, uint256 i, uint256 total) = manager.debtPreview(id);
        assert(p == 200e6 && i == 0 && total == 200e6 + 1);
        vm.prank(borrower);
        manager.repay(id, 200e6, 1);
        assert(manager.principal(id) == 0 && manager.accruedInterest(id) == 1 && manager.interestRemainder(id) == 0);
        vm.warp(block.timestamp + 365 days);
        (p, i, total) = manager.debtPreview(id);
        assert(p == 0 && i == 1 && total == 1);
        vm.prank(borrower);
        manager.repay(id, 1, 2);
        (, CreditManager.State state,) = manager.agreement(id);
        assert(state == CreditManager.State.Closed && manager.totalInterestPaid(id) == 1);
    }

    function testSplitAccrualMatchesContinuous() public {
        _draw();
        uint256 start = block.timestamp;
        vm.warp(start + 1);
        manager.accrueInterest(id);
        vm.warp(start + 2);
        manager.accrueInterest(id);
        vm.warp(start + 10);
        (, uint256 interest, uint256 total) = manager.debtPreview(id);
        assert(interest == (200e6 * 10) / manager.INTEREST_DENOMINATOR());
        assert(total == 200e6 + interest + 1);
        manager.accrueInterest(id);
        assert(manager.interestRemainder(id) == (200e6 * 10) % manager.INTEREST_DENOMINATOR());
    }

    function testFuzzAccrualMatchesExactRational(uint32 first, uint32 second) public {
        _draw();
        uint256 start = block.timestamp;
        vm.warp(start + first);
        manager.accrueInterest(id);
        vm.warp(start + uint256(first) + uint256(second));
        (uint256 p, uint256 interest, uint256 total) = manager.debtPreview(id);
        uint256 numerator = 200e6 * (uint256(first) + uint256(second));
        uint256 expected = numerator / manager.INTEREST_DENOMINATOR();
        uint256 remainder = numerator % manager.INTEREST_DENOMINATOR();
        assert(p == 200e6 && interest == expected && total == p + expected + (remainder == 0 ? 0 : 1));
        manager.accrueInterest(id);
        assert(manager.interestRemainder(id) == remainder && manager.totalInterestAccrued(id) == expected);
    }

    function testDefaultCureAndCancellationGuards() public {
        _draw();
        _fund(borrower, 250e6);
        vm.expectRevert(CreditManager.InvalidState.selector);
        manager.markDefault(id);
        vm.prank(borrower);
        vm.expectRevert(CreditManager.InvalidState.selector);
        manager.cancelUnused(id);
        vm.warp(uint256(terms.maturity) + uint256(terms.grace));
        manager.markDefault(id);
        (, CreditManager.State state,) = manager.agreement(id);
        assert(state == CreditManager.State.Defaulted);
        vm.prank(borrower);
        manager.repay(id, 10e6, 1);
        assert(manager.principal(id) > 0);
        (,, uint256 total) = manager.debtPreview(id);
        vm.prank(borrower);
        manager.repay(id, total, 2);
        (, state,) = manager.agreement(id);
        assert(state == CreditManager.State.Closed);
        vm.prank(borrower);
        vm.expectRevert(CreditManager.InvalidState.selector);
        manager.repay(id, 1, 3);
    }

    function testRepaymentFailureRollbackReplayAndNoThirdPartyCollection() public {
        _draw();
        _fund(borrower, 200e6);
        vm.prank(borrower);
        vm.expectRevert(CreditManager.InvalidRepayment.selector);
        manager.repay(id, 0, 1);
        vm.prank(borrower);
        vm.expectRevert(CreditManager.InvalidRepayment.selector);
        manager.repay(id, 200e6 + 1, 1);
        vm.prank(address(0xBEEF));
        vm.expectRevert(TransferFailed.selector);
        manager.repay(id, 10e6, 1);
        assert(token.balanceOf(borrower) == 200e6 && manager.principal(id) == 200e6);
        token.configure(false, true, address(0));
        vm.prank(borrower);
        vm.expectRevert(InexactTransfer.selector);
        manager.repay(id, 10e6, 1);
        assert(manager.principal(id) == 200e6 && vault.free(lender) == 400e6);
        token.configure(false, false, address(0));
        vm.prank(borrower);
        manager.repay(id, 10e6, 1);
        vm.prank(borrower);
        vm.expectRevert(CreditManager.InvalidRepayment.selector);
        manager.repay(id, 10e6, 1);
        assert(manager.principal(id) == 190e6 && vault.free(lender) == 410e6);
    }

    function testMalformedReentrantAndDonationAccounting() public {
        _draw();
        _fund(borrower, 200e6);
        token.mint(address(vault), 7);
        token.setMalformedReturn(true);
        vm.prank(borrower);
        vm.expectRevert(TransferFailed.selector);
        manager.repay(id, 10e6, 1);
        token.setMalformedReturn(false);
        token.configure(false, false, address(vault));
        vm.prank(borrower);
        manager.repay(id, 10e6, 1);
        assert(!token.reentrySucceeded() && token.reentryError() == ReentrantCall.selector);
        assert(vault.surplus() == 7 && token.balanceOf(address(vault)) == vault.totalFree() + vault.totalReserved() + 7);
        assert(manager.principal(id) == 190e6);
    }

    function testSecondBorrowerAndLenderCannotReceiveFirstRepayment() public {
        _draw();
        address secondBorrower = vm.addr(0xCAFE);
        address secondLender = vm.addr(0xD00D);
        CreditManager.Terms memory second = terms;
        second.borrower = secondBorrower;
        second.debtor = secondBorrower;
        second.lender = secondLender;
        second.borrowerNonce = 42;
        second.lenderNonce = 43;
        second.lotId = keccak256(
            abi.encode("LOT_V1", second.collateralChainId, second.collateralVault, manager.agreementId(second))
        );
        bytes32 signed = manager.digest(second);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xCAFE, signed);
        bytes memory b = abi.encodePacked(r, s, v);
        (v, r, s) = vm.sign(0xD00D, signed);
        bytes32 secondId = manager.register(second, b, abi.encodePacked(r, s, v));
        token.mint(secondLender, 600e6);
        vm.prank(secondLender);
        token.approve(address(vault), 600e6);
        vm.prank(secondLender);
        vault.deposit(600e6);
        vm.prank(secondLender);
        vault.setCommitment(secondId, 500e6);
        collateral.set(secondId, second.lotId, secondBorrower, 1 ether);
        manager.activate(secondId);
        market.setPosition(secondBorrower, 800e6, 840e6);
        bytes32 secondOp = manager.observeRisk(secondId);
        vm.prank(secondBorrower);
        manager.executePending(secondId, secondOp, 200e6);
        _fund(borrower, 50e6);
        vm.prank(borrower);
        manager.repay(id, 50e6, 123);
        assert(manager.principal(id) == 150e6 && manager.principal(secondId) == 200e6);
        assert(vault.free(lender) == 450e6 && vault.free(secondLender) == 400e6);
        assert(token.balanceOf(address(vault)) == vault.totalFree() + vault.totalReserved() + vault.surplus());
    }
}
