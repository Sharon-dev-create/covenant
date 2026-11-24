// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {IERC20, ILiquidityVault} from "./interfaces/IVaults.sol";
import {
    Reservation,
    ReservationState,
    InvalidAddress,
    InvalidIdentifier,
    InvalidAmount,
    Unauthorized,
    InvalidState,
    InsufficientLiquidity,
    InexactTransfer,
    TransferFailed,
    ReentrantCall
} from "./ProtocolTypes.sol";

/// @notice Local cash custody. The fixed consumer must be a purpose-bound integration before deployment.
contract LiquidityVault is ILiquidityVault {
    IERC20 public immutable asset;
    address public immutable manager;
    address public immutable consumer;

    mapping(address lender => uint256 amount) public free;
    mapping(address lender => uint256 amount) public reserved;
    mapping(address lender => mapping(bytes32 agreementId => uint256 amount)) public commitments;
    mapping(bytes32 id => Reservation reservation) public reservations;
    uint256 public totalFree;
    uint256 public totalReserved;

    bool private entered;

    uint256 private immutable deploymentChainId;

    constructor(IERC20 asset_, address manager_, address consumer_) {
        if (address(asset_).code.length == 0 || manager_ == address(0) || consumer_ == address(0)) {
            revert InvalidAddress();
        }
        asset = asset_;
        manager = manager_;
        consumer = consumer_;
        deploymentChainId = block.chainid;
    }

    modifier nonReentrant() {
        if (entered) revert ReentrantCall();
        entered = true;
        _;
        entered = false;
    }

    modifier onlyManager() {
        if (msg.sender != manager) revert Unauthorized();
        _;
    }

    function reservationId(bytes32 agreementId) public view returns (bytes32) {
        return keccak256(abi.encode("RESERVATION_V1", deploymentChainId, address(this), agreementId));
    }

    function deposit(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();
        uint256 beforeBalance = asset.balanceOf(address(this));
        uint256 beforeLender = asset.balanceOf(msg.sender);
        _transfer(abi.encodeCall(IERC20.transferFrom, (msg.sender, address(this), amount)));
        if (
            asset.balanceOf(address(this)) != beforeBalance + amount
                || beforeLender != asset.balanceOf(msg.sender) + amount
        ) revert InexactTransfer();
        free[msg.sender] += amount;
        totalFree += amount;
        emit LiquidityDeposited(msg.sender, amount);
    }

    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();
        if (amount > free[msg.sender]) revert InsufficientLiquidity();
        free[msg.sender] -= amount;
        totalFree -= amount;
        _pay(msg.sender, amount);
        emit LiquidityWithdrawn(msg.sender, amount);
    }

    /// @notice A local standing consent capped by amount. Updating to zero revokes unused consent.
    function setCommitment(bytes32 agreementId, uint256 amount) external nonReentrant {
        if (agreementId == bytes32(0)) revert InvalidIdentifier();
        if (reservations[reservationId(agreementId)].state != ReservationState.Absent) revert InvalidState();
        commitments[msg.sender][agreementId] = amount;
        emit CommitmentSet(msg.sender, agreementId, amount);
    }

    function reserve(bytes32 agreementId, address lender, uint256 amount)
        external
        nonReentrant
        onlyManager
        returns (bytes32 id)
    {
        if (agreementId == bytes32(0)) revert InvalidIdentifier();
        if (lender == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        id = reservationId(agreementId);
        if (reservations[id].state != ReservationState.Absent) revert InvalidState();
        if (amount > commitments[lender][agreementId]) revert Unauthorized();
        if (amount > free[lender]) revert InsufficientLiquidity();
        delete commitments[lender][agreementId];
        free[lender] -= amount;
        totalFree -= amount;
        reserved[lender] += amount;
        totalReserved += amount;
        reservations[id] = Reservation(lender, agreementId, amount, ReservationState.Reserved);
        emit LiquidityReserved(id, agreementId, lender, amount);
    }

    function cancel(bytes32 id) external nonReentrant onlyManager {
        Reservation storage reservation = _active(id);
        uint256 amount = _close(reservation, ReservationState.Returned, 0);
        emit ReservationReturned(id, amount);
    }

    /// @notice Consumes one reservation and returns its unspent part to the lender in the same transaction.
    function consume(bytes32 id, uint256 amount) external nonReentrant onlyManager {
        Reservation storage reservation = _active(id);
        if (amount == 0 || amount > reservation.amount) revert InvalidAmount();
        uint256 returned = _close(reservation, ReservationState.Consumed, amount);
        _pay(consumer, amount);
        emit ReservationConsumed(id, amount, returned);
    }

    function surplus() external view returns (uint256) {
        return asset.balanceOf(address(this)) - totalFree - totalReserved;
    }

    function _active(bytes32 id) private view returns (Reservation storage reservation) {
        if (id == bytes32(0)) revert InvalidIdentifier();
        reservation = reservations[id];
        if (reservation.state != ReservationState.Reserved) revert InvalidState();
    }

    function _close(Reservation storage reservation, ReservationState state, uint256 spent)
        private
        returns (uint256 returned)
    {
        uint256 amount = reservation.amount;
        address lender = reservation.lender;
        reservation.state = state;
        reservation.amount = 0;
        reserved[lender] -= amount;
        totalReserved -= amount;
        returned = amount - spent;
        free[lender] += returned;
        totalFree += returned;
    }

    function _pay(address recipient, uint256 amount) private {
        uint256 initialVault = asset.balanceOf(address(this));
        uint256 initialRecipient = asset.balanceOf(recipient);
        _transfer(abi.encodeCall(IERC20.transfer, (recipient, amount)));
        if (
            asset.balanceOf(address(this)) != initialVault - amount
                || asset.balanceOf(recipient) != initialRecipient + amount
        ) revert InexactTransfer();
    }

    function _transfer(bytes memory data) private {
        (bool success, bytes memory result) = address(asset).call(data);
        if (!success) revert TransferFailed();
        if (result.length == 0) return;
        if (result.length != 32 || abi.decode(result, (uint256)) != 1) revert TransferFailed();
    }
}
