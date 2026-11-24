// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {ICollateralVault} from "./interfaces/IVaults.sol";
import {
    CollateralPosition,
    CollateralState,
    InvalidIdentifier,
    InvalidAmount,
    InvalidState,
    InvalidAddress,
    Unauthorized
} from "./ProtocolTypes.sol";

/// @notice Local, lock-only custody. Deployments have no path for releasing ETH.
contract CollateralVault is ICollateralVault {
    address public immutable binder;
    mapping(bytes32 agreementId => address borrower) public borrowers;
    mapping(bytes32 agreementId => uint256 amount) public lockAmounts;

    uint256 private immutable deploymentChainId;

    constructor(address binder_) {
        if (binder_ == address(0)) revert InvalidAddress();
        binder = binder_;
        deploymentChainId = block.chainid;
    }

    function bind(bytes32 agreementId, address borrower, uint256 amount) external {
        if (msg.sender != binder) revert Unauthorized();
        if (agreementId == bytes32(0)) revert InvalidIdentifier();
        if (borrower == address(0)) revert InvalidAddress();
        if (borrowers[agreementId] != address(0)) revert InvalidState();
        if (amount == 0) revert InvalidAmount();
        borrowers[agreementId] = borrower;
        lockAmounts[agreementId] = amount;
        emit AgreementBound(agreementId, borrower, amount);
    }

    mapping(bytes32 id => CollateralPosition position) public positions;
    uint256 public totalLocked;
    uint256 public constant totalReleased = 0;

    function positionId(bytes32 agreementId) public view returns (bytes32) {
        return keccak256(abi.encode("LOT_V1", deploymentChainId, address(this), agreementId));
    }

    function lock(bytes32 agreementId) external payable returns (bytes32 id) {
        if (agreementId == bytes32(0)) revert InvalidIdentifier();
        if (borrowers[agreementId] != msg.sender) revert Unauthorized();
        if (msg.value == 0 || msg.value != lockAmounts[agreementId]) revert InvalidAmount();
        id = positionId(agreementId);
        if (positions[id].state != CollateralState.Absent) revert InvalidState();
        positions[id] = CollateralPosition(msg.sender, agreementId, msg.value, CollateralState.Locked);
        totalLocked += msg.value;
        emit CollateralLocked(agreementId, id, msg.sender, msg.value);
    }

    function surplus() external view returns (uint256) {
        return address(this).balance - totalLocked;
    }
}
