// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;
import {IOmniReactive, IOmniSystem} from "../transport/IOmniTransport.sol";
import {OmniPayer} from "../transport/OmniPayer.sol";
import {FinancialTriggerV1, FinancialTrigger} from "./FinancialTrigger.sol";
import {FinancialCallbackReceiver} from "./FinancialCallbackReceiver.sol";

/// @notice Lasna testnet orchestration only. A request is not a financial success.
contract FinancialReactive is IOmniReactive, OmniPayer {
    uint64 public constant MIN_CALLBACK_GAS = 1_000_000;
    uint64 public constant MAX_CALLBACK_GAS = 3_000_000;
    uint8 public constant MAX_ATTEMPTS = 3;
    uint64 public constant RETRY_DELAY = 60;
    IOmniSystem private constant SYSTEM = IOmniSystem(FinancialTrigger.SYSTEM);

    struct Request {
        bytes32 agreementId;
        uint64 generation;
        uint64 retryAfter;
        uint8 attempts;
        bytes32 sourceIdentity;
    }
    address public immutable operator;
    address public registry;
    address public manager;
    address public receiver;
    uint64 public callbackGas;
    bool public active;
    mapping(bytes32 => Request) public requests;
    mapping(bytes32 => mapping(uint64 => bytes32)) public observed;
    error Unauthorized();
    error InvalidRoute();
    error InvalidLog();
    error RetryUnavailable();
    event FinancialRouteConfigured(
        address indexed registry, address indexed manager, address indexed receiver, uint64 callbackGas
    );
    event FinancialRouteStopped();
    event FinancialSignalObserved(
        bytes32 indexed triggerId,
        bytes32 indexed agreementId,
        uint64 generation,
        uint256 blockHash,
        uint256 txHash,
        uint256 logIndex
    );
    event FinancialCallbackRequested(bytes32 indexed triggerId, uint8 attempt);
    event FinancialSignalDuplicate(bytes32 indexed triggerId, uint256 blockHash, uint256 txHash, uint256 logIndex);

    constructor(address operator_) OmniPayer(address(SYSTEM)) {
        if (block.chainid != FinancialTrigger.LASNA || operator_ == address(0) || address(SYSTEM).code.length == 0) {
            revert InvalidRoute();
        }
        operator = operator_;
    }
    modifier onlyOperator() {
        if (msg.sender != operator) revert Unauthorized();
        _;
    }

    function configure(address registry_, address manager_, address receiver_, uint64 gasLimit) external onlyOperator {
        if (
            registry != address(0) || registry_ == address(0) || manager_ == address(0) || receiver_ == address(0)
                || gasLimit < MIN_CALLBACK_GAS || gasLimit > MAX_CALLBACK_GAS
        ) revert InvalidRoute();
        registry = registry_;
        manager = manager_;
        receiver = receiver_;
        callbackGas = gasLimit;
        active = true;
        SYSTEM.subscribe(
            FinancialTrigger.BASE,
            registry_,
            uint256(FinancialTrigger.TOPIC),
            FinancialTrigger.IGNORE,
            FinancialTrigger.IGNORE,
            uint256(uint160(manager_))
        );
        emit FinancialRouteConfigured(registry_, manager_, receiver_, gasLimit);
    }

    function stop() external onlyOperator {
        if (!active) revert InvalidRoute();
        active = false;
        SYSTEM.unsubscribe(
            FinancialTrigger.BASE,
            registry,
            uint256(FinancialTrigger.TOPIC),
            FinancialTrigger.IGNORE,
            FinancialTrigger.IGNORE,
            uint256(uint160(manager))
        );
        emit FinancialRouteStopped();
    }

    function react(LogRecord calldata e) external {
        if (msg.sender != address(SYSTEM) || block.chainid != FinancialTrigger.LASNA) revert Unauthorized();
        if (
            !active || e.chainId != FinancialTrigger.BASE || e.contractAddress != registry
                || e.topic0 != uint256(FinancialTrigger.TOPIC) || e.topic1 == 0 || e.topic2 == 0
                || e.topic2 > type(uint64).max || e.topic3 != uint256(uint160(manager)) || e.data.length != 0
                || e.opCode != 4 || e.blockHash == 0 || e.txHash == 0
        ) revert InvalidLog();
        uint64 generation = uint64(e.topic2);
        FinancialTriggerV1 memory t = FinancialTriggerV1(
            1, FinancialTrigger.BASE, registry, FinancialTrigger.BASE, manager, bytes32(e.topic1), generation
        );
        bytes32 triggerId = FinancialTrigger.id(address(this), receiver, t);
        bytes32 sourceIdentity = keccak256(abi.encode(e.blockHash, e.txHash, e.logIndex));
        if (observed[t.agreementId][generation] != bytes32(0)) {
            if (observed[t.agreementId][generation] != triggerId) revert InvalidLog();
            emit FinancialSignalDuplicate(triggerId, e.blockHash, e.txHash, e.logIndex);
            return;
        }
        observed[t.agreementId][generation] = triggerId;
        requests[triggerId] = Request(t.agreementId, generation, 0, 0, sourceIdentity);
        emit FinancialSignalObserved(triggerId, t.agreementId, generation, e.blockHash, e.txHash, e.logIndex);
        _request(triggerId, t);
    }

    function retry(bytes32 triggerId) external onlyOperator {
        Request storage r = requests[triggerId];
        if (
            block.chainid != FinancialTrigger.LASNA || !active || r.attempts == 0 || r.attempts >= MAX_ATTEMPTS
                || block.timestamp < r.retryAfter
        ) {
            revert RetryUnavailable();
        }
        FinancialTriggerV1 memory t = FinancialTriggerV1(
            1, FinancialTrigger.BASE, registry, FinancialTrigger.BASE, manager, r.agreementId, r.generation
        );
        _request(triggerId, t);
    }

    function _request(bytes32 triggerId, FinancialTriggerV1 memory t) private {
        if (block.timestamp > type(uint64).max - RETRY_DELAY) revert RetryUnavailable();
        Request storage r = requests[triggerId];
        r.attempts++;
        r.retryAfter = uint64(block.timestamp) + RETRY_DELAY;
        emit FinancialCallbackRequested(triggerId, r.attempts);
        SYSTEM.requestCallbackV_1_0(
            IOmniSystem.CallbackConfiguration(
                FinancialTrigger.BASE,
                receiver,
                callbackGas,
                abi.encodeCall(FinancialCallbackReceiver.onRiskSignal, (address(0), triggerId, t))
            )
        );
    }
}
