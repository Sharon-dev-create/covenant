// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface ICollateralVault {
    event AgreementBound(bytes32 indexed agreementId, address indexed borrower, uint256 amount);
    function bind(bytes32 agreementId, address borrower, uint256 amount) external;
    event CollateralLocked(
        bytes32 indexed agreementId, bytes32 indexed positionId, address indexed borrower, uint256 amount
    );
    function lock(bytes32 agreementId) external payable returns (bytes32 positionId);
}

interface ILiquidityVault {
    event LiquidityDeposited(address indexed lender, uint256 amount);
    event LiquidityWithdrawn(address indexed lender, uint256 amount);
    event CommitmentSet(address indexed lender, bytes32 indexed agreementId, uint256 amount);
    event LiquidityReserved(
        bytes32 indexed reservationId, bytes32 indexed agreementId, address indexed lender, uint256 amount
    );
    event ReservationReturned(bytes32 indexed reservationId, uint256 amount);
    event ReservationConsumed(bytes32 indexed reservationId, uint256 spent, uint256 returned);

    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function setCommitment(bytes32 agreementId, uint256 amount) external;
    function reserve(bytes32 agreementId, address lender, uint256 amount) external returns (bytes32);
    function cancel(bytes32 reservationId) external;
    function consume(bytes32 reservationId, uint256 amount) external;
}
