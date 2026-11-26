// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;
import {DemoToken} from "./DemoToken.sol";
import {DemoAdapter} from "./DemoAdapter.sol";
import {DemoMarket} from "./DemoMarket.sol";
import {CollateralAttestationVerifier} from "./CollateralAttestationVerifier.sol";
import {TestnetCreditFactory} from "../TestnetCreditFactory.sol";

/// @notice Testnet demo path only: rejects generic tokens, including real USDC bytecode.
contract DemoDeploymentFactory {
    address public immutable factory;
    address public immutable manager;
    address public immutable vault;
    error InvalidDemoDeployment();

    constructor(address asset, address verifier, address oracle, address adapter) {
        if (block.chainid != 84532 || asset.codehash != keccak256(type(DemoToken).runtimeCode)) {
            revert InvalidDemoDeployment();
        }
        TestnetCreditFactory f = new TestnetCreditFactory(asset, verifier, oracle, adapter);
        DemoAdapter a = DemoAdapter(adapter);
        if (
            verifier.code.length == 0 || oracle.code.length == 0 || a.asset() != asset || a.manager() != f.manager()
                || a.market().code.length == 0 || DemoMarket(a.market()).asset() != asset
                || CollateralAttestationVerifier(verifier).manager() != f.manager()
        ) revert InvalidDemoDeployment();
        factory = address(f);
        manager = f.manager();
        vault = f.vault();
    }
}
