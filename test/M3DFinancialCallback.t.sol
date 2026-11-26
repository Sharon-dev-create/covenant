// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;
import {M3CDemoTest} from "./M3CDemo.t.sol";
import {CreditManagerCore} from "../src/CreditManagerCore.sol";
import {TestnetCreditManager} from "../src/TestnetCreditManager.sol";
import {CollateralAttestationVerifier} from "../src/demo/CollateralAttestationVerifier.sol";
import {DemoAdapter} from "../src/demo/DemoAdapter.sol";
import {DemoToken} from "../src/demo/DemoToken.sol";
import {DemoMarket} from "../src/demo/DemoMarket.sol";
import {IOmniReactive, IOmniSystem} from "../src/reactive/transport/IOmniTransport.sol";
import {MockOmniSystem} from "./Transport.t.sol";
import {FinancialTrigger, FinancialTriggerV1} from "../src/reactive/financial/FinancialTrigger.sol";
import {RiskSignalRegistry} from "../src/reactive/financial/RiskSignalRegistry.sol";
import {FinancialReactive} from "../src/reactive/financial/FinancialReactive.sol";
import {FinancialCallbackReceiver} from "../src/reactive/financial/FinancialCallbackReceiver.sol";

interface M3DVm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }
    function chainId(uint256) external;
    function etch(address, bytes calldata) external;
    function prank(address) external;
    function warp(uint256) external;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory);
    function expectRevert(bytes4) external;
    function expectRevert() external;
    function mockCallRevert(address, bytes calldata, bytes calldata) external;
    function mockCall(address, bytes calldata, bytes calldata) external;
    function clearMockedCalls() external;
}

contract M3DProxy {
    function deliver(address target, address reactive, bytes calldata payload) external {
        (bool ok, bytes memory result) = target.call(bytes.concat(payload[:4], abi.encode(reactive), payload[36:]));
        if (!ok) {
            assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
        }
    }
}

