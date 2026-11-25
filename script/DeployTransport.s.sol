// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {CovenantTransportReactive} from "../src/reactive/transport/CovenantTransportReactive.sol";
import {IOmniSystem} from "../src/reactive/transport/IOmniTransport.sol";
import {TransportEmitter} from "../src/reactive/transport/TransportEmitter.sol";
import {TransportReceiver} from "../src/reactive/transport/TransportReceiver.sol";
import {InvalidRoute, TransportTypes} from "../src/reactive/transport/TransportTypes.sol";

interface DeploymentVm {
    function envAddress(string calldata name) external returns (address);
    function startBroadcast() external;
    function stopBroadcast() external;
}

contract DeployTransport {
    DeploymentVm private constant vm = DeploymentVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function deployEmitter(uint8 route) external returns (TransportEmitter emitter) {
        (uint256 source,) = TransportTypes.routeChains(route);
        address signer = _signer(source);
        vm.startBroadcast();
        emitter = new TransportEmitter(route, signer);
        vm.stopBroadcast();
    }

    function deployReactive() external returns (CovenantTransportReactive reactiveContract) {
        address signer = _signer(TransportTypes.LASNA);
        vm.startBroadcast();
        reactiveContract = new CovenantTransportReactive(signer);
        vm.stopBroadcast();
    }

    function deployReceiver(uint8 route, address emitter, address reactiveContract)
        external
        returns (TransportReceiver receiver)
    {
        (, uint256 destination) = TransportTypes.routeChains(route);
        address signer = _signer(destination);
        if (TransportTypes.proxy(destination).code.length == 0) revert InvalidRoute();
        vm.startBroadcast();
        receiver = new TransportReceiver(route, emitter, reactiveContract, signer);
        vm.stopBroadcast();
    }

    function configure(address reactiveContract, uint8 route, address emitter, address receiver, uint64 gasLimit)
        external
    {
        _signer(TransportTypes.LASNA);
        if (reactiveContract.code.length == 0) revert InvalidRoute();
        vm.startBroadcast();
        CovenantTransportReactive(payable(reactiveContract)).configureRoute(route, emitter, receiver, gasLimit);
        vm.stopBroadcast();
    }

    function fund(uint256 chain, address recipient, uint256 amountWei) external {
        _signer(chain);
        address provider = chain == TransportTypes.LASNA ? TransportTypes.SYSTEM : TransportTypes.proxy(chain);
        if (amountWei == 0 || provider.code.length == 0 || recipient.code.length == 0) revert InvalidRoute();
        vm.startBroadcast();
        IOmniSystem(provider).depositTo{value: amountWei}(recipient);
        vm.stopBroadcast();
    }

    /// @dev TRANSPORT_SIGNER is a public address used only for constructor arguments and chain checks.
    ///      Signing comes from the CLI keystore/account selected for the broadcast, which the driver
    ///      checks against this address before broadcasting.
    function _signer(uint256 chain) private returns (address signer) {
        if (block.chainid != chain) revert InvalidRoute();
        signer = vm.envAddress("TRANSPORT_SIGNER");
        if (signer == address(0)) revert InvalidRoute();
    }
}
