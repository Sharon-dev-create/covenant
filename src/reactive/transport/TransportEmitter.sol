// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {
    DuplicateOperation,
    InvalidMessage,
    InvalidRoute,
    ProbeMessage,
    TransportTypes,
    UnauthorizedTransport
} from "./TransportTypes.sol";

contract TransportEmitter {
    address public immutable operator;
    uint8 public immutable route;
    uint256 public immutable sourceChain;
    uint256 public immutable destinationChain;
    uint64 public sequence;
    mapping(bytes32 requestKey => bytes32 operationId) public operations;

    event ProbeRequested(
        bytes32 indexed operationId,
        uint8 indexed route,
        uint64 indexed sequence,
        uint256 destinationChain,
        uint256 sourceBlock,
        uint256 sourceTimestamp,
        bytes32 payload,
        bytes32 payloadHash
    );

    constructor(uint8 route_, address operator_) {
        (sourceChain, destinationChain) = TransportTypes.routeChains(route_);
        if (block.chainid != sourceChain || operator_ == address(0)) revert InvalidRoute();
        route = route_;
        operator = operator_;
    }

    function emitProbe(bytes32 requestKey, bytes32 payload) external returns (bytes32 id) {
        if (msg.sender != operator) revert UnauthorizedTransport();
        if (block.chainid != sourceChain || requestKey == bytes32(0)) revert InvalidMessage();
        if (operations[requestKey] != bytes32(0)) revert DuplicateOperation();

        ProbeMessage memory message = ProbeMessage({
            route: route,
            sourceChain: sourceChain,
            emitter: address(this),
            destinationChain: destinationChain,
            sequence: ++sequence,
            sourceBlock: block.number,
            sourceTimestamp: block.timestamp,
            payload: payload,
            payloadHash: keccak256(abi.encode(payload))
        });
        id = TransportTypes.operationId(message);
        operations[requestKey] = id;
        emit ProbeRequested(
            id, route, sequence, destinationChain, block.number, block.timestamp, payload, message.payloadHash
        );
    }
}
