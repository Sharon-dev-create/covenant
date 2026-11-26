// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {CreditManagerCore} from "./CreditManagerCore.sol";

/// @notice Base Sepolia demo only. Limits apply per deployment, not across deployments.
contract TestnetCreditManager is CreditManagerCore {
    uint256 public constant DEMO_COMMITMENT_LIMIT = 300e6;
    uint256 public constant DEMO_PRINCIPAL_LIMIT = 300e6;
    uint256 public constant DEMO_LIFETIME_LIMIT = 300e6;
    uint256 public lifetimePrincipalCreated;

    constructor(address vault_, address asset_, address verifier_, address oracle_, address adapter_)
        CreditManagerCore(vault_, asset_, verifier_, oracle_, adapter_)
    {
        if (block.chainid != 84532 || adapter_.code.length == 0) revert InvalidTerms();
    }

    function _validateDeploymentPolicy(Terms calldata terms) internal pure override {
        if (terms.cap > DEMO_COMMITMENT_LIMIT || terms.autonomousRepayment > DEMO_PRINCIPAL_LIMIT) {
            revert InvalidTerms();
        }
    }

    function _recordDrawPolicy(uint256 amount) internal override {
        if (amount > DEMO_LIFETIME_LIMIT - lifetimePrincipalCreated) revert InvalidExecution();
        lifetimePrincipalCreated += amount;
    }
}
