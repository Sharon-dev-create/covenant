// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @notice Minimal read surface of the Omni system contract or callback proxy used for fee accounting.
interface IOmniDebtProvider {
    function debt(address account) external view returns (uint256);
}

/// @notice Local, minimal implementation of the documented Omni payer wire behavior.
/// @dev Mirrors the ABI and accounting rules of reactive-lib-omni/AbstractPayer at commit
///      3ade0dcf1d27e67e5783ef807e73a1b9e0c0cce8 without importing the full library. The provider
///      is immutable and must be the Lasna system contract for reactive probes or the destination
///      callback proxy for receiver probes.
abstract contract OmniPayer {
    error NotAuthorized(address sender, address provider);
    error InsufficientFunds(uint256 required, uint256 available);
    error TransferFailed();
    error ZeroProvider();

    address public immutable _SERVICE_PROVIDER;

    constructor(address provider_) {
        if (provider_ == address(0)) revert ZeroProvider();
        _SERVICE_PROVIDER = provider_;
    }

    receive() external payable {}

    modifier onlyServiceProvider() {
        if (msg.sender != _SERVICE_PROVIDER) revert NotAuthorized(msg.sender, _SERVICE_PROVIDER);
        _;
    }

    /// @notice Called by the immutable provider when fees are due.
    function pay(uint256 amount) external onlyServiceProvider {
        _pay(payable(msg.sender), amount);
    }

    /// @notice Settles any recorded debt from this contract's own balance.
    function coverDebt() external {
        _coverDebt();
    }

    function _coverDebt() internal {
        uint256 amount = IOmniDebtProvider(_SERVICE_PROVIDER).debt(address(this));
        _pay(payable(_SERVICE_PROVIDER), amount);
    }

    function _pay(address payable recipient, uint256 amount) internal {
        uint256 available = address(this).balance;
        if (available < amount) revert InsufficientFunds(amount, available);
        if (amount == 0) return;

        // Recipient is either the immutable provider or its authenticated caller.
        // forge-lint: disable-next-line(arbitrary-send-eth)
        (bool success,) = recipient.call{value: amount}(new bytes(0));
        if (!success) revert TransferFailed();
    }
}
