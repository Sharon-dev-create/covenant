// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {TransportEmitter} from "../src/reactive/transport/TransportEmitter.sol";
import {TransportReceiver} from "../src/reactive/transport/TransportReceiver.sol";
import {CovenantTransportReactive} from "../src/reactive/transport/CovenantTransportReactive.sol";
import {IOmniReactive, IOmniSystem} from "../src/reactive/transport/IOmniTransport.sol";
import {OmniPayer} from "../src/reactive/transport/OmniPayer.sol";
import {
    DuplicateOperation,
    InvalidMessage,
    InvalidRoute,
    ProbeMessage,
    TransportTypes,
    UnauthorizedTransport
} from "../src/reactive/transport/TransportTypes.sol";

interface TransportVm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function chainId(uint256 id) external;
    function etch(address target, bytes calldata code) external;
    function expectRevert(bytes4 selector) external;
    function expectRevert(bytes memory reason) external;
    function prank(address sender) external;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory);
    function roll(uint256 height) external;
    function warp(uint256 timestamp) external;
}

contract MockOmniSystem {
    error RequestRejected();

    bytes32 public subscription;
    uint256 public requests;
    bool public reject;
    address public sender;
    mapping(address => uint256) public debt;
    IOmniSystem.CallbackConfiguration private callback;

    receive() external payable {
        debt[msg.sender] = 0;
    }

    function setDebt(address account, uint256 amount) external {
        debt[account] = amount;
    }

    function subscribe(uint256 chain, address emitter, uint256 topic0, uint256 topic1, uint256 topic2, uint256 topic3)
        external
    {
        subscription = keccak256(abi.encode(msg.sender, chain, emitter, topic0, topic1, topic2, topic3));
    }

    function unsubscribe(uint256 chain, address emitter, uint256 topic0, uint256 topic1, uint256 topic2, uint256 topic3)
        external
    {
        assert(subscription == keccak256(abi.encode(msg.sender, chain, emitter, topic0, topic1, topic2, topic3)));
        delete subscription;
    }

    function setReject(bool value) external {
        reject = value;
    }

    function requestCallbackV_1_0(IOmniSystem.CallbackConfiguration calldata config) external {
        if (reject) revert RequestRejected();
        sender = msg.sender;
        callback = config;
        ++requests;
    }

    function lastRequest() external view returns (IOmniSystem.CallbackConfiguration memory) {
        return callback;
    }
}

contract MockOmniProxy {
    mapping(address => uint256) public debt;

    receive() external payable {
        debt[msg.sender] = 0;
    }

    function setDebt(address account, uint256 amount) external {
        debt[account] = amount;
    }

    function deliver(address recipient, address reactive, bytes calldata payload) external {
        (bool ok, bytes memory reason) =
            recipient.call{gas: 170_000}(bytes.concat(payload[:4], abi.encode(reactive), payload[36:]));
        if (!ok) {
            assembly ("memory-safe") {
                revert(add(reason, 32), mload(reason))
            }
        }
    }
}

