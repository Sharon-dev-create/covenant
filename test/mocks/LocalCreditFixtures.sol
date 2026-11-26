// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @dev Local test input only. This is not source-chain finality verification.
contract LocalCollateralFixture {
    struct Evidence {
        bytes32 lot;
        address borrower;
        uint256 amount;
    }
    mapping(bytes32 => Evidence) public evidence;

    function set(bytes32 id, bytes32 lot, address borrower, uint256 amount) external {
        evidence[id] = Evidence(lot, borrower, amount);
    }

    function verify(bytes32 id, bytes32 lot, address borrower, uint256 amount) external view returns (bool) {
        Evidence storage e = evidence[id];
        return e.lot == lot && e.borrower == borrower && e.amount == amount && amount != 0;
    }
}

contract LocalOracleFixture {
    uint256 public value;
    uint256 public updatedAt;

    function set(uint256 value_, uint256 updatedAt_) external {
        value = value_;
        updatedAt = updatedAt_;
    }

    function valueUSDC(uint256 amount) external view returns (uint256, uint256) {
        require(amount <= type(uint128).max && value <= type(uint128).max);
        return (amount * value / 1 ether, updatedAt);
    }
}
