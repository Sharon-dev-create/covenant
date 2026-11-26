// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {M3DFinancialCallbackTest} from "./M3DFinancialCallback.t.sol";
import {IOmniReactive, IOmniSystem} from "../src/reactive/transport/IOmniTransport.sol";
import {FinancialTrigger} from "../src/reactive/financial/FinancialTrigger.sol";
import {FinancialCallbackReceiver} from "../src/reactive/financial/FinancialCallbackReceiver.sol";
import {TestnetCreditManager} from "../src/TestnetCreditManager.sol";

/// @dev Models the 870k forwarded after historically observed 80k + 50k deductions from a 1m request.
contract M4GasProxy {
    function deliver(address target, address reactive, bytes calldata payload) external {
        (bool ok, bytes memory result) =
            target.call{gas: 870_000}(bytes.concat(payload[:4], abi.encode(reactive), payload[36:]));
        if (!ok) {
            assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
        }
    }
}

contract M4IntegratedInvariant is M3DFinancialCallbackTest {
    struct SelectorTarget {
        address addr;
        bytes4[] selectors;
    }
    uint8 private phase;
    bool private suspended;
    bytes32 private trigger;
    IOmniSystem.CallbackConfiguration private callback;
    mapping(bytes4 => uint256) public calls;
    mapping(bytes4 => uint256) public transitions;
    uint256 public duplicateTransitions;
    uint256 public failedDeliveries;
    event GasMeasured(string name, uint256 gasUsed);

    function targetContracts() external view returns (address[] memory a) {
        a = new address[](1);
        a[0] = address(this);
    }

    function targetSelectors() external view returns (SelectorTarget[] memory a) {
        bytes4[] memory s = new bytes4[](7);
        s[0] = this.hInitialize.selector;
        s[1] = this.hRequest.selector;
        s[2] = this.hExecute.selector;
        s[3] = this.hPause.selector;
        s[4] = this.hAttemptPaused.selector;
        s[5] = this.hResume.selector;
        s[6] = this.hRepay.selector;
        a = new SelectorTarget[](1);
        a[0] = SelectorTarget(address(this), s);
    }

    function hInitialize() external {
        calls[msg.sig]++;
        if (phase != 0) return;
        _setupIntegration();
        phase = 1;
        transitions[msg.sig]++;
    }

    function hRequest() external {
        calls[msg.sig]++;
        if (phase != 1) return;
        (IOmniReactive.LogRecord memory e, bytes32 tid) = _signal();
        callback = _request(e);
        trigger = tid;
        phase = 2;
        transitions[msg.sig]++;
        assert(manager.principal(id) == 0 && vault.reserved(lender) == 300e6);
    }

    function hExecute() external {
        calls[msg.sig]++;
        if (phase != 2 || suspended) return;
        _deliver(callback);
        (FinancialCallbackReceiver.Outcome o,) = receiver.records(trigger);
        assert(o == FinancialCallbackReceiver.Outcome.Executed);
        phase = 3;
        transitions[msg.sig]++;
        _deliver(callback);
        duplicateTransitions++;
        assert(manager.principal(id) == 200e6 && market.debt(borrower) == 600e6);
    }

    function hPause() external {
        calls[msg.sig]++;
        if ((phase != 2 && phase != 3) || suspended) return;
        vmd.prank(address(0xBEEF));
        verifier.setPaused(true);
        suspended = true;
        transitions[msg.sig]++;
    }

    function hAttemptPaused() external {
        calls[msg.sig]++;
        if (phase != 2 || !suspended) return;
        (bool ok,) = address(PROXY)
            .call(abi.encodeCall(PROXY.deliver, (address(receiver), address(reactiveContract), callback.payload)));
        assert(!ok && manager.principal(id) == 0 && vault.reserved(lender) == 300e6);
        failedDeliveries++;
        transitions[msg.sig]++;
    }

    function hResume() external {
        calls[msg.sig]++;
        if (!suspended) return;
        verifier.setPaused(false);
        suspended = false;
        transitions[msg.sig]++;
    }

    function hRepay() external {
        calls[msg.sig]++;
        if (phase != 3) return;
        vmd.prank(borrower);
        token.approve(address(vault), 200e6);
        vmd.prank(borrower);
        manager.repay(id, 200e6, 22);
        phase = 4;
        transitions[msg.sig]++;
    }

    function invariant_IntegratedCashAndSingleDraw() public view {
        uint256 expectedFree = phase == 0 ? 1000e6 : phase <= 2 ? 700e6 : phase == 3 ? 800e6 : 1000e6;
        uint256 expectedReserved = phase >= 1 && phase <= 2 ? 300e6 : 0;
        uint256 expectedPrincipal = phase == 3 ? 200e6 : 0;
        assert(vault.free(lender) == expectedFree && vault.reserved(lender) == expectedReserved);
        assert(vault.totalFree() == expectedFree && vault.totalReserved() == expectedReserved);
        assert(token.balanceOf(address(vault)) == expectedFree + expectedReserved);
        assert(manager.principal(id) == expectedPrincipal);
        assert(market.debt(borrower) == (phase >= 3 ? 600e6 : 800e6));
        assert(TestnetCreditManager(address(manager)).lifetimePrincipalCreated() == (phase >= 3 ? 200e6 : 0));
        assert(source.totalLocked() == 0.001 ether && address(source).balance == 0.001 ether);
    }

    function testM4DirectedModelTransitions() public {
        this.hInitialize();
        invariant_IntegratedCashAndSingleDraw();
        this.hRequest();
        invariant_IntegratedCashAndSingleDraw();
        this.hPause();
        this.hAttemptPaused();
        invariant_IntegratedCashAndSingleDraw();
        this.hResume();
        this.hExecute();
        invariant_IntegratedCashAndSingleDraw();
        this.hPause();
        assert(suspended);
        this.hRepay();
        invariant_IntegratedCashAndSingleDraw();
        assert(duplicateTransitions == 1 && failedDeliveries == 1);
        assert(
            transitions[this.hInitialize.selector] == 1 && transitions[this.hRequest.selector] == 1
                && transitions[this.hExecute.selector] == 1 && transitions[this.hRepay.selector] == 1
        );
    }

    function testM4MeasureSuccessDuplicateAndOneMillionSimulation() public {
        _setupIntegration();
        (IOmniReactive.LogRecord memory e,) = _signal();
        IOmniSystem.CallbackConfiguration memory c = _request(e);
        vmd.etch(FinancialTrigger.BASE_PROXY, address(new M4GasProxy()).code);
        uint256 beforeGas = gasleft();
        M4GasProxy(FinancialTrigger.BASE_PROXY).deliver(address(receiver), address(reactiveContract), c.payload);
        emit GasMeasured("success_proxy_870k", beforeGas - gasleft());
        beforeGas = gasleft();
        M4GasProxy(FinancialTrigger.BASE_PROXY).deliver(address(receiver), address(reactiveContract), c.payload);
        emit GasMeasured("duplicate_proxy", beforeGas - gasleft());
        assert(manager.principal(id) == 200e6);
    }

    function testM4MeasureRecoveredAndObsolete() public {
        _setupIntegration();
        (IOmniReactive.LogRecord memory e,) = _signal();
        IOmniSystem.CallbackConfiguration memory c = _request(e);
        market.setPosition(borrower, 800e6, 1000e6);
        uint256 beforeGas = gasleft();
        _deliver(c);
        emit GasMeasured("recovered_proxy", beforeGas - gasleft());
        assert(manager.principal(id) == 0);
    }

    function testM4MeasureTemporaryFailureAndRetry() public {
        _setupIntegration();
        (IOmniReactive.LogRecord memory e, bytes32 tid) = _signal();
        IOmniSystem.CallbackConfiguration memory c = _request(e);
        vmd.prank(address(0xBEEF));
        verifier.setPaused(true);
        uint256 beforeGas = gasleft();
        (bool ok,) = address(PROXY)
            .call(abi.encodeCall(PROXY.deliver, (address(receiver), address(reactiveContract), c.payload)));
        emit GasMeasured("temporary_failure_proxy", beforeGas - gasleft());
        assert(!ok);
        verifier.setPaused(false);
        vmd.chainId(FinancialTrigger.LASNA);
        vmd.warp(block.timestamp + 60);
        reactiveContract.retry(tid);
        c = SYSTEM.lastRequest();
        vmd.chainId(FinancialTrigger.BASE);
        beforeGas = gasleft();
        _deliver(c);
        emit GasMeasured("retry_success_proxy", beforeGas - gasleft());
        assert(manager.principal(id) == 200e6);
    }

    function testM4MeasureExpiredDisposition() public {
        _setupIntegration();
        (IOmniReactive.LogRecord memory e,) = _signal();
        IOmniSystem.CallbackConfiguration memory c = _request(e);
        vmd.warp(terms.drawDeadline);
        uint256 beforeGas = gasleft();
        _deliver(c);
        emit GasMeasured("expired_proxy", beforeGas - gasleft());
        assert(manager.principal(id) == 0);
    }
}
