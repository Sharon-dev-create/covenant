// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @notice Operator-controlled simulated valuation in demo-token units, not an ETH price feed.
contract DemoOracle {
    address public immutable operator;
    uint256 public valuePerEther;
    uint256 public updatedAt;
    error Unauthorized();
    error InvalidValue();
    event ValuationUpdated(uint256 valuePerEther, uint256 timestamp);

    constructor(address operator_) {
        if (block.chainid != 84532 || operator_ == address(0)) revert Unauthorized();
        operator = operator_;
    }

    function update(uint256 price) external {
        if (msg.sender != operator) revert Unauthorized();
        if (price == 0 || price > type(uint128).max) revert InvalidValue();
        valuePerEther = price;
        updatedAt = block.timestamp;
        emit ValuationUpdated(price, block.timestamp);
    }

    function valueUSDC(uint256 amount) external view returns (uint256 value, uint256 timestamp) {
        if (amount > type(uint128).max) revert InvalidValue();
        return (amount * valuePerEther / 1 ether, updatedAt);
    }
}
