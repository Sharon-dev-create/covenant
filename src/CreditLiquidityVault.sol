// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {LiquidityVault} from "./LiquidityVault.sol";
import {IERC20} from "./interfaces/IVaults.sol";
import {
    Reservation,
    ReservationState,
    InvalidIdentifier,
    InvalidAddress,
    InvalidAmount,
    InvalidState,
    InexactTransfer,
    TransferFailed
} from "./ProtocolTypes.sol";

/// @notice Local credit vault. Repayment authorization is enforced by its immutable manager.
contract CreditLiquidityVault is LiquidityVault {
    mapping(bytes32 paymentId => bool used) public repaymentUsed;

    event RepaymentCredited(
        bytes32 indexed reservationId, bytes32 indexed paymentId, address indexed lender, address payer, uint256 amount
    );

    constructor(IERC20 asset_, address manager_, address consumer_) LiquidityVault(asset_, manager_, consumer_) {}

    function creditRepayment(bytes32 id, bytes32 paymentId, address payer, uint256 amount)
        external
        nonReentrant
        onlyManager
    {
        if (id == bytes32(0) || paymentId == bytes32(0)) revert InvalidIdentifier();
        if (payer == address(0) || payer == address(this)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        Reservation storage reservation = reservations[id];
        if (reservation.state != ReservationState.Consumed || repaymentUsed[paymentId]) revert InvalidState();
        repaymentUsed[paymentId] = true;
        uint256 beforeVault = asset.balanceOf(address(this));
        uint256 beforePayer = asset.balanceOf(payer);
        (bool ok, bytes memory result) =
            address(asset).call(abi.encodeCall(IERC20.transferFrom, (payer, address(this), amount)));
        if (!ok || (result.length != 0 && (result.length != 32 || abi.decode(result, (uint256)) != 1))) {
            revert TransferFailed();
        }
        if (asset.balanceOf(address(this)) != beforeVault + amount || asset.balanceOf(payer) + amount != beforePayer) {
            revert InexactTransfer();
        }
        free[reservation.lender] += amount;
        totalFree += amount;
        emit RepaymentCredited(id, paymentId, reservation.lender, payer, amount);
    }
}
