// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {CollateralVault} from "../src/CollateralVault.sol";
import {DemoToken} from "../src/demo/DemoToken.sol";
import {DemoOracle} from "../src/demo/DemoOracle.sol";
import {DemoMarket} from "../src/demo/DemoMarket.sol";
import {DemoAdapter} from "../src/demo/DemoAdapter.sol";
import {CollateralAttestationVerifier} from "../src/demo/CollateralAttestationVerifier.sol";
import {DemoDeploymentFactory} from "../src/demo/DemoDeploymentFactory.sol";
import {CreditLiquidityVault} from "../src/CreditLiquidityVault.sol";
import {CreditManagerCore} from "../src/CreditManagerCore.sol";
import {RiskSignalRegistry} from "../src/reactive/financial/RiskSignalRegistry.sol";
import {FinancialReactive} from "../src/reactive/financial/FinancialReactive.sol";
import {FinancialCallbackReceiver} from "../src/reactive/financial/FinancialCallbackReceiver.sol";
import {IOmniSystem} from "../src/reactive/transport/IOmniTransport.sol";

interface M4Vm {
    function startBroadcast(address signer) external;
    function envAddress(string calldata name) external returns (address);
    function stopBroadcast() external;
    function getNonce(address account) external view returns (uint64);
    function computeCreateAddress(address deployer, uint256 nonce) external pure returns (address);
}

