// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

error InvalidRoute();
error InvalidMessage();
error UnauthorizedTransport();
error DuplicateOperation();

struct ProbeMessage {
    uint8 route;
    uint256 sourceChain;
    address emitter;
    uint256 destinationChain;
    uint64 sequence;
    uint256 sourceBlock;
    uint256 sourceTimestamp;
    bytes32 payload;
    bytes32 payloadHash;
}

library TransportTypes {
    uint256 internal constant UNICHAIN = 1301;
    uint256 internal constant BASE = 84532;
    uint256 internal constant LASNA = 5318007;
    address internal constant SYSTEM = 0x8888888888888888888888888888888888888888;

    bytes32 internal constant TOPIC =
        keccak256("ProbeRequested(bytes32,uint8,uint64,uint256,uint256,uint256,bytes32,bytes32)");

    function routeChains(uint8 route) internal pure returns (uint256 source, uint256 destination) {
        if (route == 1) return (UNICHAIN, BASE);
        if (route == 2) return (BASE, UNICHAIN);
        if (route == 3) return (BASE, BASE);
        // forge-lint: disable-next-line(require-revert-in-loop)
        revert InvalidRoute();
    }

    function proxy(uint256 chain) internal pure returns (address) {
        if (chain == BASE) return 0x476F44b11F5C942c58f4c8E3d0300E5710743585;
        if (chain == UNICHAIN) return 0x775c9B990ADe401060B78D0e98684eEf8d2466C1;
        // forge-lint: disable-next-line(require-revert-in-loop)
        revert InvalidRoute();
    }

    function operationId(ProbeMessage memory message) internal pure returns (bytes32) {
        return keccak256(abi.encode("COVENANT_TRANSPORT_PROBE_V1", message));
    }

    function validate(bytes32 id, ProbeMessage memory message) internal pure {
        if (
            id == bytes32(0) || message.sequence == 0 || message.sourceBlock == 0 || message.sourceTimestamp == 0
                || message.payloadHash != keccak256(abi.encode(message.payload)) || id != operationId(message)
        ) revert InvalidMessage();
    }
}
