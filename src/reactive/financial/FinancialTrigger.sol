// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

struct FinancialTriggerV1 {
    uint32 version;
    uint256 originChainId;
    address originRegistry;
    uint256 destinationChainId;
    address manager;
    bytes32 agreementId;
    uint64 generation;
}

library FinancialTrigger {
    uint256 internal constant BASE = 84532;
    uint256 internal constant LASNA = 5318007;
    address internal constant SYSTEM = 0x8888888888888888888888888888888888888888;
    address internal constant BASE_PROXY = 0x476F44b11F5C942c58f4c8E3d0300E5710743585;
    uint256 internal constant IGNORE = 0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad;
    bytes32 internal constant TOPIC = keccak256("RiskSignaled(bytes32,uint64,address)");

    function id(address reactive, address ingress, FinancialTriggerV1 memory t) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                "COVENANT_RISK_TRIGGER_V1",
                LASNA,
                reactive,
                t.originChainId,
                t.originRegistry,
                t.destinationChainId,
                ingress,
                t.manager,
                t.agreementId,
                t.generation
            )
        );
    }
}
