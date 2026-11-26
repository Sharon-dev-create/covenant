// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {CreditManagerCore} from "./CreditManagerCore.sol";

/// @notice Existing local financial manager. Never deployable outside the local chain.
contract CreditManager is CreditManagerCore {
    constructor(
        address vault_,
        address asset_,
        address localCollateralVerifier_,
        address localOracle_,
        address localAdapter_
    ) CreditManagerCore(vault_, asset_, localCollateralVerifier_, localOracle_, localAdapter_) {
        if (block.chainid != 31337) revert InvalidTerms();
    }

    function _validateDeploymentPolicy(Terms calldata) internal pure override {}
    function _recordDrawPolicy(uint256) internal pure override {}
}
