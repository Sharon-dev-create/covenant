// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {CreditLiquidityVault} from "../src/CreditLiquidityVault.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {Vm} from "./Vaults.t.sol";
import {
    InvalidState,
    Unauthorized,
    InexactTransfer,
    InvalidIdentifier,
    InvalidAddress,
    InvalidAmount,
    TransferFailed,
    ReentrantCall,
    ReservationState
} from "../src/ProtocolTypes.sol";

contract CreditLiquidityVaultTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address private constant LENDER = address(0xA);
    address private constant PAYER = address(0xB);
    bytes32 private constant AGREEMENT = bytes32(uint256(1));
    bytes32 private constant PAYMENT = bytes32(uint256(2));
    MockUSDC private token;
    CreditLiquidityVault private vault;
    bytes32 private reservation;

    function setUp() public {
        token = new MockUSDC();
        vault = new CreditLiquidityVault(token, address(this), address(this));
        token.mint(LENDER, 100);
        vm.prank(LENDER);
        token.approve(address(vault), 100);
        vm.prank(LENDER);
        vault.deposit(100);
        vm.prank(LENDER);
        vault.setCommitment(AGREEMENT, 80);
        reservation = vault.reserve(AGREEMENT, LENDER, 80);
        vault.consume(reservation, 60);
        token.mint(PAYER, 50);
        vm.prank(PAYER);
        token.approve(address(vault), 50);
    }

    function testMeasuredCreditAndReplay() public {
        token.mint(address(vault), 7);
        vault.creditRepayment(reservation, PAYMENT, PAYER, 20);
        assert(vault.free(LENDER) == 60 && vault.totalFree() == 60 && vault.surplus() == 7);
        assert(token.balanceOf(PAYER) == 30 && vault.repaymentUsed(PAYMENT));
        vm.expectRevert(InvalidState.selector);
        vault.creditRepayment(reservation, PAYMENT, PAYER, 20);
        vm.prank(PAYER);
        vm.expectRevert(Unauthorized.selector);
        vault.creditRepayment(reservation, bytes32(uint256(3)), PAYER, 1);
    }

    function testFeeTransferRollsBackPaymentIdAndBalances() public {
        token.configure(false, true, address(0));
        vm.expectRevert(InexactTransfer.selector);
        vault.creditRepayment(reservation, PAYMENT, PAYER, 20);
        assert(!vault.repaymentUsed(PAYMENT) && vault.free(LENDER) == 40);
        assert(token.balanceOf(PAYER) == 50);
        token.configure(false, false, address(0));
        vault.creditRepayment(reservation, PAYMENT, PAYER, 20);
        assert(vault.free(LENDER) == 60);
    }

    function testRejectsInvalidInputsAndReservations() public {
        vm.expectRevert(InvalidIdentifier.selector);
        vault.creditRepayment(bytes32(0), PAYMENT, PAYER, 1);
        vm.expectRevert(InvalidIdentifier.selector);
        vault.creditRepayment(reservation, bytes32(0), PAYER, 1);
        vm.expectRevert(InvalidAddress.selector);
        vault.creditRepayment(reservation, PAYMENT, address(0), 1);
        vm.expectRevert(InvalidAddress.selector);
        vault.creditRepayment(reservation, PAYMENT, address(vault), 1);
        vm.expectRevert(InvalidAmount.selector);
        vault.creditRepayment(reservation, PAYMENT, PAYER, 0);
        vm.expectRevert(InvalidState.selector);
        vault.creditRepayment(bytes32(uint256(999)), PAYMENT, PAYER, 1);

        bytes32 activeAgreement = bytes32(uint256(12));
        vm.prank(LENDER);
        vault.setCommitment(activeAgreement, 5);
        bytes32 active = vault.reserve(activeAgreement, LENDER, 5);
        vm.expectRevert(InvalidState.selector);
        vault.creditRepayment(active, PAYMENT, PAYER, 1);
        vault.cancel(active);
        vm.expectRevert(InvalidState.selector);
        vault.creditRepayment(active, PAYMENT, PAYER, 1);
        assert(!vault.repaymentUsed(PAYMENT));
    }

    function testBindsCreditsToOriginalLenderAndGloballyRejectsReplay() public {
        address secondLender = address(0xC);
        bytes32 secondAgreement = bytes32(uint256(3));
        token.mint(secondLender, 100);
        vm.prank(secondLender);
        token.approve(address(vault), 100);
        vm.prank(secondLender);
        vault.deposit(100);
        vm.prank(secondLender);
        vault.setCommitment(secondAgreement, 40);
        bytes32 second = vault.reserve(secondAgreement, secondLender, 40);
        vault.consume(second, 30);
        (address owner, bytes32 agreement, uint256 amount, ReservationState state) = vault.reservations(second);
        assert(
            owner == secondLender && agreement == secondAgreement && amount == 0 && state == ReservationState.Consumed
        );
        vault.creditRepayment(second, PAYMENT, PAYER, 20);
        assert(vault.free(secondLender) == 90 && vault.free(LENDER) == 40);
        vm.expectRevert(InvalidState.selector);
        vault.creditRepayment(reservation, PAYMENT, PAYER, 1);
        assert(vault.totalFree() == 130 && token.balanceOf(address(vault)) == 130);
    }

    function testFalseAndMalformedTokenReturnsRollbackAndCanRetry() public {
        token.configure(true, false, address(0));
        vm.expectRevert(TransferFailed.selector);
        vault.creditRepayment(reservation, PAYMENT, PAYER, 20);
        token.configure(false, false, address(0));
        token.setMalformedReturn(true);
        vm.expectRevert(TransferFailed.selector);
        vault.creditRepayment(reservation, PAYMENT, PAYER, 20);
        assert(!vault.repaymentUsed(PAYMENT) && token.balanceOf(PAYER) == 50 && vault.free(LENDER) == 40);
        token.setMalformedReturn(false);
        vault.creditRepayment(reservation, PAYMENT, PAYER, 20);
        assert(vault.free(LENDER) == 60);
    }

    function testInsufficientAllowanceAndBalanceRollback() public {
        vm.prank(PAYER);
        token.approve(address(vault), 0);
        vm.expectRevert(TransferFailed.selector);
        vault.creditRepayment(reservation, PAYMENT, PAYER, 1);
        vm.prank(PAYER);
        token.approve(address(vault), 100);
        vm.expectRevert(TransferFailed.selector);
        vault.creditRepayment(reservation, PAYMENT, PAYER, 51);
        assert(!vault.repaymentUsed(PAYMENT) && vault.free(LENDER) == 40 && vault.totalFree() == 40);
    }

    function testCrossFunctionReentrancyIsRejected() public {
        token.configure(false, false, address(vault));
        vault.creditRepayment(reservation, PAYMENT, PAYER, 20);
        assert(!token.reentrySucceeded() && token.reentryError() == ReentrantCall.selector);
        assert(vault.free(LENDER) == 60 && token.balanceOf(address(vault)) == 60);
    }

    function testFuzzCashConservation(uint8 firstSeed, uint8 donationSeed) public {
        uint256 first = uint256(firstSeed) % 50 + 1;
        uint256 donation = donationSeed;
        token.mint(address(vault), donation);
        vault.creditRepayment(reservation, PAYMENT, PAYER, first);
        assert(vault.totalFree() == 40 + first && vault.reserved(LENDER) == 0);
        assert(token.balanceOf(address(vault)) == vault.totalFree() + vault.totalReserved() + donation);
        assert(vault.surplus() == donation);
    }
}
