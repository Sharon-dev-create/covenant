// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

interface IDemoTransfer {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @notice Operator-controlled simulated debt and health, not a real lending protocol.
contract DemoMarket {
    address public immutable asset;
    address public immutable operator;
    mapping(address => uint256) public debt;
    mapping(address => uint256) public simulatedCollateral;
    error Unauthorized();
    error InvalidPosition();

    constructor(address asset_, address operator_) {
        if (block.chainid != 84532 || asset_.code.length == 0 || operator_ == address(0)) revert Unauthorized();
        asset = asset_;
        operator = operator_;
    }

    function setPosition(address borrower, uint256 debt_, uint256 collateral_) external {
        if (msg.sender != operator) revert Unauthorized();
        if (borrower == address(0) || debt_ > 100_000e6 || collateral_ > 100_000e6) revert InvalidPosition();
        debt[borrower] = debt_;
        simulatedCollateral[borrower] = collateral_;
    }

    function health(address borrower) public view returns (uint256) {
        uint256 d = debt[borrower];
        return d == 0 ? type(uint256).max : simulatedCollateral[borrower] * 1e18 / d;
    }

    function isDistressed(address borrower) external view returns (bool) {
        uint256 h = health(borrower);
        return h > 1e18 && h <= 11e17;
    }

    function repay(address borrower, uint256 amount) external returns (uint256) {
        if (amount == 0 || amount > debt[borrower]) revert InvalidPosition();
        debt[borrower] -= amount;
        if (!IDemoTransfer(asset).transferFrom(msg.sender, address(this), amount)) revert InvalidPosition();
        return amount;
    }
}
