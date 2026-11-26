// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {CreditLiquidityVault} from "../src/CreditLiquidityVault.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {Vm} from "./Vaults.t.sol";
import {InvalidState, Unauthorized, InexactTransfer} from "../src/ProtocolTypes.sol";

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
}