/// @notice Prepared testnet-only deployment steps. Use forge script without --broadcast for simulation.
contract DeployM4 {
    M4Vm constant vm = M4Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address constant SYSTEM = 0x8888888888888888888888888888888888888888;
    address constant BASE_PROXY = 0x476F44b11F5C942c58f4c8E3d0300E5710743585;
    error BadConfiguration();

    function predicted(address deployer, uint256 factoryNonce)
        public
        pure
        returns (address demoFactory, address nestedFactory, address manager, address vault)
    {
        if (deployer == address(0)) revert BadConfiguration();
        demoFactory = vm.computeCreateAddress(deployer, factoryNonce);
        nestedFactory = vm.computeCreateAddress(demoFactory, 1);
        manager = vm.computeCreateAddress(nestedFactory, 1);
        vault = vm.computeCreateAddress(nestedFactory, 2);
    }

    function deployCollateral(address binder) external returns (CollateralVault vault) {
        if (block.chainid != 1301 || binder == address(0)) revert BadConfiguration();
        vm.startBroadcast(_signer());
        vault = new CollateralVault(binder);
        vm.stopBroadcast();
        if (vault.binder() != binder) revert BadConfiguration();
    }

    function deployAsset(address authority) external returns (DemoToken token) {
        if (block.chainid != 84532 || authority == address(0)) revert BadConfiguration();
        vm.startBroadcast(_signer());
        token = new DemoToken(authority);
        vm.stopBroadcast();
        if (token.authority() != authority || token.decimals() != 6) revert BadConfiguration();
    }

    function deployOracle(address operator) external returns (DemoOracle oracle) {
        if (block.chainid != 84532 || operator == address(0)) revert BadConfiguration();
        vm.startBroadcast(_signer());
        oracle = new DemoOracle(operator);
        vm.stopBroadcast();
        if (oracle.operator() != operator) revert BadConfiguration();
    }

    function deployMarket(address asset, address operator) external returns (DemoMarket market) {
        if (
            block.chainid != 84532 || asset.codehash != keccak256(type(DemoToken).runtimeCode) || operator == address(0)
        ) revert BadConfiguration();
        vm.startBroadcast(_signer());
        market = new DemoMarket(asset, operator);
        vm.stopBroadcast();
        if (market.asset() != asset || market.operator() != operator) revert BadConfiguration();
    }

    function deployVerifier(
        address sourceVault,
        address predictedManager,
        address governance,
        address emergency,
        address[4] calldata signers
    ) external returns (CollateralAttestationVerifier verifier) {
        if (
            block.chainid != 84532 || sourceVault == address(0) || predictedManager == address(0)
                || governance == address(0) || emergency == address(0)
        ) revert BadConfiguration();
        vm.startBroadcast(_signer());
        verifier = new CollateralAttestationVerifier(sourceVault, predictedManager, governance, emergency, signers);
        vm.stopBroadcast();
        if (
            verifier.sourceVault() != sourceVault || verifier.manager() != predictedManager
                || verifier.governance() != governance || verifier.emergencyAuthority() != emergency
        ) revert BadConfiguration();
    }

    function deployAdapter(address asset, address market, address predictedManager)
        external
        returns (DemoAdapter adapter)
    {
        if (
            block.chainid != 84532 || asset.codehash != keccak256(type(DemoToken).runtimeCode)
                || market.code.length == 0 || DemoMarket(market).asset() != asset || predictedManager == address(0)
        ) revert BadConfiguration();
        vm.startBroadcast(_signer());
        adapter = new DemoAdapter(asset, market, predictedManager);
        vm.stopBroadcast();
        if (adapter.asset() != asset || adapter.market() != market || adapter.manager() != predictedManager) {
            revert BadConfiguration();
        }
    }

    function deployFactory(
        address deployer,
        address asset,
        address verifier,
        address oracle,
        address adapter,
        address expectedFactory
    ) external returns (DemoDeploymentFactory f) {
        if (
            block.chainid != 84532 || deployer == address(0) || asset.codehash != keccak256(type(DemoToken).runtimeCode)
                || verifier.code.length == 0 || oracle.code.length == 0 || adapter.code.length == 0
        ) revert BadConfiguration();
        (address actualFactory,, address expectedManager,) = predicted(deployer, vm.getNonce(deployer));
        if (
            _signer() != deployer || actualFactory != expectedFactory
                || DemoAdapter(adapter).manager() != expectedManager
                || CollateralAttestationVerifier(verifier).manager() != expectedManager
                || DemoAdapter(adapter).asset() != asset
        ) revert BadConfiguration();
        vm.startBroadcast(_signer());
        f = new DemoDeploymentFactory(asset, verifier, oracle, adapter);
        vm.stopBroadcast();
        if (
            address(f) != expectedFactory || f.manager() != expectedManager
                || CreditManagerCore(f.manager()).asset() != asset
                || CreditManagerCore(f.manager()).localOracle() != oracle
                || CreditManagerCore(f.manager()).localAdapter() != adapter
                || CreditManagerCore(f.manager()).localCollateralVerifier() != verifier
        ) revert BadConfiguration();
    }

    function deployRegistry(address manager, address market) external returns (RiskSignalRegistry registry) {
        if (
            block.chainid != 84532 || manager.code.length == 0 || market.code.length == 0
                || DemoAdapter(CreditManagerCore(manager).localAdapter()).market() != market
        ) revert BadConfiguration();
        vm.startBroadcast(_signer());
        registry = new RiskSignalRegistry(manager, market);
        vm.stopBroadcast();
        if (address(registry.manager()) != manager || registry.market() != market) revert BadConfiguration();
    }

    function deployReactive(address operator) external returns (FinancialReactive reactiveContract) {
        if (block.chainid != 5318007 || operator == address(0) || SYSTEM.code.length == 0) revert BadConfiguration();
        vm.startBroadcast(_signer());
        reactiveContract = new FinancialReactive(operator);
        vm.stopBroadcast();
        if (reactiveContract.operator() != operator || reactiveContract._SERVICE_PROVIDER() != SYSTEM) {
            revert BadConfiguration();
        }
    }

    function deployReceiver(address reactive, address manager, address registry)
        external
        returns (FinancialCallbackReceiver receiver)
    {
        if (
            block.chainid != 84532 || reactive == address(0) || manager.code.length == 0 || registry.code.length == 0
                || BASE_PROXY.code.length == 0 || address(RiskSignalRegistry(registry).manager()) != manager
        ) revert BadConfiguration();
        vm.startBroadcast(_signer());
        receiver = new FinancialCallbackReceiver(reactive, manager, registry);
        vm.stopBroadcast();
        if (
            receiver.reactive() != reactive || address(receiver.manager()) != manager
                || address(receiver.registry()) != registry || receiver._SERVICE_PROVIDER() != BASE_PROXY
        ) revert BadConfiguration();
    }

    function configure(
        address reactive,
        address registry,
        address manager,
        address receiver,
        uint64 gasLimit,
        address operator
    ) external {
        if (
            block.chainid != 5318007 || reactive.code.length == 0 || registry == address(0) || manager == address(0)
                || receiver == address(0) || FinancialReactive(payable(reactive)).operator() != operator
                || operator == address(0) || _signer() != operator || gasLimit < 1_000_000 || gasLimit > 3_000_000
        ) revert BadConfiguration();
        vm.startBroadcast(_signer());
        FinancialReactive(payable(reactive)).configure(registry, manager, receiver, gasLimit);
        vm.stopBroadcast();
        if (
            !FinancialReactive(payable(reactive)).active()
                || FinancialReactive(payable(reactive)).registry() != registry
                || FinancialReactive(payable(reactive)).manager() != manager
                || FinancialReactive(payable(reactive)).receiver() != receiver
        ) revert BadConfiguration();
    }

    function fund(address recipient, uint256 amount) external {
        address provider = block.chainid == 5318007 ? SYSTEM : block.chainid == 84532 ? BASE_PROXY : address(0);
        if (provider == address(0) || provider.code.length == 0 || recipient.code.length == 0 || amount == 0) {
            revert BadConfiguration();
        }
        vm.startBroadcast(_signer());
        IOmniSystem(provider).depositTo{value: amount}(recipient);
        vm.stopBroadcast();
    }

    function verifyBase(
        address asset,
        address market,
        address oracle,
        address adapter,
        address verifier,
        address demoFactory,
        address registry,
        address receiver,
        address reactive,
        address sourceVault
    ) external view {
        if (
            block.chainid != 84532 || asset.codehash != keccak256(type(DemoToken).runtimeCode)
                || market.code.length == 0 || oracle.code.length == 0 || adapter.code.length == 0
                || verifier.code.length == 0 || demoFactory.code.length == 0 || registry.code.length == 0
                || receiver.code.length == 0 || reactive == address(0) || sourceVault == address(0)
                || BASE_PROXY.code.length == 0
        ) revert BadConfiguration();
        DemoDeploymentFactory f = DemoDeploymentFactory(demoFactory);
        CreditManagerCore m = CreditManagerCore(f.manager());
        CreditLiquidityVault v = CreditLiquidityVault(f.vault());
        FinancialCallbackReceiver r = FinancialCallbackReceiver(payable(receiver));
        if (
            m.asset() != asset || m.vault() != address(v) || m.localOracle() != oracle || m.localAdapter() != adapter
                || m.localCollateralVerifier() != verifier || v.manager() != address(m) || v.consumer() != address(m)
                || address(v.asset()) != asset || DemoAdapter(adapter).manager() != address(m)
                || DemoAdapter(adapter).asset() != asset || DemoAdapter(adapter).market() != market
                || DemoMarket(market).asset() != asset
                || CollateralAttestationVerifier(verifier).manager() != address(m)
                || CollateralAttestationVerifier(verifier).sourceVault() != sourceVault
                || address(RiskSignalRegistry(registry).manager()) != address(m)
                || RiskSignalRegistry(registry).market() != market || r.reactive() != reactive
                || address(r.manager()) != address(m) || address(r.registry()) != registry
                || r._SERVICE_PROVIDER() != BASE_PROXY
        ) revert BadConfiguration();
    }

    function verifyLasna(
        address reactive,
        address registry,
        address manager,
        address receiver,
        uint64 gasLimit,
        address operator
    ) external view {
        if (
            block.chainid != 5318007 || SYSTEM.code.length == 0 || reactive.code.length == 0 || registry == address(0)
                || manager == address(0) || receiver == address(0) || operator == address(0)
        ) revert BadConfiguration();
        FinancialReactive r = FinancialReactive(payable(reactive));
        if (
            !r.active() || r.operator() != operator || r._SERVICE_PROVIDER() != SYSTEM || r.registry() != registry
                || r.manager() != manager || r.receiver() != receiver || r.callbackGas() != gasLimit
        ) revert BadConfiguration();
    }

    function verifyCollateral(address sourceVault, address binder) external view {
        if (
            block.chainid != 1301 || sourceVault.code.length == 0 || binder == address(0)
                || CollateralVault(sourceVault).binder() != binder
        ) revert BadConfiguration();
    }

    function _signer() private returns (address signer) {
        signer = vm.envAddress("M4_SIGNER");
        if (signer == address(0)) revert BadConfiguration();
    }
}
