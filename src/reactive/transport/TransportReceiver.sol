// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {OmniPayer} from "./OmniPayer.sol";
import {
    DuplicateOperation,
    InvalidMessage,
    InvalidRoute,
    ProbeMessage,
    TransportTypes,
    UnauthorizedTransport
} from "./TransportTypes.sol";

contract TransportReceiver is OmniPayer {
    error ProbeFailure();

    address public immutable operator;
    address public immutable callbackProxy;
    address public immutable expectedReactive;
    address public immutable sourceEmitter;
    uint256 public immutable sourceChain;
    uint256 public immutable destinationChain;
    uint8 public immutable route;
    uint64 public highestSequence;
    uint64 public receivedCount;
    uint64 public failSequence;
    mapping(uint64 sequence => bytes32 operationId) public received;

    event FailureConfigured(uint64 indexed sequence);
    event ProbeReceived(
        bytes32 indexed operationId, uint8 indexed route, uint64 indexed sequence, address reactive, bytes32 payloadHash
    );

    constructor(uint8 route_, address emitter_, address reactive_, address operator_)
        payable
        OmniPayer(_proxyForRoute(route_))
    {
        (sourceChain, destinationChain) = TransportTypes.routeChains(route_);
        if (
            block.chainid != destinationChain || emitter_ == address(0) || reactive_ == address(0)
                || operator_ == address(0)
        ) revert InvalidRoute();
        callbackProxy = _SERVICE_PROVIDER;
        route = route_;
        sourceEmitter = emitter_;
        expectedReactive = reactive_;
        operator = operator_;
    }

    function setFailureSequence(uint64 sequence) external {
        if (msg.sender != operator) revert UnauthorizedTransport();
        failSequence = sequence;
        emit FailureConfigured(sequence);
    }

    function receiveProbe(address reactive, bytes32 id, ProbeMessage calldata message) external {
        if (msg.sender != callbackProxy || reactive != expectedReactive) revert UnauthorizedTransport();
        if (msg.data.length != 4 + 11 * 32) revert InvalidMessage();
        if (
            block.chainid != destinationChain || message.destinationChain != destinationChain || message.route != route
                || message.sourceChain != sourceChain || message.emitter != sourceEmitter
        ) revert InvalidRoute();
        TransportTypes.validate(id, message);
        if (received[message.sequence] != bytes32(0)) revert DuplicateOperation();
        if (message.sequence == failSequence) revert ProbeFailure();

        // Independent probes may arrive in either order. Each sequence still has one receipt.
        received[message.sequence] = id;
        ++receivedCount;
        if (message.sequence > highestSequence) highestSequence = message.sequence;
        emit ProbeReceived(id, route, message.sequence, reactive, message.payloadHash);
    }

    function _proxyForRoute(uint8 route_) private pure returns (address) {
        (, uint256 destination) = TransportTypes.routeChains(route_);
        return TransportTypes.proxy(destination);
    }
}
