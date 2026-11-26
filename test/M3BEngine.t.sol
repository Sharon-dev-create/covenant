// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {CreditManagerCore} from "../src/CreditManagerCore.sol";
import {CreditManager} from "../src/CreditManager.sol";
import {TestnetCreditManager} from "../src/TestnetCreditManager.sol";
import {LocalCreditFactory} from "../src/LocalCreditFactory.sol";
import {TestnetCreditFactory} from "../src/TestnetCreditFactory.sol";
import {CreditLiquidityVault} from "../src/CreditLiquidityVault.sol";
import {IERC20} from "../src/interfaces/IVaults.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {
    LocalCollateralFixture,
    LocalOracleFixture,
    LocalLendingMarket,
    LocalRepaymentAdapter
} from "./mocks/LocalCreditFixtures.sol";

interface M3Vm {
    function addr(uint256) external returns (address);
    function sign(uint256, bytes32) external returns (uint8, bytes32, bytes32);
    function prank(address) external;
    function warp(uint256) external;
    function chainId(uint256) external;
    function expectRevert() external;
    function expectRevert(bytes4) external;
    function getNonce(address) external view returns (uint64);
    function computeCreateAddress(address, uint256) external pure returns (address);
}

contract EighteenDecimalToken {
    function decimals() external pure returns (uint8) {
        return 18;
    }
}

/// @dev Isolated failure injection; not the production factory path.
contract TestnetAtomicHarness {
    M3Vm constant vm = M3Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address public recordedManager;
    address public recordedVault;

    function deploy(address asset, address verifier, address oracle, address adapter, bool inject) external {
        uint256 nonce = vm.getNonce(address(this));
        address predictedManager = vm.computeCreateAddress(address(this), nonce);
        address predictedVault = vm.computeCreateAddress(address(this), nonce + 1);
        TestnetCreditManager m = new TestnetCreditManager(predictedVault, asset, verifier, oracle, adapter);
        require(address(m) == predictedManager && address(m).code.length != 0);
        CreditLiquidityVault v =
            new CreditLiquidityVault(IERC20(asset), predictedManager, inject ? address(1) : predictedManager);
        require(address(v) == predictedVault && v.consumer() == predictedManager, "binding verification failed");
        recordedManager = address(m);
        recordedVault = address(v);
    }
}

