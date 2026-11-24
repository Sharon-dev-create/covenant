// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

enum CollateralState {
    Absent,
    Locked
}

enum ReservationState {
    Absent,
    Reserved,
    Returned,
    Consumed
}

struct CollateralPosition {
    address borrower;
    bytes32 agreementId;
    uint256 amount;
    CollateralState state;
}

struct Reservation {
    address lender;
    bytes32 agreementId;
    uint256 amount;
    ReservationState state;
}

error InvalidAddress();
error InvalidIdentifier();
error InvalidAmount();
error Unauthorized();
error InvalidState();
error InsufficientLiquidity();
error InexactTransfer();
error TransferFailed();
error ReentrantCall();
