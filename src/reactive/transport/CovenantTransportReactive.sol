// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {IOmniReactive, IOmniSystem} from "./IOmniTransport.sol";
import {OmniPayer} from "./OmniPayer.sol";
import {
    DuplicateOperation,
    InvalidMessage,
    InvalidRoute,
    ProbeMessage,
    TransportTypes,
    UnauthorizedTransport
} from "./TransportTypes.sol";
import {TransportReceiver} from "./TransportReceiver.sol";

contract CovenantTransportReactive is IOmniReactive, OmniPayer {
    error RetryUnavailable();

    uint64 public constant MIN_CALLBACK_GAS = 250_000;
    uint64 public constant MAX_CALLBACK_GAS = 500_000;
    uint8 public constant MAX_ATTEMPTS = 3;
    uint64 public constant RETRY_DELAY = 60 seconds;
    uint256 private constant IGNORE_TOPIC = 0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad;
    IOmniSystem private constant SYSTEM = IOmniSystem(TransportTypes.SYSTEM);

    struct RouteConfig {
        address emitter;
        address receiver;
        uint64 gasLimit;
        bool active;
    }

    struct EventData {
        uint256 destination;
        uint256 blockNumber;
        uint256 timestamp;
        bytes32 payload;
        bytes32 hash;
    }

    struct Request {
        uint64 sequence;
        uint8 route;
        uint8 attempts;
        uint64 retryAfter;
        uint256 sourceBlock;
        uint256 sourceTimestamp;
        bytes32 payload;
    }

    address public immutable operator;
    mapping(uint8 route => RouteConfig) public routes;
    mapping(uint8 route => mapping(uint64 sequence => bytes32 operationId)) public observed;
    mapping(bytes32 operationId => Request) private requests;

    event RouteConfigured(uint8 indexed route, address indexed emitter, address indexed receiver, uint64 gasLimit);
    event RouteStopped(uint8 indexed route);
    event CallbackRequested(bytes32 indexed operationId, uint8 indexed route, uint8 attempt);
    event ProbeObserved(bytes32 indexed operationId, uint256 blockHash, uint256 txHash, uint256 logIndex);

    constructor(address operator_) payable OmniPayer(address(SYSTEM)) {
        if (block.chainid != TransportTypes.LASNA || operator_ == address(0) || address(SYSTEM).code.length == 0) {
            revert InvalidRoute();
        }
        operator = operator_;
    }

    modifier onlyOperator() {
        if (msg.sender != operator) revert UnauthorizedTransport();
        _;
    }

    function configureRoute(uint8 route, address emitter, address receiver, uint64 gasLimit) external onlyOperator {
        (uint256 source,) = TransportTypes.routeChains(route);
        if (
            emitter == address(0) || receiver == address(0) || routes[route].emitter != address(0)
                || gasLimit < MIN_CALLBACK_GAS || gasLimit > MAX_CALLBACK_GAS
        ) revert InvalidRoute();
        routes[route] = RouteConfig(emitter, receiver, gasLimit, true);
        emit RouteConfigured(route, emitter, receiver, gasLimit);
        // ProbeRequested topics: [0] signature, [1] operationId, [2] route, [3] sequence.
        SYSTEM.subscribe(source, emitter, uint256(TransportTypes.TOPIC), IGNORE_TOPIC, route, IGNORE_TOPIC);
    }

    function stopRoute(uint8 route) external onlyOperator {
        RouteConfig storage config = routes[route];
        if (!config.active) revert InvalidRoute();
        (uint256 source,) = TransportTypes.routeChains(route);
        config.active = false;
        emit RouteStopped(route);
        SYSTEM.unsubscribe(source, config.emitter, uint256(TransportTypes.TOPIC), IGNORE_TOPIC, route, IGNORE_TOPIC);
    }

    function react(LogRecord calldata entry) external {
        if (msg.sender != address(SYSTEM)) revert UnauthorizedTransport();
        if (
            entry.topic0 != uint256(TransportTypes.TOPIC) || entry.opCode != 4 || entry.topic1 == 0 || entry.topic2 == 0
                || entry.topic2 > type(uint8).max || entry.topic3 > type(uint64).max || entry.data.length != 5 * 32
                || entry.blockHash == 0 || entry.txHash == 0
        ) revert InvalidMessage();
        // Range checked above; narrowing cannot truncate the route ID.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint8 route = uint8(entry.topic2);
        RouteConfig storage config = routes[route];
        (uint256 source, uint256 destination) = TransportTypes.routeChains(route);
        if (!config.active || entry.chainId != source || entry.contractAddress != config.emitter) {
            revert InvalidRoute();
        }

        EventData memory data = abi.decode(entry.data, (EventData));
        if (data.destination != destination || data.blockNumber != entry.blockNumber) revert InvalidMessage();
        ProbeMessage memory message = ProbeMessage(
            route,
            source,
            entry.contractAddress,
            destination,
            // Sequence is range checked in the envelope validation above.
            // forge-lint: disable-next-line(unsafe-typecast)
            uint64(entry.topic3),
            data.blockNumber,
            data.timestamp,
            data.payload,
            data.hash
        );
        bytes32 id = bytes32(entry.topic1);
        TransportTypes.validate(id, message);
        bytes32 previous = observed[route][message.sequence];
        if (previous == id) return;
        if (previous != bytes32(0)) revert DuplicateOperation();

        observed[route][message.sequence] = id;
        Request storage request = requests[id];
        request.sequence = message.sequence;
        request.route = route;
        request.sourceBlock = message.sourceBlock;
        request.sourceTimestamp = message.sourceTimestamp;
        request.payload = message.payload;
        emit ProbeObserved(id, entry.blockHash, entry.txHash, entry.logIndex);
        _request(id, request, config, message);
    }

    function requestStatus(bytes32 id) external view returns (uint8 attempts, uint256 retryAfter) {
        Request storage request = requests[id];
        return (request.attempts, request.retryAfter);
    }

    function retry(bytes32 id) external onlyOperator {
        Request storage request = requests[id];
        RouteConfig storage config = routes[request.route];
        if (
            !config.active || request.attempts == 0 || request.attempts >= MAX_ATTEMPTS
                // Cooldown is intentionally wall-clock based; miner skew is acceptable for probe retries.
                // forge-lint: disable-next-line(block-timestamp)
                || block.timestamp < request.retryAfter
        ) {
            revert RetryUnavailable();
        }
        (uint256 source, uint256 destination) = TransportTypes.routeChains(request.route);
        ProbeMessage memory message = ProbeMessage(
            request.route,
            source,
            config.emitter,
            destination,
            request.sequence,
            request.sourceBlock,
            request.sourceTimestamp,
            request.payload,
            keccak256(abi.encode(request.payload))
        );
        _request(id, request, config, message);
    }

    function _request(bytes32 id, Request storage request, RouteConfig storage config, ProbeMessage memory message)
        private
    {
        uint8 attempt = ++request.attempts;
        // Cooldown arithmetic is checked before the narrowing cast.
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp > type(uint64).max - RETRY_DELAY) revert RetryUnavailable();
        // forge-lint: disable-next-line(unsafe-typecast)
        request.retryAfter = uint64(block.timestamp) + RETRY_DELAY;
        emit CallbackRequested(id, request.route, attempt);
        SYSTEM.requestCallbackV_1_0(
            IOmniSystem.CallbackConfiguration(
                message.destinationChain,
                config.receiver,
                config.gasLimit,
                abi.encodeCall(TransportReceiver.receiveProbe, (address(0), id, message))
            )
        );
    }
}
