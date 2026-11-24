// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {CollateralVault} from "../src/CollateralVault.sol";
import {LiquidityVault} from "../src/LiquidityVault.sol";
import {
    CollateralState,
    ReservationState,
    InvalidIdentifier,
    Unauthorized,
    InvalidAmount,
    InvalidState,
    InsufficientLiquidity,
    TransferFailed,
    InexactTransfer,
    ReentrantCall,
    InvalidAddress
} from "../src/ProtocolTypes.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

interface Vm {
    function chainId(uint256) external;
    function deal(address, uint256) external;
    function prank(address) external;
    function expectRevert(bytes4) external;
}

contract VaultsTest {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address internal constant ALICE = address(0xA);
    address internal constant BOB = address(0xB);
    address internal constant CONSUMER = address(0xC);
    bytes32 internal constant FIRST = bytes32(uint256(1));
    bytes32 internal constant SECOND = bytes32(uint256(2));

    CollateralVault internal collateral;
    LiquidityVault internal liquidity;
    MockUSDC internal token;

    function setUp() public {
        token = new MockUSDC();
        collateral = new CollateralVault(address(this));
        liquidity = new LiquidityVault(token, address(this), CONSUMER);
        vm.deal(ALICE, 5 ether);
        vm.deal(BOB, 5 ether);
    }

    function testLocksDistinctAgreementsAndAccountsForForcedEther() public {
        collateral.bind(FIRST, ALICE, 1 ether);
        collateral.bind(SECOND, BOB, 2 ether);
        vm.prank(ALICE);
        bytes32 first = collateral.lock{value: 1 ether}(FIRST);
        vm.prank(BOB);
        bytes32 second = collateral.lock{value: 2 ether}(SECOND);
        (address borrower, bytes32 agreement, uint256 amount, CollateralState state) = collateral.positions(first);
        assert(first != second && borrower == ALICE && agreement == FIRST);
        assert(amount == 1 ether && state == CollateralState.Locked);
        vm.deal(address(collateral), 4 ether);
        assert(collateral.totalLocked() == 3 ether && collateral.totalReleased() == 0);
        assert(collateral.surplus() == 1 ether);
    }

    function testRejectsInvalidLocksAndUnauthorizedBinding() public {
        vm.expectRevert(InvalidIdentifier.selector);
        collateral.bind(bytes32(0), ALICE, 1 ether);
        vm.expectRevert(InvalidAddress.selector);
        collateral.bind(FIRST, address(0), 1 ether);
        vm.prank(ALICE);
        vm.expectRevert(Unauthorized.selector);
        collateral.bind(FIRST, ALICE, 1 ether);
        collateral.bind(FIRST, ALICE, 1 ether);
        vm.expectRevert(InvalidState.selector);
        collateral.bind(FIRST, BOB, 1 ether);
        vm.prank(BOB);
        vm.expectRevert(Unauthorized.selector);
        collateral.lock{value: 1 ether}(FIRST);
        vm.prank(ALICE);
        vm.expectRevert(InvalidAmount.selector);
        collateral.lock(FIRST);
        vm.prank(ALICE);
        vm.expectRevert(InvalidAmount.selector);
        collateral.lock{value: 2 ether}(FIRST);
        vm.prank(ALICE);
        collateral.lock{value: 1 ether}(FIRST);
        vm.prank(ALICE);
        vm.expectRevert(InvalidState.selector);
        collateral.lock{value: 1 ether}(FIRST);
        assert(address(collateral).balance == 1 ether && collateral.totalLocked() == 1 ether);
    }

    function testCollateralHasNoReleasePathForBorrowerOrThirdParty() public {
        collateral.bind(FIRST, ALICE, 1 ether);
        vm.prank(ALICE);
        bytes32 id = collateral.lock{value: 1 ether}(FIRST);
        vm.prank(ALICE);
        (bool borrowerClaim,) = address(collateral).call(abi.encodeWithSignature("claim(bytes32,address)", id, ALICE));
        vm.prank(BOB);
        (bool thirdPartyRelease,) = address(collateral).call(abi.encodeWithSignature("release(bytes32)", id));
        assert(!borrowerClaim && !thirdPartyRelease && address(collateral).balance == 1 ether);
    }

    function testMultipleLendersAndCommittedCashCannotBeWithdrawn() public {
        _deposit(ALICE, 100);
        _deposit(BOB, 50);
        bytes32 first = _reserve(ALICE, FIRST, 80);
        bytes32 second = _reserve(BOB, SECOND, 50);
        vm.prank(ALICE);
        vm.expectRevert(InsufficientLiquidity.selector);
        liquidity.withdraw(21);
        vm.prank(ALICE);
        liquidity.withdraw(15);
        assert(first != second && liquidity.free(ALICE) == 5 && liquidity.free(BOB) == 0);
        assert(liquidity.reserved(ALICE) == 80 && liquidity.reserved(BOB) == 50);
        _reconcile(135);
    }

    function testCancellationRestoresCashOnce() public {
        _deposit(ALICE, 100);
        bytes32 id = _reserve(ALICE, FIRST, 70);
        liquidity.cancel(id);
        assert(liquidity.free(ALICE) == 100 && liquidity.reserved(ALICE) == 0);
        (,,, ReservationState state) = liquidity.reservations(id);
        assert(state == ReservationState.Returned);
        vm.expectRevert(InvalidState.selector);
        liquidity.cancel(id);
        vm.expectRevert(InvalidState.selector);
        liquidity.consume(id, 1);
        vm.expectRevert(InvalidState.selector);
        liquidity.reserve(FIRST, ALICE, 70);
        _reconcile(100);
    }

    function testZeroAmountsInvalidIdsAndAuthorization() public {
        vm.expectRevert(InvalidAmount.selector);
        liquidity.deposit(0);
        vm.expectRevert(InvalidAmount.selector);
        liquidity.withdraw(0);
        vm.expectRevert(InvalidIdentifier.selector);
        liquidity.cancel(bytes32(0));
        vm.expectRevert(InvalidIdentifier.selector);
        liquidity.reserve(bytes32(0), ALICE, 1);
        _deposit(ALICE, 100);
        vm.expectRevert(Unauthorized.selector);
        liquidity.reserve(FIRST, ALICE, 100);
        vm.prank(ALICE);
        liquidity.setCommitment(FIRST, 101);
        vm.expectRevert(InsufficientLiquidity.selector);
        liquidity.reserve(FIRST, ALICE, 101);
        vm.prank(BOB);
        vm.expectRevert(Unauthorized.selector);
        liquidity.reserve(FIRST, ALICE, 100);
        vm.expectRevert(Unauthorized.selector);
        liquidity.reserve(FIRST, ALICE, 102);
        bytes32 id = liquidity.reserve(FIRST, ALICE, 100);
        vm.expectRevert(InvalidState.selector);
        liquidity.reserve(FIRST, ALICE, 1);
        vm.prank(ALICE);
        vm.expectRevert(Unauthorized.selector);
        liquidity.cancel(id);
        vm.prank(BOB);
        vm.expectRevert(Unauthorized.selector);
        liquidity.consume(id, 1);
        vm.expectRevert(InvalidAmount.selector);
        liquidity.consume(id, 101);
        _reconcile(100);
    }

    function testTransferFailuresAndFeesRollbackAndSurplusCannotBeWithdrawn() public {
        _deposit(ALICE, 100);
        bytes32 id = _reserve(ALICE, FIRST, 80);
        token.mint(address(liquidity), 11);
        assert(liquidity.surplus() == 11);
        token.configure(true, false, address(0));
        vm.expectRevert(TransferFailed.selector);
        liquidity.consume(id, 40);
        vm.expectRevert(TransferFailed.selector);
        vm.prank(ALICE);
        liquidity.withdraw(10);
        token.configure(false, true, address(0));
        vm.expectRevert(InexactTransfer.selector);
        liquidity.consume(id, 40);
        token.mint(ALICE, 10);
        vm.prank(ALICE);
        token.approve(address(liquidity), 10);
        vm.prank(ALICE);
        vm.expectRevert(InexactTransfer.selector);
        liquidity.deposit(10);
        assert(liquidity.free(ALICE) == 20 && liquidity.reserved(ALICE) == 80);
        assert(token.balanceOf(CONSUMER) == 0 && token.balanceOf(ALICE) == 10);
        _reconcile(111);
    }

    function testCrossFunctionReentrancyFailsWithoutInterruptingValidDeposit() public {
        token.configure(false, false, address(liquidity));
        _deposit(ALICE, 100);
        assert(!token.reentrySucceeded() && token.reentryError() == ReentrantCall.selector);
        _reconcile(100);
    }

    function testFuzzConsumptionIsNonRevolving(uint128 amountSeed, uint128 spendSeed) public {
        uint256 amount = uint256(amountSeed) + 1;
        uint256 spend = uint256(spendSeed) % amount + 1;
        _deposit(ALICE, amount);
        bytes32 id = _reserve(ALICE, FIRST, amount);
        liquidity.consume(id, spend);
        assert(liquidity.free(ALICE) == amount - spend && liquidity.reserved(ALICE) == 0);
        assert(token.balanceOf(CONSUMER) == spend);
        vm.expectRevert(InvalidState.selector);
        liquidity.consume(id, spend);
        vm.expectRevert(InvalidState.selector);
        liquidity.cancel(id);
        _reconcile(amount - spend);
    }

    function testIdentifiersRemainStableAcrossChainIdChange() public {
        collateral.bind(FIRST, ALICE, 1 ether);
        vm.prank(ALICE);
        bytes32 position = collateral.lock{value: 1 ether}(FIRST);
        _deposit(ALICE, 2);
        bytes32 reservation = _reserve(ALICE, FIRST, 1);

        vm.chainId(block.chainid + 1);
        assert(collateral.positionId(FIRST) == position);
        assert(liquidity.reservationId(FIRST) == reservation);

        vm.prank(ALICE);
        vm.expectRevert(InvalidState.selector);
        collateral.lock{value: 1 ether}(FIRST);
        vm.prank(ALICE);
        vm.expectRevert(InvalidState.selector);
        liquidity.setCommitment(FIRST, 1);
    }

    function testMalformedTokenReturnRollsBackTransfer() public {
        _deposit(ALICE, 100);
        bytes32 id = _reserve(ALICE, FIRST, 80);
        token.setMalformedReturn(true);

        vm.expectRevert(TransferFailed.selector);
        liquidity.consume(id, 80);

        (,, uint256 amount, ReservationState state) = liquidity.reservations(id);
        assert(amount == 80 && state == ReservationState.Reserved);
        assert(liquidity.free(ALICE) == 20 && liquidity.reserved(ALICE) == 80);
        assert(token.balanceOf(CONSUMER) == 0);
        _reconcile(100);
    }

    function testSurplusAndOtherLenderCashCannotFundWithdrawal() public {
        _deposit(ALICE, 100);
        token.mint(BOB, 11);
        vm.prank(BOB);
        assert(token.transfer(address(liquidity), 11));
        vm.prank(BOB);
        vm.expectRevert(InsufficientLiquidity.selector);
        liquidity.withdraw(1);
        vm.prank(ALICE);
        liquidity.withdraw(100);
        assert(liquidity.surplus() == 11);
        _reconcile(11);
    }

    function testFullWidthExactConsumption() public {
        uint256 amount = type(uint256).max;
        _deposit(ALICE, amount);
        bytes32 id = _reserve(ALICE, FIRST, amount);
        liquidity.consume(id, amount);
        assert(token.balanceOf(CONSUMER) == amount && liquidity.reserved(ALICE) == 0);
        _reconcile(0);
    }

    function _deposit(address lender, uint256 amount) private {
        token.mint(lender, amount);
        vm.prank(lender);
        token.approve(address(liquidity), amount);
        vm.prank(lender);
        liquidity.deposit(amount);
    }

    function _reserve(address lender, bytes32 agreement, uint256 amount) private returns (bytes32) {
        vm.prank(lender);
        liquidity.setCommitment(agreement, amount);
        return liquidity.reserve(agreement, lender, amount);
    }

    function _reconcile(uint256 amount) private view {
        assert(liquidity.totalFree() + liquidity.totalReserved() + liquidity.surplus() == amount);
        assert(token.balanceOf(address(liquidity)) == amount);
    }
}