contract TransportTest {
    TransportVm private constant vm = TransportVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    MockOmniSystem private constant SYSTEM = MockOmniSystem(payable(TransportTypes.SYSTEM));
    bytes32 private constant PAYLOAD = bytes32(uint256(42));

    CovenantTransportReactive private reactiveContract;

    function setUp() public {
        vm.chainId(TransportTypes.LASNA);
        vm.etch(address(SYSTEM), address(new MockOmniSystem()).code);
        bytes memory proxyCode = address(new MockOmniProxy()).code;
        vm.etch(TransportTypes.proxy(TransportTypes.BASE), proxyCode);
        vm.etch(TransportTypes.proxy(TransportTypes.UNICHAIN), proxyCode);
        reactiveContract = new CovenantTransportReactive(address(this));
        vm.roll(10);
        vm.warp(1000);
    }

    function testAllThreeRoutes() public {
        for (uint8 route = 1; route <= 3; ++route) {
            (TransportEmitter emitter, TransportReceiver receiver) = _configure(route);
            (bytes32 id, IOmniReactive.LogRecord memory entry) = _emit(emitter, 1);
            _react(entry);
            (uint8 attempts,) = reactiveContract.requestStatus(id);
            assert(attempts == 1 && receiver.receivedCount() == 0);
            IOmniSystem.CallbackConfiguration memory request = SYSTEM.lastRequest();
            assert(request.chainId == receiver.destinationChain() && request.recipient == address(receiver));
            assert(request.gasLimit == 300_000 && SYSTEM.sender() == address(reactiveContract));
            _deliver(request, SYSTEM.sender());
            assert(receiver.received(1) == id && receiver.receivedCount() == 1 && receiver.highestSequence() == 1);
        }
    }

    function testUnauthorizedDirectCallWrongProxyAndWrongInjectedSender() public {
        (TransportEmitter emitter, TransportReceiver receiver) = _configure(1);
        MockOmniProxy proxy = MockOmniProxy(payable(receiver.callbackProxy()));
        (bytes32 id, IOmniReactive.LogRecord memory entry) = _emit(emitter, 1);
        _react(entry);
        IOmniSystem.CallbackConfiguration memory request = SYSTEM.lastRequest();
        address expected = SYSTEM.sender();
        vm.chainId(request.chainId);

        vm.expectRevert(UnauthorizedTransport.selector);
        MockOmniProxy(payable(TransportTypes.proxy(TransportTypes.UNICHAIN)))
            .deliver(address(receiver), expected, request.payload);

        vm.expectRevert(UnauthorizedTransport.selector);
        proxy.deliver(address(receiver), address(1), request.payload);

        (bool direct,) = address(receiver).call(request.payload);
        assert(!direct && receiver.received(1) != id);
    }

    function testRejectsWrongSourceRoutePayloadAndMalformedLog() public {
        (TransportEmitter emitter,) = _configure(1);
        (, IOmniReactive.LogRecord memory entry) = _emit(emitter, 1);
        vm.chainId(TransportTypes.LASNA);
        vm.expectRevert(UnauthorizedTransport.selector);
        reactiveContract.react(entry);

        entry.contractAddress = address(1);
        _expectReaction(entry, InvalidRoute.selector);
        entry.contractAddress = address(emitter);
        entry.chainId = TransportTypes.BASE;
        _expectReaction(entry, InvalidRoute.selector);
        entry.chainId = TransportTypes.UNICHAIN;
        entry.topic2 = 3;
        _expectReaction(entry, InvalidRoute.selector);
        entry.topic2 = 1;
        entry.topic3 = uint256(type(uint64).max) + 1;
        _expectReaction(entry, InvalidMessage.selector);
        entry.topic3 = 1;
        entry.opCode = 3;
        _expectReaction(entry, InvalidMessage.selector);
        entry.opCode = 4;
        entry.topic0 = 0;
        _expectReaction(entry, InvalidMessage.selector);
        entry.topic0 = uint256(TransportTypes.TOPIC);
        entry.data = abi.encode(TransportTypes.BASE, entry.blockNumber, block.timestamp, PAYLOAD, bytes32(0));
        _expectReaction(entry, InvalidMessage.selector);
        assert(SYSTEM.requests() == 0);
    }

    function testReceiverValidatesRouteSourceAndPayload() public {
        (TransportEmitter emitter, TransportReceiver receiver) = _configure(1);
        MockOmniProxy proxy = MockOmniProxy(payable(receiver.callbackProxy()));
        (, IOmniReactive.LogRecord memory entry) = _emit(emitter, 1);
        _react(entry);
        IOmniSystem.CallbackConfiguration memory request = SYSTEM.lastRequest();
        ProbeMessage memory message = ProbeMessage(
            1,
            TransportTypes.UNICHAIN,
            address(emitter),
            request.chainId,
            1,
            entry.blockNumber,
            block.timestamp,
            PAYLOAD,
            keccak256(abi.encode(PAYLOAD))
        );
        vm.chainId(request.chainId);
        message.route = 3;
        _expectDelivery(receiver, message, InvalidRoute.selector);
        message.route = 1;
        message.emitter = address(1);
        _expectDelivery(receiver, message, InvalidRoute.selector);
        message.emitter = address(emitter);
        message.payloadHash = bytes32(0);
        _expectDelivery(receiver, message, InvalidMessage.selector);
        vm.expectRevert(InvalidMessage.selector);
        proxy.deliver(address(receiver), address(reactiveContract), bytes.concat(request.payload, bytes32(0)));
        assert(receiver.receivedCount() == 0);
    }

    function testDuplicateSourceRequestReactionAndDelivery() public {
        (TransportEmitter emitter, TransportReceiver receiver) = _configure(3);
        MockOmniProxy proxy = MockOmniProxy(payable(receiver.callbackProxy()));
        (bytes32 id, IOmniReactive.LogRecord memory entry) = _emit(emitter, 1);
        vm.expectRevert(DuplicateOperation.selector);
        emitter.emitProbe(bytes32(uint256(1)), PAYLOAD);
        assert(emitter.sequence() == 1);

        _react(entry);
        _react(entry);
        assert(SYSTEM.requests() == 1 && reactiveContract.observed(3, 1) == id);
        IOmniSystem.CallbackConfiguration memory request = SYSTEM.lastRequest();
        _deliver(request, address(reactiveContract));
        vm.expectRevert(DuplicateOperation.selector);
        proxy.deliver(address(receiver), address(reactiveContract), request.payload);
        assert(receiver.receivedCount() == 1);
    }

    function testOutOfOrderIndependentProbesReconcile() public {
        (TransportEmitter emitter, TransportReceiver receiver) = _configure(2);
        (bytes32 first, IOmniReactive.LogRecord memory firstEntry) = _emit(emitter, 1);
        (bytes32 second, IOmniReactive.LogRecord memory secondEntry) = _emit(emitter, 2);
        _react(secondEntry);
        _deliver(SYSTEM.lastRequest(), address(reactiveContract));
        assert(receiver.received(1) == bytes32(0) && receiver.highestSequence() == 2);
        _react(firstEntry);
        _deliver(SYSTEM.lastRequest(), address(reactiveContract));
        assert(receiver.receivedCount() == 2 && receiver.highestSequence() == 2);
        assert(receiver.received(1) == first && receiver.received(2) == second);
    }

    function testControlledFailureRetryAndAttemptLimit() public {
        (TransportEmitter emitter, TransportReceiver receiver) = _configure(1);
        MockOmniProxy proxy = MockOmniProxy(payable(receiver.callbackProxy()));
        (bytes32 id, IOmniReactive.LogRecord memory entry) = _emit(emitter, 1);
        _react(entry);
        IOmniSystem.CallbackConfiguration memory request = SYSTEM.lastRequest();
        vm.chainId(request.chainId);
        receiver.setFailureSequence(1);
        vm.expectRevert(TransportReceiver.ProbeFailure.selector);
        proxy.deliver(address(receiver), address(reactiveContract), request.payload);
        assert(receiver.receivedCount() == 0 && receiver.received(1) == bytes32(0));
        receiver.setFailureSequence(0);

        vm.chainId(TransportTypes.LASNA);
        vm.expectRevert(CovenantTransportReactive.RetryUnavailable.selector);
        reactiveContract.retry(id);
        (uint8 attempts, uint256 retryAfter) = reactiveContract.requestStatus(id);
        assert(attempts == 1);
        vm.warp(retryAfter);
        reactiveContract.retry(id);
        IOmniSystem.CallbackConfiguration memory retryRequest = SYSTEM.lastRequest();
        assert(keccak256(retryRequest.payload) == keccak256(request.payload));
        _deliver(retryRequest, address(reactiveContract));
        assert(receiver.received(1) == id && receiver.receivedCount() == 1);

        vm.chainId(TransportTypes.LASNA);
        (, retryAfter) = reactiveContract.requestStatus(id);
        vm.warp(retryAfter);
        reactiveContract.retry(id);
        (, retryAfter) = reactiveContract.requestStatus(id);
        vm.warp(retryAfter);
        vm.expectRevert(CovenantTransportReactive.RetryUnavailable.selector);
        reactiveContract.retry(id);
        assert(SYSTEM.requests() == 3);
    }

    function testRejectedSystemRequestRollsBackAndRouteCanStop() public {
        (TransportEmitter emitter, TransportReceiver receiver) = _configure(1);
        (bytes32 id, IOmniReactive.LogRecord memory entry) = _emit(emitter, 1);
        vm.chainId(TransportTypes.LASNA);
        SYSTEM.setReject(true);
        _expectReaction(entry, MockOmniSystem.RequestRejected.selector);
        (uint8 attempts,) = reactiveContract.requestStatus(id);
        assert(attempts == 0 && reactiveContract.observed(1, 1) == bytes32(0));

        SYSTEM.setReject(false);
        _react(entry);
        reactiveContract.stopRoute(1);
        assert(SYSTEM.subscription() == bytes32(0));
        _expectReaction(entry, InvalidRoute.selector);
        vm.expectRevert(InvalidRoute.selector);
        reactiveContract.configureRoute(1, address(emitter), address(receiver), 300_000);
    }

    function testOperatorControlsAndGasBounds() public {
        (TransportEmitter emitter, TransportReceiver receiver) = _configure(1);
        vm.expectRevert(InvalidRoute.selector);
        reactiveContract.configureRoute(2, address(emitter), address(receiver), 249_999);
        vm.expectRevert(InvalidRoute.selector);
        reactiveContract.configureRoute(2, address(emitter), address(receiver), 500_001);

        vm.prank(address(1));
        vm.expectRevert(UnauthorizedTransport.selector);
        reactiveContract.configureRoute(2, address(emitter), address(receiver), 300_000);
        vm.prank(address(1));
        vm.expectRevert(UnauthorizedTransport.selector);
        reactiveContract.retry(bytes32(uint256(1)));
        vm.prank(address(1));
        vm.expectRevert(UnauthorizedTransport.selector);
        reactiveContract.stopRoute(1);

        vm.chainId(TransportTypes.UNICHAIN);
        vm.prank(address(1));
        vm.expectRevert(UnauthorizedTransport.selector);
        emitter.emitProbe(bytes32(uint256(1)), PAYLOAD);

        vm.chainId(TransportTypes.BASE);
        vm.prank(address(1));
        vm.expectRevert(UnauthorizedTransport.selector);
        receiver.setFailureSequence(1);
    }

    function testPayerFundingProviderAuthAndDebtSettlement() public {
        (, TransportReceiver receiver) = _configure(1);
        assert(reactiveContract._SERVICE_PROVIDER() == address(SYSTEM));

        vm.chainId(TransportTypes.LASNA);
        SYSTEM.setDebt(address(reactiveContract), 0.001 ether);
        (bool funded,) = address(reactiveContract).call{value: 0.01 ether}("");
        assert(funded);
        vm.expectRevert(abi.encodeWithSelector(OmniPayer.NotAuthorized.selector, address(this), address(SYSTEM)));
        reactiveContract.pay(1);
        uint256 providerBalance = address(SYSTEM).balance;
        reactiveContract.coverDebt();
        assert(SYSTEM.debt(address(reactiveContract)) == 0);
        assert(address(SYSTEM).balance == providerBalance + 0.001 ether);

        vm.chainId(TransportTypes.BASE);
        MockOmniProxy proxy = MockOmniProxy(payable(receiver.callbackProxy()));
        assert(receiver._SERVICE_PROVIDER() == address(proxy));
        proxy.setDebt(address(receiver), 0.002 ether);
        (bool receiverFunded,) = address(receiver).call{value: 0.01 ether}("");
        assert(receiverFunded);
        vm.expectRevert(abi.encodeWithSelector(OmniPayer.NotAuthorized.selector, address(this), address(proxy)));
        receiver.pay(1);
        providerBalance = address(proxy).balance;
        receiver.coverDebt();
        assert(proxy.debt(address(receiver)) == 0);
        assert(address(proxy).balance == providerBalance + 0.002 ether);
    }

    function _configure(uint8 route) private returns (TransportEmitter emitter, TransportReceiver receiver) {
        (uint256 source, uint256 destination) = TransportTypes.routeChains(route);
        vm.chainId(source);
        emitter = new TransportEmitter(route, address(this));
        vm.chainId(destination);
        receiver = new TransportReceiver(route, address(emitter), address(reactiveContract), address(this));
        vm.chainId(TransportTypes.LASNA);
        reactiveContract.configureRoute(route, address(emitter), address(receiver), 300_000);
        uint256 ignore = 0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad;
        assert(
            SYSTEM.subscription()
                == keccak256(
                    abi.encode(
                        address(reactiveContract), source, address(emitter), TransportTypes.TOPIC, ignore, route, ignore
                    )
                )
        );
    }

    function _emit(TransportEmitter emitter, uint256 key)
        private
        returns (bytes32 id, IOmniReactive.LogRecord memory entry)
    {
        uint256 source = emitter.sourceChain();
        vm.chainId(source);
        vm.recordLogs();
        id = emitter.emitProbe(bytes32(key), PAYLOAD);
        TransportVm.Log[] memory logs = vm.getRecordedLogs();
        assert(logs.length == 1 && logs[0].topics.length == 4 && logs[0].topics[1] == id);
        TransportVm.Log memory item = logs[0];
        entry = IOmniReactive.LogRecord(
            source,
            item.emitter,
            uint256(item.topics[0]),
            uint256(item.topics[1]),
            uint256(item.topics[2]),
            uint256(item.topics[3]),
            item.data,
            block.number,
            item.topics.length,
            1,
            key,
            0
        );
    }

    function _react(IOmniReactive.LogRecord memory entry) private {
        vm.chainId(TransportTypes.LASNA);
        vm.prank(address(SYSTEM));
        reactiveContract.react(entry);
    }

    function _expectReaction(IOmniReactive.LogRecord memory entry, bytes4 errorSelector) private {
        vm.prank(address(SYSTEM));
        vm.expectRevert(errorSelector);
        reactiveContract.react(entry);
    }

    function _deliver(IOmniSystem.CallbackConfiguration memory request, address sender) private {
        vm.chainId(request.chainId);
        MockOmniProxy(payable(TransportTypes.proxy(request.chainId)))
            .deliver(request.recipient, sender, request.payload);
    }

    function _expectDelivery(TransportReceiver receiver, ProbeMessage memory message, bytes4 errorSelector) private {
        bytes memory data =
            abi.encodeCall(TransportReceiver.receiveProbe, (address(0), TransportTypes.operationId(message), message));
        vm.expectRevert(errorSelector);
        MockOmniProxy(payable(TransportTypes.proxy(message.destinationChain)))
            .deliver(address(receiver), address(reactiveContract), data);
    }
}
