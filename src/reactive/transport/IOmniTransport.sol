// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

// Wire ABI from Reactive-Network/reactive-lib-omni commit
// 3ade0dcf1d27e67e5783ef807e73a1b9e0c0cce8 (reviewed 2026-11-24).
interface IOmniReactive {
    struct LogRecord {
        uint256 chainId;
        address contractAddress;
        uint256 topic0;
        uint256 topic1;
        uint256 topic2;
        uint256 topic3;
        bytes data;
        uint256 blockNumber;
        uint256 opCode;
        uint256 blockHash;
        uint256 txHash;
        uint256 logIndex;
    }

    function react(LogRecord calldata entry) external;
}

interface IOmniSystem {
    struct CallbackConfiguration {
        uint256 chainId;
        address recipient;
        uint64 gasLimit;
        bytes payload;
    }

    function subscribe(uint256 chain, address emitter, uint256 topic0, uint256 topic1, uint256 topic2, uint256 topic3)
        external;
    function unsubscribe(uint256 chain, address emitter, uint256 topic0, uint256 topic1, uint256 topic2, uint256 topic3)
        external;
    function requestCallbackV_1_0(CallbackConfiguration calldata config) external;
    function depositTo(address recipient) external payable;
}
