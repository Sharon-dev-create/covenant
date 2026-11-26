// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;
import {DemoToken} from "../src/demo/DemoToken.sol";
import {DemoOracle} from "../src/demo/DemoOracle.sol";
import {DemoMarket} from "../src/demo/DemoMarket.sol";
import {DemoAdapter} from "../src/demo/DemoAdapter.sol";
import {CollateralAttestationVerifier} from "../src/demo/CollateralAttestationVerifier.sol";
import {DemoDeploymentFactory} from "../src/demo/DemoDeploymentFactory.sol";
import {RiskSignalRegistry} from "../src/reactive/financial/RiskSignalRegistry.sol";
import {FinancialReactive} from "../src/reactive/financial/FinancialReactive.sol";
import {FinancialCallbackReceiver} from "../src/reactive/financial/FinancialCallbackReceiver.sol";
import {MockOmniSystem, MockOmniProxy} from "./Transport.t.sol";
import {DeployM4} from "../script/DeployM4.s.sol";

interface M4GuardVm {
    function chainId(uint256) external;
    function setEnv(string calldata, string calldata) external;
    function etch(address, bytes calldata) external;
    function getNonce(address) external view returns (uint64);
    function expectRevert(bytes4) external;
    function computeCreateAddress(address, uint256) external pure returns (address);
}

contract M4DeploymentGuardsTest {
    M4GuardVm constant vm = M4GuardVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function testLocalScriptAssetSimulation() public {
        vm.chainId(84532);
        vm.setEnv("M4_SIGNER", "0x0000000000000000000000000000000000001234");
        DeployM4 d = new DeployM4();
        assert(address(d.deployAsset(address(0x1234))) != address(0));
    }

    struct Deployment {
        address asset;
        address oracle;
        address market;
        address verifier;
        address adapter;
        address factory;
        address registry;
        address manager;
    }

    function _base(DeployM4 d, address signer) private returns (Deployment memory x) {
        vm.chainId(84532);
        x.asset = address(d.deployAsset(signer));
        x.oracle = address(d.deployOracle(signer));
        x.market = address(d.deployMarket(x.asset, signer));
        (address outer,, address manager,) = d.predicted(signer, uint256(vm.getNonce(signer)) + 2);
        x.manager = manager;
        address[4] memory signers = [address(1), address(2), address(3), address(4)];
        x.verifier = address(d.deployVerifier(address(0x9876), manager, signer, signer, signers));
        x.adapter = address(d.deployAdapter(x.asset, x.market, manager));
        x.factory = address(d.deployFactory(signer, x.asset, x.verifier, x.oracle, x.adapter, outer));
        x.registry = address(d.deployRegistry(manager, x.market));
    }

    function testLocalFullDeploymentScriptSequence() public {
        address signer = address(0x1234);
        vm.setEnv("M4_SIGNER", "0x0000000000000000000000000000000000001234");
        DeployM4 d = new DeployM4();
        Deployment memory x = _base(d, signer);
        vm.chainId(5318007);
        vm.etch(0x8888888888888888888888888888888888888888, address(new MockOmniSystem()).code);
        address reactiveContract = address(d.deployReactive(signer));
        vm.chainId(84532);
        vm.etch(0x476F44b11F5C942c58f4c8E3d0300E5710743585, address(new MockOmniProxy()).code);
        address receiver = address(d.deployReceiver(reactiveContract, x.manager, x.registry));
        d.verifyBase(
            x.asset,
            x.market,
            x.oracle,
            x.adapter,
            x.verifier,
            x.factory,
            x.registry,
            receiver,
            reactiveContract,
            address(0x9876)
        );
        vm.chainId(5318007);
        d.configure(reactiveContract, x.registry, x.manager, receiver, 1_000_000, signer);
        d.verifyLasna(reactiveContract, x.registry, x.manager, receiver, 1_000_000, signer);
    }

    function testPredictedNestedAddressesAndMissingInputsFailClosed() public {
        DeployM4 d = new DeployM4();
        address sender = address(0x1234);
        (address outer, address inner, address manager, address vault) = d.predicted(sender, 7);
        assert(outer == vm.computeCreateAddress(sender, 7));
        assert(inner == vm.computeCreateAddress(outer, 1));
        assert(manager == vm.computeCreateAddress(inner, 1) && vault == vm.computeCreateAddress(inner, 2));
        vm.expectRevert(DeployM4.BadConfiguration.selector);
        d.predicted(address(0), 0);
        vm.chainId(31337);
        vm.expectRevert(DeployM4.BadConfiguration.selector);
        d.deployCollateral(address(1));
        vm.expectRevert(DeployM4.BadConfiguration.selector);
        d.deployAsset(address(1));
        vm.expectRevert(DeployM4.BadConfiguration.selector);
        d.deployReactive(address(1));
        vm.chainId(1301);
        vm.expectRevert(DeployM4.BadConfiguration.selector);
        d.deployCollateral(address(0));
        vm.chainId(84532);
        vm.expectRevert(DeployM4.BadConfiguration.selector);
        d.deployMarket(address(1), address(1));
        vm.expectRevert(DeployM4.BadConfiguration.selector);
        d.deployReceiver(address(0), address(0), address(0));
        vm.expectRevert(DeployM4.BadConfiguration.selector);
        d.fund(address(0), 0);
    }
}
