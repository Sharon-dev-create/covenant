// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {CreditExecutionTest} from "./CreditExecution.t.sol";
import {CreditManager} from "../src/CreditManager.sol";
import {LocalCollateralFixture, LocalOracleFixture, LocalLendingMarket} from "./mocks/LocalCreditFixtures.sol";

/// @dev Extreme local dependencies are deliberately mocked; not a claim about a live USDC supply.
contract CreditArithmeticBoundaryTest is CreditExecutionTest {
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

    function testExtremeValidDrawCanBecomeUnpayableWhenClaimExceedsUint256() public {
        uint256 p = type(uint256).max / 2;
        CreditManager.Terms memory t = terms;
        t.cap = p;
        t.autonomousRepayment = p;
        t.borrowerNonce = 900;
        t.lenderNonce = 901;
        t.lotId = keccak256(abi.encode("LOT_V1", t.collateralChainId, t.collateralVault, manager.agreementId(t)));
        bytes32 digest = manager.digest(t);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xA11CE, digest);
        bytes memory bs = abi.encodePacked(r, s, v);
        (v, r, s) = vm.sign(0xB0B, digest);
        bytes32 loan = manager.register(t, bs, abi.encodePacked(r, s, v));
        token.mint(lender, p);
        vm.prank(lender);
        token.approve(address(vault), p);
        vm.prank(lender);
        vault.deposit(p);
        vm.prank(lender);
        vault.setCommitment(loan, p);
        collateral.set(loan, t.lotId, borrower, 1 ether);
        vm.mockCall(
            address(oracle),
            abi.encodeCall(LocalOracleFixture.valueUSDC, (1 ether)),
            abi.encode(type(uint256).max, block.timestamp)
        );
        manager.activate(loan);
        market.setPosition(borrower, p, 0);
        vm.mockCall(address(market), abi.encodeCall(LocalLendingMarket.isDistressed, (borrower)), abi.encode(true));
        vm.mockCall(address(market), abi.encodeCall(LocalLendingMarket.health, (borrower)), abi.encode(1e18));
        bytes32 operation = manager.observeRisk(loan);
        manager.executePending(loan, operation, p);
        assert(manager.principal(loan) == p);
        uint256 drawTime = block.timestamp;
        vm.warp(drawTime + 630720000);
        (uint256 principal_, uint256 interest, uint256 total) = manager.debtPreview(loan);
        assert(principal_ == p && interest == p && total == type(uint256).max - 1);
        vm.warp(drawTime + 630720001);
        vm.expectRevert();
        manager.debtPreview(loan);
        vm.prank(borrower);
        vm.expectRevert();
        manager.repay(loan, 1, 123);
        assert(manager.principal(loan) == p && manager.accruedInterest(loan) == 0);
    }
}
