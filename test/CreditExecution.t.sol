// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {CreditManager} from "../src/CreditManager.sol";
import {CreditLiquidityVault} from "../src/CreditLiquidityVault.sol";
import {LocalCreditFactory} from "../src/LocalCreditFactory.sol";
import {ReservationState} from "../src/ProtocolTypes.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {
    LocalCollateralFixture,
    LocalOracleFixture,
    LocalLendingMarket,
    LocalRepaymentAdapter
} from "./mocks/LocalCreditFixtures.sol";

interface ExecutionVm {
    function addr(uint256) external returns (address);
    function sign(uint256, bytes32) external returns (uint8, bytes32, bytes32);
    function prank(address) external;
    function warp(uint256) external;
    function expectRevert() external;
    function expectRevert(bytes4) external;
    function mockCall(address, bytes calldata, bytes calldata) external;
    function clearMockedCalls() external;
}

contract LocalExecutor {
    function execute(CreditManager manager, bytes32 agreementId, bytes32 operation, uint256 amount) external {
        manager.executePending(agreementId, operation, amount);
    }
}

contract CreditExecutionTest {
    ExecutionVm constant vm = ExecutionVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    MockUSDC token;
    LocalCollateralFixture collateral;
    LocalOracleFixture oracle;
    LocalLendingMarket market;
    LocalRepaymentAdapter adapter;
    CreditManager manager;
    CreditLiquidityVault vault;
    CreditManager.Terms terms;
    bytes32 id;
    bytes32 op;
    address borrower;
    address lender;

    function setUp() public {
        vm.warp(10000);
        borrower = vm.addr(0xA11CE);
        lender = vm.addr(0xB0B);
        token = new MockUSDC();
        collateral = new LocalCollateralFixture();
        oracle = new LocalOracleFixture();
        market = new LocalLendingMarket(address(token));
        adapter = new LocalRepaymentAdapter(address(token), address(market));
        LocalCreditFactory factory =
            new LocalCreditFactory(address(token), address(collateral), address(oracle), address(adapter));
        manager = CreditManager(factory.manager());
        vault = CreditLiquidityVault(factory.vault());
        terms = CreditManager.Terms(
            borrower,
            lender,
            address(0x55),
            1301,
            bytes32(0),
            1 ether,
            address(market),
            borrower,
            bytes32(uint256(1)),
            500e6,
            200e6,
            11e17,
            1,
            10,
            11000,
            12000,
            13000,
            100,
            5000
        );
        terms.lotId =
            keccak256(abi.encode("LOT_V1", terms.collateralChainId, terms.collateralVault, manager.agreementId(terms)));
        bytes32 digest = manager.digest(terms);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xA11CE, digest);
        bytes memory b = abi.encodePacked(r, s, v);
        (v, r, s) = vm.sign(0xB0B, digest);
        bytes memory l = abi.encodePacked(r, s, v);
        id = manager.register(terms, b, l);
        token.mint(lender, 600e6);
        vm.prank(lender);
        token.approve(address(vault), 600e6);
        vm.prank(lender);
        vault.deposit(600e6);
        vm.prank(lender);
        vault.setCommitment(id, 500e6);
        collateral.set(id, terms.lotId, borrower, 1 ether);
        oracle.set(2000e6, block.timestamp);
        manager.activate(id);
        market.setPosition(borrower, 800e6, 840e6);
        op = manager.observeRisk(id);
        adapter.configure(false, false, false, address(manager), id, op);
    }

    function testExactDrawAndReplay() public {
        token.mint(address(manager), 7);
        token.mint(address(adapter), 9);
        vm.prank(borrower);
        manager.executePending(id, op, 200e6);
        assert(
            manager.principal(id) == 200e6 && manager.drawTimestamp(id) == block.timestamp && manager.completedDraw(op)
        );
        assert(manager.pendingDraw(id) == bytes32(0) && market.debt(borrower) == 600e6);
        assert(vault.free(lender) == 400e6 && vault.reserved(lender) == 0);
        assert(token.balanceOf(address(manager)) == 7 && token.balanceOf(address(adapter)) == 9);
        assert(
            token.allowance(address(manager), address(adapter)) == 0
                && token.allowance(address(adapter), address(market)) == 0
        );
        vm.prank(borrower);
        vm.expectRevert(CreditManager.InvalidState.selector);
        manager.executePending(id, op, 1);
    }

    function testNonBorrowerExecutorAndCompetingExecutor() public {
        LocalExecutor executor = new LocalExecutor();
        executor.execute(manager, id, op, 200e6);
        assert(manager.principal(id) == 200e6 && market.debt(borrower) == 600e6);
        assert(vault.free(lender) == 400e6 && vault.reserved(lender) == 0);
        vm.prank(address(0xBEEF));
        vm.expectRevert(CreditManager.InvalidState.selector);
        manager.executePending(id, op, 200e6);
    }

    function testRecoveredPositionClearsPendingAndCanReobserve() public {
        market.setPosition(borrower, 800e6, 1000e6);
        vm.prank(address(0xBEEF));
        vm.expectRevert(CreditManager.InvalidExecution.selector);
        manager.executePending(id, op, 200e6);
        _unchanged();
        bytes32 old = op;
        vm.prank(address(0xBEEF));
        manager.clearRecoveredRisk(id);
        assert(manager.pendingDraw(id) == bytes32(0));
        vm.expectRevert(CreditManager.InvalidExecution.selector);
        manager.observeRisk(id);
        market.setPosition(borrower, 800e6, 840e6);
        bytes32 next = manager.observeRisk(id);
        assert(next != old);
        vm.prank(address(0xBEEF));
        vm.expectRevert(CreditManager.InvalidState.selector);
        manager.executePending(id, old, 200e6);
        vm.prank(address(0xBEEF));
        manager.executePending(id, next, 200e6);
        assert(manager.principal(id) == 200e6);
    }

    function testArbitraryCallerCannotManipulateOrOverwriteRisk() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        market.setPosition(borrower, 800e6, 840e6);
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        oracle.set(1e30, block.timestamp);
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        collateral.set(id, terms.lotId, borrower, 100 ether);
        vm.prank(address(0xBEEF));
        vm.expectRevert(CreditManager.InvalidState.selector);
        manager.observeRisk(id);
        vm.prank(address(0xBEEF));
        vm.expectRevert(CreditManager.InvalidExecution.selector);
        manager.clearRecoveredRisk(id);
        vm.prank(address(0xBEEF));
        vm.expectRevert(CreditManager.InvalidExecution.selector);
        manager.executePending(id, op, 199e6);
        _unchanged();
    }

    function testExecutionFailuresRollbackAndRetry() public {
        market.configure(true, false);
        vm.prank(borrower);
        vm.expectRevert();
        manager.executePending(id, op, 200e6);
        _unchanged();
        market.configure(false, true);
        vm.prank(borrower);
        vm.expectRevert();
        manager.executePending(id, op, 200e6);
        _unchanged();
        market.configure(false, false);
        adapter.configure(true, false, false, address(manager), id, op);
        vm.prank(borrower);
        vm.expectRevert();
        manager.executePending(id, op, 200e6);
        _unchanged();
        adapter.configure(false, true, false, address(manager), id, op);
        vm.prank(borrower);
        vm.expectRevert();
        manager.executePending(id, op, 200e6);
        _unchanged();
        adapter.configure(false, false, true, address(manager), id, op);
        vm.prank(borrower);
        manager.executePending(id, op, 200e6);
        assert(!adapter.reentrySucceeded() && manager.principal(id) == 200e6);
    }

    function testEligibilityAndPrice() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(CreditManager.InvalidExecution.selector);
        manager.executePending(id, op, 1);
        vm.prank(borrower);
        vm.expectRevert(CreditManager.InvalidState.selector);
        manager.executePending(id, bytes32(uint256(2)), 200e6);
        vm.prank(borrower);
        vm.expectRevert(CreditManager.InvalidExecution.selector);
        manager.executePending(id, op, 501e6);
        oracle.set(100e6, block.timestamp);
        vm.prank(borrower);
        vm.expectRevert(CreditManager.InvalidExecution.selector);
        manager.executePending(id, op, 200e6);
        oracle.set(2000e6, block.timestamp - 3601);
        vm.prank(borrower);
        vm.expectRevert(CreditManager.InvalidPrice.selector);
        manager.executePending(id, op, 200e6);
        _unchanged();
    }

    function testCollateralExpiryZeroAndTokenFailureRollback() public {
        vm.prank(borrower);
        vm.expectRevert(CreditManager.InvalidExecution.selector);
        manager.executePending(id, op, 0);
        collateral.set(id, terms.lotId, borrower, 2 ether);
        vm.prank(borrower);
        vm.expectRevert(CreditManager.InvalidCollateral.selector);
        manager.executePending(id, op, 200e6);
        collateral.set(id, terms.lotId, borrower, 1 ether);
        token.configure(true, false, address(0));
        vm.prank(borrower);
        vm.expectRevert();
        manager.executePending(id, op, 200e6);
        token.configure(false, false, address(0));
        _unchanged();
        vm.warp(terms.drawDeadline);
        vm.prank(borrower);
        vm.expectRevert(CreditManager.InvalidState.selector);
        manager.executePending(id, op, 200e6);
    }

    function testRiskRequiresDistressAndCannotDuplicatePending() public {
        vm.expectRevert(CreditManager.InvalidState.selector);
        manager.observeRisk(id);
        vm.prank(borrower);
        manager.cancelUnused(id);
        assert(manager.pendingDraw(id) == bytes32(0));
        vm.expectRevert(CreditManager.InvalidState.selector);
        manager.observeRisk(id);
    }

    function testIncorrectBindingAndDebtRevalidation() public {
        vm.mockCall(address(adapter), abi.encodeWithSignature("market()"), abi.encode(address(0xBAD)));
        vm.prank(borrower);
        vm.expectRevert(CreditManager.InvalidExecution.selector);
        manager.executePending(id, op, 200e6);
        vm.clearMockedCalls();
        vm.mockCall(address(market), abi.encodeWithSignature("asset()"), abi.encode(address(0xBAD)));
        vm.prank(borrower);
        vm.expectRevert(CreditManager.InvalidExecution.selector);
        manager.executePending(id, op, 200e6);
        vm.clearMockedCalls();
        market.setPosition(borrower, 100e6, 105e6);
        vm.prank(borrower);
        vm.expectRevert(CreditManager.InvalidExecution.selector);
        manager.executePending(id, op, 200e6);
        assert(manager.pendingDraw(id) == op && manager.principal(id) == 0);
    }

    function testUnexpectedResidualAndAllowanceRollBack() public {
        token.mint(address(adapter), 1);
        adapter.configurePost(true, false);
        vm.prank(borrower);
        vm.expectRevert(CreditManager.InvalidExecution.selector);
        manager.executePending(id, op, 200e6);
        _unchanged();
        adapter.configurePost(false, true);
        vm.prank(borrower);
        vm.expectRevert(CreditManager.InvalidExecution.selector);
        manager.executePending(id, op, 200e6);
        _unchanged();
        assert(token.balanceOf(address(adapter)) == 1);
    }

    function _unchanged() private view {
        (,, uint256 amount, ReservationState state) = vault.reservations(vault.reservationId(id));
        assert(
            state == ReservationState.Reserved && amount == 500e6 && vault.reserved(lender) == 500e6
                && vault.free(lender) == 100e6
        );
        assert(
            manager.principal(id) == 0 && manager.pendingDraw(id) == op && !manager.completedDraw(op)
                && market.debt(borrower) == 800e6
        );
        assert(
            token.allowance(address(manager), address(adapter)) == 0
                && token.allowance(address(adapter), address(market)) == 0
        );
    }
}