contract M3DFinancialCallbackTest is M3CDemoTest {
    M3DVm private constant vmd = M3DVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    RiskSignalRegistry registry;
    FinancialReactive reactiveContract;
    FinancialCallbackReceiver receiver;
    MockOmniSystem constant SYSTEM = MockOmniSystem(payable(FinancialTrigger.SYSTEM));
    M3DProxy constant PROXY = M3DProxy(FinancialTrigger.BASE_PROXY);

    function _attest() private {
        CollateralAttestationVerifier.CollateralLockAttestationV1 memory a =
            CollateralAttestationVerifier.CollateralLockAttestationV1(
                1301,
                address(source),
                84532,
                address(verifier),
                address(manager),
                100,
                bytes32(uint256(12)),
                bytes32(uint256(13)),
                0,
                id,
                terms.lotId,
                borrower,
                0.001 ether,
                manager.termsHash(terms),
                1,
                1,
                uint64(block.timestamp + 30 minutes)
            );
        bytes32 d = verifier.digest(a);
        bytes[] memory sigs = new bytes[](3);
        for (uint256 i; i < 3; i++) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(keys[i], d);
            sigs[i] = abi.encodePacked(r, s, v);
        }
        verifier.acceptLock(a, sigs);
    }

    function _setupIntegration() private {
        _attest();
        manager.activate(id);
        registry = new RiskSignalRegistry(address(manager), address(market));
        vmd.chainId(FinancialTrigger.LASNA);
        vmd.etch(FinancialTrigger.SYSTEM, address(new MockOmniSystem()).code);
        reactiveContract = new FinancialReactive(address(this));
        vmd.chainId(FinancialTrigger.BASE);
        vmd.etch(FinancialTrigger.BASE_PROXY, address(new M3DProxy()).code);
        receiver = new FinancialCallbackReceiver(address(reactiveContract), address(manager), address(registry));
        vmd.chainId(FinancialTrigger.LASNA);
        reactiveContract.configure(address(registry), address(manager), address(receiver), 2_000_000);
        assert(
            SYSTEM.subscription()
                == keccak256(
                    abi.encode(
                        address(reactiveContract),
                        FinancialTrigger.BASE,
                        address(registry),
                        uint256(FinancialTrigger.TOPIC),
                        FinancialTrigger.IGNORE,
                        FinancialTrigger.IGNORE,
                        uint256(uint160(address(manager)))
                    )
                )
        );
        vmd.chainId(FinancialTrigger.BASE);
    }

    function _signal() private returns (IOmniReactive.LogRecord memory entry, bytes32 triggerId) {
        vmd.recordLogs();
        uint64 generation = registry.signal(id);
        M3DVm.Log[] memory logs = vmd.getRecordedLogs();
        assert(logs.length == 1 && logs[0].emitter == address(registry));
        entry = IOmniReactive.LogRecord(
            FinancialTrigger.BASE,
            address(registry),
            uint256(logs[0].topics[0]),
            uint256(logs[0].topics[1]),
            uint256(logs[0].topics[2]),
            uint256(logs[0].topics[3]),
            logs[0].data,
            block.number,
            4,
            1,
            2,
            0
        );
        FinancialTriggerV1 memory t = FinancialTriggerV1(
            1, FinancialTrigger.BASE, address(registry), FinancialTrigger.BASE, address(manager), id, generation
        );
        triggerId = FinancialTrigger.id(address(reactiveContract), address(receiver), t);
    }

    function _request(IOmniReactive.LogRecord memory entry)
        private
        returns (IOmniSystem.CallbackConfiguration memory c)
    {
        vmd.chainId(FinancialTrigger.LASNA);
        vmd.prank(FinancialTrigger.SYSTEM);
        reactiveContract.react(entry);
        c = SYSTEM.lastRequest();
        assert(c.recipient == address(receiver) && c.chainId == FinancialTrigger.BASE);
        vmd.chainId(FinancialTrigger.BASE);
    }

    function _deliver(IOmniSystem.CallbackConfiguration memory c) private {
        PROXY.deliver(address(receiver), address(reactiveContract), c.payload);
    }

    function testEndToEndAuthenticatedFinancialExecutionAndRepayment() public {
        _setupIntegration();
        (IOmniReactive.LogRecord memory e, bytes32 trigger) = _signal();
        IOmniSystem.CallbackConfiguration memory c = _request(e);
        assert(manager.principal(id) == 0 && vault.reserved(lender) == 300e6);
        _deliver(c);
        (FinancialCallbackReceiver.Outcome outcome, bytes32 op) = receiver.records(trigger);
        assert(outcome == FinancialCallbackReceiver.Outcome.Executed && manager.completedDraw(op));
        assert(market.debt(borrower) == 600e6 && manager.principal(id) == 200e6 && vault.free(lender) == 800e6);
        assert(TestnetCreditManager(address(manager)).lifetimePrincipalCreated() == 200e6);
        _deliver(c);
        assert(manager.principal(id) == 200e6 && market.debt(borrower) == 600e6);
        vmd.warp(block.timestamp + 1 days);
        (,, uint256 payableAmount) = manager.debtPreview(id);
        vmd.prank(borrower);
        token.approve(address(vault), payableAmount);
        vmd.prank(borrower);
        manager.repay(id, payableAmount, 1);
        assert(manager.principal(id) == 0 && vault.free(lender) == 800e6 + payableAmount && payableAmount > 200e6);
        assert(source.totalLocked() == 0.001 ether);
    }

    function testAuthAndMalformedPayloadCannotExecute() public {
        _setupIntegration();
        (IOmniReactive.LogRecord memory e,) = _signal();
        IOmniSystem.CallbackConfiguration memory c = _request(e);
        vmd.expectRevert(FinancialCallbackReceiver.InvalidCallback.selector);
        PROXY.deliver(address(receiver), address(1), c.payload);
        (bool direct,) = address(receiver).call(c.payload);
        assert(!direct);
        vmd.expectRevert(FinancialCallbackReceiver.InvalidCallback.selector);
        PROXY.deliver(address(receiver), address(reactiveContract), bytes.concat(c.payload, bytes32(0)));
        assert(manager.principal(id) == 0 && vault.reserved(lender) == 300e6);
    }

    function testRecoveredSignalSkipsAndCanSignalAgain() public {
        _setupIntegration();
        (IOmniReactive.LogRecord memory e, bytes32 trigger) = _signal();
        IOmniSystem.CallbackConfiguration memory c = _request(e);
        bytes32 op = manager.observeRisk(id);
        market.setPosition(borrower, 800e6, 1000e6);
        _deliver(c);
        (FinancialCallbackReceiver.Outcome outcome,) = receiver.records(trigger);
        assert(
            outcome == FinancialCallbackReceiver.Outcome.SkippedRecovered && manager.pendingDraw(id) == bytes32(0)
                && op != bytes32(0)
        );
        assert(!registry.outstanding(id) && manager.principal(id) == 0);
        market.setPosition(borrower, 800e6, 840e6);
        assert(registry.signal(id) == 2);
    }

    function testPausedFailurePreservesRetryAndFinancialState() public {
        _setupIntegration();
        (IOmniReactive.LogRecord memory e, bytes32 trigger) = _signal();
        IOmniSystem.CallbackConfiguration memory c = _request(e);
        vmd.prank(address(0xBEEF));
        verifier.setPaused(true);
        vmd.expectRevert(CreditManagerCore.InvalidCollateral.selector);
        _deliver(c);
        (FinancialCallbackReceiver.Outcome outcome,) = receiver.records(trigger);
        assert(
            outcome == FinancialCallbackReceiver.Outcome.None && manager.pendingDraw(id) == bytes32(0)
                && manager.principal(id) == 0 && vault.reserved(lender) == 300e6
        );
        verifier.setPaused(false);
        vmd.chainId(FinancialTrigger.LASNA);
        vmd.warp(block.timestamp + 60);
        reactiveContract.retry(trigger);
        c = SYSTEM.lastRequest();
        vmd.chainId(FinancialTrigger.BASE);
        _deliver(c);
        assert(
            manager.principal(id) == 200e6 && TestnetCreditManager(address(manager)).lifetimePrincipalCreated() == 200e6
        );
    }

    function testAdapterFailureRollsBackAndCanRetry() public {
        _setupIntegration();
        (IOmniReactive.LogRecord memory e, bytes32 trigger) = _signal();
        IOmniSystem.CallbackConfiguration memory c = _request(e);
        vmd.mockCallRevert(
            address(market),
            abi.encodeCall(DemoMarket.repay, (borrower, 200e6)),
            abi.encodeWithSignature("Error(string)", "failure")
        );
        vmd.expectRevert();
        _deliver(c);
        (FinancialCallbackReceiver.Outcome outcome,) = receiver.records(trigger);
        assert(
            outcome == FinancialCallbackReceiver.Outcome.None && manager.principal(id) == 0
                && manager.pendingDraw(id) == bytes32(0)
        );
        assert(
            market.debt(borrower) == 800e6 && vault.reserved(lender) == 300e6
                && TestnetCreditManager(address(manager)).lifetimePrincipalCreated() == 0
        );
        vmd.clearMockedCalls();
        vmd.chainId(FinancialTrigger.LASNA);
        vmd.warp(block.timestamp + 60);
        reactiveContract.retry(trigger);
        c = SYSTEM.lastRequest();
        vmd.chainId(FinancialTrigger.BASE);
        _deliver(c);
        assert(manager.principal(id) == 200e6 && market.debt(borrower) == 600e6);
    }

    function testExistingPendingOperationSurvivesPausedFailure() public {
        _setupIntegration();
        (IOmniReactive.LogRecord memory e, bytes32 trigger) = _signal();
        IOmniSystem.CallbackConfiguration memory c = _request(e);
        bytes32 pending = manager.observeRisk(id);
        vmd.prank(address(0xBEEF));
        verifier.setPaused(true);
        vmd.expectRevert(CreditManagerCore.InvalidCollateral.selector);
        _deliver(c);
        assert(manager.pendingDraw(id) == pending && manager.principal(id) == 0);
        verifier.setPaused(false);
        vmd.chainId(FinancialTrigger.LASNA);
        vmd.warp(block.timestamp + 60);
        reactiveContract.retry(trigger);
        c = SYSTEM.lastRequest();
        vmd.chainId(FinancialTrigger.BASE);
        _deliver(c);
        (, bytes32 executed) = receiver.records(trigger);
        assert(executed == pending && manager.completedDraw(pending) && manager.principal(id) == 200e6);
    }

    function testStaleOracleRevertsThenRetrySucceeds() public {
        _setupIntegration();
        (IOmniReactive.LogRecord memory e, bytes32 trigger) = _signal();
        IOmniSystem.CallbackConfiguration memory c = _request(e);
        vmd.warp(block.timestamp + 1 hours + 1);
        _attest();
        vmd.expectRevert(CreditManagerCore.InvalidPrice.selector);
        _deliver(c);
        assert(manager.principal(id) == 0 && vault.reserved(lender) == 300e6);
        oracle.update(1_000_000e6);
        vmd.chainId(FinancialTrigger.LASNA);
        reactiveContract.retry(trigger);
        c = SYSTEM.lastRequest();
        vmd.chainId(FinancialTrigger.BASE);
        _deliver(c);
        assert(manager.principal(id) == 200e6 && market.debt(borrower) == 600e6);
    }

    function testSignalCannotBeOverwrittenAndCompetingExecutorReconciles() public {
        _setupIntegration();
        (IOmniReactive.LogRecord memory e, bytes32 trigger) = _signal();
        vmd.prank(address(123));
        assert(registry.signal(id) == 1);
        IOmniSystem.CallbackConfiguration memory c = _request(e);
        bytes32 op = manager.observeRisk(id);
        manager.executePending(id, op, 200e6);
        _deliver(c);
        (FinancialCallbackReceiver.Outcome outcome, bytes32 recorded) = receiver.records(trigger);
        assert(
            outcome == FinancialCallbackReceiver.Outcome.AlreadyDrawn && recorded == bytes32(0)
                && manager.principal(id) == 200e6
        );
    }

    function testExpiredSignalSkippedWithoutDebt() public {
        _setupIntegration();
        (IOmniReactive.LogRecord memory e, bytes32 trigger) = _signal();
        IOmniSystem.CallbackConfiguration memory c = _request(e);
        vmd.warp(terms.drawDeadline);
        _deliver(c);
        (FinancialCallbackReceiver.Outcome outcome,) = receiver.records(trigger);
        assert(
            outcome == FinancialCallbackReceiver.Outcome.SkippedExpired && manager.principal(id) == 0
                && vault.reserved(lender) == 300e6
        );
    }

    function testSettledSignalIsTerminalAndCannotReexecute() public {
        _setupIntegration();
        (IOmniReactive.LogRecord memory e, bytes32 trigger) = _signal();
        IOmniSystem.CallbackConfiguration memory c = _request(e);
        bytes32 op = manager.observeRisk(id);
        manager.executePending(id, op, 200e6);
        (,, uint256 amount) = manager.debtPreview(id);
        vmd.prank(borrower);
        token.approve(address(vault), amount);
        vmd.prank(borrower);
        manager.repay(id, amount, 1);
        _deliver(c);
        (FinancialCallbackReceiver.Outcome outcome,) = receiver.records(trigger);
        assert(outcome == FinancialCallbackReceiver.Outcome.SkippedTerminal && manager.principal(id) == 0);
        assert(TestnetCreditManager(address(manager)).lifetimePrincipalCreated() == 200e6);
    }

    function testUnknownAndStaleSignalsAreRecordedAsSkipped() public {
        _setupIntegration();
        FinancialTriggerV1 memory t = FinancialTriggerV1(
            1,
            FinancialTrigger.BASE,
            address(registry),
            FinancialTrigger.BASE,
            address(manager),
            bytes32(uint256(777)),
            1
        );
        bytes32 unknown = FinancialTrigger.id(address(reactiveContract), address(receiver), t);
        vmd.prank(FinancialTrigger.BASE_PROXY);
        receiver.onRiskSignal(address(reactiveContract), unknown, t);
        (FinancialCallbackReceiver.Outcome unknownOutcome,) = receiver.records(unknown);
        assert(unknownOutcome == FinancialCallbackReceiver.Outcome.SkippedUnknown);
        (, bytes32 oldTrigger) = _signal();
        market.setPosition(borrower, 800e6, 1000e6);
        registry.retire(id);
        market.setPosition(borrower, 800e6, 840e6);
        assert(registry.signal(id) == 2);
        t.agreementId = id;
        t.generation = 1;
        assert(oldTrigger == FinancialTrigger.id(address(reactiveContract), address(receiver), t));
        vmd.prank(FinancialTrigger.BASE_PROXY);
        receiver.onRiskSignal(address(reactiveContract), oldTrigger, t);
        (FinancialCallbackReceiver.Outcome oldOutcome,) = receiver.records(oldTrigger);
        assert(oldOutcome == FinancialCallbackReceiver.Outcome.SkippedStale && manager.principal(id) == 0);
    }

    function testRetryDelayAuthorizationAndBound() public {
        _setupIntegration();
        (IOmniReactive.LogRecord memory e, bytes32 trigger) = _signal();
        _request(e);
        vmd.chainId(FinancialTrigger.LASNA);
        vmd.prank(address(99));
        vmd.expectRevert(FinancialReactive.Unauthorized.selector);
        reactiveContract.retry(trigger);
        vmd.expectRevert(FinancialReactive.RetryUnavailable.selector);
        reactiveContract.retry(trigger);
        vmd.warp(block.timestamp + 60);
        reactiveContract.retry(trigger);
        vmd.warp(block.timestamp + 60);
        reactiveContract.retry(trigger);
        vmd.warp(block.timestamp + 60);
        vmd.expectRevert(FinancialReactive.RetryUnavailable.selector);
        reactiveContract.retry(trigger);
        assert(SYSTEM.requests() == 3);
    }

    function testAdapterTransferAndApprovalFailuresRevertAtomically() public {
        token.mint(address(manager), 200e6);
        vmd.prank(address(manager));
        token.approve(address(adapter), 200e6);
        bytes memory transferCall = abi.encodeCall(DemoToken.transferFrom, (address(manager), address(adapter), 200e6));
        vmd.mockCall(address(token), transferCall, abi.encode(false));
        vmd.prank(address(manager));
        vmd.expectRevert(DemoAdapter.TransferFailed.selector);
        adapter.repay(borrower, 200e6);
        assert(token.balanceOf(address(manager)) == 200e6 && market.debt(borrower) == 800e6);
        vmd.clearMockedCalls();
        vmd.mockCall(address(token), abi.encodeCall(DemoToken.approve, (address(market), 200e6)), abi.encode(false));
        vmd.prank(address(manager));
        vmd.expectRevert(DemoAdapter.TransferFailed.selector);
        adapter.repay(borrower, 200e6);
        assert(
            token.balanceOf(address(manager)) == 200e6 && token.balanceOf(address(adapter)) == 0
                && market.debt(borrower) == 800e6
        );
        vmd.clearMockedCalls();
        vmd.mockCall(address(token), abi.encodeCall(DemoToken.approve, (address(market), 0)), abi.encode(false));
        vmd.prank(address(manager));
        vmd.expectRevert(DemoAdapter.TransferFailed.selector);
        adapter.repay(borrower, 200e6);
        assert(
            token.balanceOf(address(manager)) == 200e6 && token.balanceOf(address(adapter)) == 0
                && market.debt(borrower) == 800e6
        );
        assert(token.allowance(address(adapter), address(market)) == 0);
    }

    function testIncorrectReportedRepaymentFailsCallbackAtomically() public {
        _setupIntegration();
        (IOmniReactive.LogRecord memory e, bytes32 trigger) = _signal();
        IOmniSystem.CallbackConfiguration memory c = _request(e);
        vmd.mockCall(address(market), abi.encodeCall(DemoMarket.repay, (borrower, 200e6)), abi.encode(199e6));
        vmd.expectRevert(CreditManagerCore.InvalidExecution.selector);
        _deliver(c);
        (FinancialCallbackReceiver.Outcome result,) = receiver.records(trigger);
        assert(
            result == FinancialCallbackReceiver.Outcome.None && manager.principal(id) == 0
                && vault.reserved(lender) == 300e6
        );
        assert(token.balanceOf(address(adapter)) == 0 && token.allowance(address(manager), address(adapter)) == 0);
    }

    function testInitialSystemFailureCanResignalSameOperation() public {
        _setupIntegration();
        (IOmniReactive.LogRecord memory e, bytes32 trigger) = _signal();
        vmd.chainId(FinancialTrigger.LASNA);
        SYSTEM.setReject(true);
        vmd.prank(FinancialTrigger.SYSTEM);
        vmd.expectRevert(MockOmniSystem.RequestRejected.selector);
        reactiveContract.react(e);
        (,,, uint8 attempts,) = reactiveContract.requests(trigger);
        assert(attempts == 0 && reactiveContract.observed(id, 1) == bytes32(0));
        SYSTEM.setReject(false);
        vmd.chainId(FinancialTrigger.BASE);
        vmd.expectRevert(RiskSignalRegistry.InvalidSignal.selector);
        registry.resignal(id);
        vmd.warp(block.timestamp + 60);
        vmd.recordLogs();
        registry.resignal(id);
        M3DVm.Log[] memory logs = vmd.getRecordedLogs();
        assert(logs.length == 1 && uint256(logs[0].topics[2]) == 1);
        e.txHash = 7;
        e.blockHash = 8;
        IOmniSystem.CallbackConfiguration memory c = _request(e);
        _deliver(c);
        assert(manager.principal(id) == 200e6);
    }

    function testRouteStopUnsubscribesAndCannotBeReconfigured() public {
        _setupIntegration();
        (IOmniReactive.LogRecord memory e, bytes32 trigger) = _signal();
        _request(e);
        vmd.chainId(FinancialTrigger.LASNA);
        vmd.prank(address(99));
        vmd.expectRevert(FinancialReactive.Unauthorized.selector);
        reactiveContract.stop();
        reactiveContract.stop();
        assert(!reactiveContract.active() && SYSTEM.subscription() == bytes32(0));
        vmd.prank(FinancialTrigger.SYSTEM);
        vmd.expectRevert(FinancialReactive.InvalidLog.selector);
        reactiveContract.react(e);
        vmd.expectRevert(FinancialReactive.RetryUnavailable.selector);
        reactiveContract.retry(trigger);
        vmd.expectRevert(FinancialReactive.InvalidRoute.selector);
        reactiveContract.configure(address(registry), address(manager), address(receiver), 2_000_000);
    }

    function testSystemRejectionDuringRetryPreservesAttempt() public {
        _setupIntegration();
        (IOmniReactive.LogRecord memory e, bytes32 trigger) = _signal();
        _request(e);
        vmd.chainId(FinancialTrigger.LASNA);
        vmd.warp(block.timestamp + 60);
        SYSTEM.setReject(true);
        vmd.expectRevert(MockOmniSystem.RequestRejected.selector);
        reactiveContract.retry(trigger);
        (,,, uint8 attempts,) = reactiveContract.requests(trigger);
        assert(attempts == 1);
        SYSTEM.setReject(false);
        reactiveContract.retry(trigger);
        (,,, attempts,) = reactiveContract.requests(trigger);
        assert(attempts == 2);
    }

    function testReactiveRejectsFakeEventsAndDeduplicates() public {
        _setupIntegration();
        (IOmniReactive.LogRecord memory e, bytes32 trigger) = _signal();
        vmd.chainId(FinancialTrigger.LASNA);
        vmd.expectRevert(FinancialReactive.Unauthorized.selector);
        reactiveContract.react(e);
        e.topic3 = 0;
        vmd.prank(FinancialTrigger.SYSTEM);
        vmd.expectRevert(FinancialReactive.InvalidLog.selector);
        reactiveContract.react(e);
        e.topic3 = uint256(uint160(address(manager)));
        vmd.prank(FinancialTrigger.SYSTEM);
        reactiveContract.react(e);
        vmd.prank(FinancialTrigger.SYSTEM);
        reactiveContract.react(e);
        assert(SYSTEM.requests() == 1);
        e.txHash = 9;
        vmd.prank(FinancialTrigger.SYSTEM);
        reactiveContract.react(e);
        assert(reactiveContract.observed(id, 1) == trigger && SYSTEM.requests() == 1);
    }
}
