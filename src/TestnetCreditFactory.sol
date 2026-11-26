// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {TestnetCreditManager} from "./TestnetCreditManager.sol";
import {CreditLiquidityVault} from "./CreditLiquidityVault.sol";
import {IERC20} from "./interfaces/IVaults.sol";

/// @notice Constructor-only deployment for Base Sepolia testnet demonstrations.
contract TestnetCreditFactory {
    error InvalidDeployment();
    address public immutable manager;
    address public immutable vault;

    constructor(address asset, address verifier, address oracle, address adapter) {
        if (block.chainid != 84532 || adapter.code.length == 0) revert InvalidDeployment();
        address predictedManager = predict(address(this), 1);
        address predictedVault = predict(address(this), 2);
        TestnetCreditManager createdManager = new TestnetCreditManager(predictedVault, asset, verifier, oracle, adapter);
        CreditLiquidityVault createdVault = new CreditLiquidityVault(IERC20(asset), predictedManager, predictedManager);
        if (
            address(createdManager) != predictedManager || address(createdVault) != predictedVault
                || address(createdManager).code.length == 0 || address(createdVault).code.length == 0
                || createdManager.vault() != predictedVault || createdManager.asset() != asset
                || createdManager.localCollateralVerifier() != verifier || createdManager.localOracle() != oracle
                || createdManager.localAdapter() != adapter || createdVault.manager() != predictedManager
                || createdVault.consumer() != predictedManager || address(createdVault.asset()) != asset
        ) revert InvalidDeployment();
        manager = predictedManager;
        vault = predictedVault;
    }

    function predict(address factory, uint8 nonce) public pure returns (address) {
        if (nonce != 1 && nonce != 2) revert InvalidDeployment();
        return address(uint160(uint256(keccak256(abi.encodePacked(hex"d694", factory, nonce)))));
    }
}