contract M3BEngineTest {
    M3Vm constant vm = M3Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 constant BK = 0xA11CE;
    uint256 constant LK = 0xB0B;
    MockUSDC token;
    LocalCollateralFixture collateral;
    LocalOracleFixture oracle;
    LocalLendingMarket market;
    LocalRepaymentAdapter adapter;
    CreditManagerCore manager;
    CreditLiquidityVault vault;
    address borrower;
    address lender;

    function _setup(uint256 chain) private {
        vm.chainId(chain);
        vm.warp(10000);
        borrower = vm.addr(BK);
        lender = vm.addr(LK);
        token = new MockUSDC();
        collateral = new LocalCollateralFixture();
        oracle = new LocalOracleFixture();
        market = new LocalLendingMarket(address(token));
        adapter = new LocalRepaymentAdapter(address(token), address(market));
        address m;
        address v;
        if (chain == 31337) {
            LocalCreditFactory f =
                new LocalCreditFactory(address(token), address(collateral), address(oracle), address(adapter));
            m = f.manager();
            v = f.vault();
            assert(m == f.predict(address(f), 1) && v == f.predict(address(f), 2));
        } else {
            TestnetCreditFactory f =
                new TestnetCreditFactory(address(token), address(collateral), address(oracle), address(adapter));
            m = f.manager();
            v = f.vault();
            assert(m == f.predict(address(f), 1) && v == f.predict(address(f), 2));
        }
        manager = CreditManagerCore(m);
        vault = CreditLiquidityVault(v);
        assert(manager.vault() == v && manager.asset() == address(token));
        assert(manager.localCollateralVerifier() == address(collateral) && manager.localOracle() == address(oracle));
        assert(manager.localAdapter() == address(adapter) && vault.manager() == m && vault.consumer() == m);
        adapter.configure(false, false, false, m, bytes32(0), bytes32(0));
        token.mint(lender, 1000e6);
        vm.prank(lender);
        token.approve(v, 1000e6);
        vm.prank(lender);
        vault.deposit(1000e6);
    }

    function _terms(uint256 nonce, uint256 cap, uint256 draw) private view returns (CreditManagerCore.Terms memory t) {
        t = CreditManagerCore.Terms(
            borrower,
            lender,
            address(0x55),
            1301,
            bytes32(0),
            1 ether,
            address(market),
            borrower,
            bytes32(uint256(1)),
            cap,
            draw,
            11e17,
            nonce,
            nonce,
            uint64(block.timestamp + 1 days),
            uint64(block.timestamp + 2 days),
            uint64(block.timestamp + 3 days),
            1 days,
            5000
        );
        t.lotId = keccak256(abi.encode("LOT_V1", t.collateralChainId, t.collateralVault, manager.agreementId(t)));
    }

    function _register(CreditManagerCore.Terms memory t) private returns (bytes32 id) {
        bytes32 d = manager.digest(t);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(BK, d);
        bytes memory a = abi.encodePacked(r, s, v);
        (v, r, s) = vm.sign(LK, d);
        id = manager.register(t, a, abi.encodePacked(r, s, v));
    }

    function _reject(CreditManagerCore.Terms memory t) private {
        bytes32 d = manager.digest(t);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(BK, d);
        bytes memory a = abi.encodePacked(r, s, v);
        (v, r, s) = vm.sign(LK, d);
        bytes memory b = abi.encodePacked(r, s, v);
        vm.expectRevert(CreditManagerCore.InvalidTerms.selector);
        manager.register(t, a, b);
    }

    function _prepare(uint256 nonce, uint256 cap, uint256 draw) private returns (bytes32 id, bytes32 op) {
        CreditManagerCore.Terms memory t = _terms(nonce, cap, draw);
        id = _register(t);
        collateral.set(id, t.lotId, borrower, 1 ether);
        oracle.set(2000e6, block.timestamp);
        vm.prank(lender);
        vault.setCommitment(id, cap);
        manager.activate(id);
        market.setPosition(borrower, 800e6, 840e6);
        op = manager.observeRisk(id);
    }

    function _repay(bytes32 id) private {
        (,, uint256 amount) = manager.debtPreview(id);
        token.mint(borrower, amount);
        vm.prank(borrower);
        token.approve(address(vault), amount);
        vm.prank(borrower);
        manager.repay(id, amount, 1);
    }

    function _scenario(uint256 chain) private returns (bytes32) {
        _setup(chain);
        (bytes32 id, bytes32 op) = _prepare(1, 300e6, 200e6);
        manager.executePending(id, op, 200e6);
        assert(vault.free(lender) == 800e6 && manager.principal(id) == 200e6 && market.debt(borrower) == 600e6);
        vm.warp(block.timestamp + 365 days);
        manager.markDefault(id);
        (uint256 p, uint256 interest, uint256 total) = manager.debtPreview(id);
        assert(p == 200e6 && interest == 10e6 && total == 210e6);
        _repay(id);
        (, CreditManagerCore.State state,) = manager.agreement(id);
        assert(state == CreditManagerCore.State.Closed && vault.free(lender) == 1010e6);
        return keccak256(
            abi.encode(
                p, interest, total, vault.free(lender), manager.totalPrincipalPaid(id), manager.totalInterestPaid(id)
            )
        );
    }

    function testLocalAndTestnetFinancialParity() public {
        bytes32 local = _scenario(31337);
        bytes32 testnet = _scenario(84532);
        assert(local == testnet);
    }

    function testTestnetLifetimeLimitFailureAndRepayment() public {
        _setup(84532);
        (bytes32 id, bytes32 op) = _prepare(1, 300e6, 200e6);
        market.configure(true, false);
        vm.expectRevert();
        manager.executePending(id, op, 200e6);
        assert(TestnetCreditManager(address(manager)).lifetimePrincipalCreated() == 0 && manager.pendingDraw(id) == op);
        market.configure(false, false);
        manager.executePending(id, op, 200e6);
        assert(TestnetCreditManager(address(manager)).lifetimePrincipalCreated() == 200e6);
        _repay(id);
        assert(TestnetCreditManager(address(manager)).lifetimePrincipalCreated() == 200e6);
        (bytes32 second, bytes32 op2) = _prepare(2, 100e6, 100e6);
        manager.executePending(second, op2, 100e6);
        assert(TestnetCreditManager(address(manager)).lifetimePrincipalCreated() == 300e6);
        (bytes32 third, bytes32 op3) = _prepare(3, 1, 1);
        uint256 beforeCash = token.balanceOf(address(vault));
        vm.expectRevert(CreditManagerCore.InvalidExecution.selector);
        manager.executePending(third, op3, 1);
        assert(
            TestnetCreditManager(address(manager)).lifetimePrincipalCreated() == 300e6 && manager.principal(third) == 0
        );
        assert(
            manager.pendingDraw(third) == op3 && token.balanceOf(address(vault)) == beforeCash
                && market.debt(borrower) == 800e6
        );
    }

    function testTestnetAgreementBoundsAndNonceRollback() public {
        _setup(84532);
        CreditManagerCore.Terms memory t = _terms(10, 300e6 + 1, 300e6);
        _reject(t);
        assert(!manager.usedBorrowerNonce(borrower, 10) && !manager.usedLenderNonce(lender, 10));
        t = _terms(10, 300e6, 300e6 + 1);
        _reject(t);
        assert(!manager.usedBorrowerNonce(borrower, 10) && !manager.usedLenderNonce(lender, 10));
        t = _terms(10, 300e6, 300e6);
        bytes32 id = _register(t);
        assert(manager.usedBorrowerNonce(borrower, 10) && manager.usedLenderNonce(lender, 10));
        assert(id != bytes32(0));
    }

    function testTestnetDomainAndNonceReplayProtection() public {
        _setup(84532);
        CreditManagerCore.Terms memory t = _terms(31, 300e6, 200e6);
        bytes32 d = manager.digest(t);
        (uint8 v, bytes32 r, bytes32 sigS) = vm.sign(BK, d);
        bytes memory bs = abi.encodePacked(r, sigS, v);
        (v, r, sigS) = vm.sign(LK, d);
        bytes memory ls = abi.encodePacked(r, sigS, v);
        vm.chainId(31337);
        assert(manager.digest(t) != d);
        bytes32 originalLot = t.lotId;
        t.lotId = keccak256(abi.encode("LOT_V1", t.collateralChainId, t.collateralVault, manager.agreementId(t)));
        vm.expectRevert(CreditManagerCore.InvalidAuthorization.selector);
        manager.register(t, bs, ls);
        assert(!manager.usedBorrowerNonce(borrower, 31) && !manager.usedLenderNonce(lender, 31));
        vm.chainId(84532);
        t.lotId = originalLot;
        manager.register(t, bs, ls);
        vm.expectRevert(CreditManagerCore.InvalidState.selector);
        manager.register(t, bs, ls);
        TestnetCreditFactory second =
            new TestnetCreditFactory(address(token), address(collateral), address(oracle), address(adapter));
        CreditManagerCore other = CreditManagerCore(second.manager());
        assert(other.digest(t) != d);
        // Rebind the lot for the other domain, but retain the old signatures.
        t.lotId = keccak256(abi.encode("LOT_V1", t.collateralChainId, t.collateralVault, other.agreementId(t)));
        vm.expectRevert(CreditManagerCore.InvalidAuthorization.selector);
        other.register(t, bs, ls);
        assert(!other.usedBorrowerNonce(borrower, 31) && !other.usedLenderNonce(lender, 31));
    }

    function testCancellationAndDefaultDoNotReplenishLifetime() public {
        _setup(84532);
        (bytes32 id, bytes32 op) = _prepare(1, 300e6, 200e6);
        manager.executePending(id, op, 200e6);
        CreditManagerCore.Terms memory t = _terms(2, 100e6, 100e6);
        bytes32 cancelled = _register(t);
        vm.prank(borrower);
        manager.cancelUnused(cancelled);
        assert(TestnetCreditManager(address(manager)).lifetimePrincipalCreated() == 200e6);
        vm.warp(block.timestamp + 5 days);
        manager.markDefault(id);
        assert(TestnetCreditManager(address(manager)).lifetimePrincipalCreated() == 200e6);
        _repay(id);
        assert(TestnetCreditManager(address(manager)).lifetimePrincipalCreated() == 200e6);
    }

    function testTestnetAtomicFactoryPatternRollbackHarness() public {
        _setup(84532);
        TestnetAtomicHarness h = new TestnetAtomicHarness();
        uint64 beforeNonce = vm.getNonce(address(h));
        address expectedManager = vm.computeCreateAddress(address(h), beforeNonce);
        address expectedVault = vm.computeCreateAddress(address(h), beforeNonce + 1);
        (bool ok,) = address(h)
            .call(
                abi.encodeCall(h.deploy, (address(token), address(collateral), address(oracle), address(adapter), true))
            );
        assert(!ok && expectedManager.code.length == 0 && expectedVault.code.length == 0);
        assert(
            vm.getNonce(address(h)) == beforeNonce && h.recordedManager() == address(0)
                && h.recordedVault() == address(0)
        );
        h.deploy(address(token), address(collateral), address(oracle), address(adapter), false);
        assert(h.recordedManager() == expectedManager && h.recordedVault() == expectedVault);
        assert(expectedManager.code.length != 0 && expectedVault.code.length != 0);
    }

    function testMaximumSingleDrawAndSixDecimalAssetRestriction() public {
        _setup(84532);
        (bytes32 id, bytes32 op) = _prepare(1, 300e6, 300e6);
        manager.executePending(id, op, 300e6);
        assert(
            manager.principal(id) == 300e6 && TestnetCreditManager(address(manager)).lifetimePrincipalCreated() == 300e6
        );
        EighteenDecimalToken wrongAsset = new EighteenDecimalToken();
        vm.expectRevert(CreditManagerCore.InvalidTerms.selector);
        new TestnetCreditFactory(address(wrongAsset), address(collateral), address(oracle), address(adapter));
    }

    function testChainGuardsAndFactoryDependencies() public {
        _setup(84532);
        vm.expectRevert();
        new LocalCreditFactory(address(token), address(collateral), address(oracle), address(adapter));
        vm.expectRevert();
        new TestnetCreditFactory(address(0), address(collateral), address(oracle), address(adapter));
        vm.expectRevert();
        new TestnetCreditFactory(address(token), address(collateral), address(oracle), address(0x123));
        vm.expectRevert();
        new TestnetCreditManager(address(1), address(token), address(collateral), address(oracle), address(0x123));
        vm.chainId(31337);
        vm.expectRevert();
        new TestnetCreditFactory(address(token), address(collateral), address(oracle), address(adapter));
        vm.chainId(1);
        vm.expectRevert();
        new CreditManager(address(1), address(token), address(collateral), address(oracle), address(adapter));
        vm.expectRevert();
        new TestnetCreditManager(address(1), address(token), address(collateral), address(oracle), address(adapter));
    }
}
