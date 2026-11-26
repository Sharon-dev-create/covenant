// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

interface IDemoAsset {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IDemoMarket {
    function repay(address borrower, uint256 amount) external returns (uint256);
}

/// @notice One immutable manager and simulated market; cannot redirect lender funds.
contract DemoAdapter {
    address public immutable asset;
    address public immutable market;
    address public immutable manager;
    error Unauthorized();
    error TransferFailed();

    constructor(address asset_, address market_, address manager_) {
        if (block.chainid != 84532 || asset_.code.length == 0 || market_.code.length == 0 || manager_ == address(0)) {
            revert Unauthorized();
        }
        asset = asset_;
        market = market_;
        manager = manager_;
    }

    function repay(address borrower, uint256 amount) external returns (uint256) {
        if (msg.sender != manager) revert Unauthorized();
        if (!IDemoAsset(asset).transferFrom(msg.sender, address(this), amount)) revert TransferFailed();
        if (!IDemoAsset(asset).approve(market, amount)) revert TransferFailed();
        uint256 actual = IDemoMarket(market).repay(borrower, amount);
        if (!IDemoAsset(asset).approve(market, 0)) revert TransferFailed();
        return actual;
    }
}
