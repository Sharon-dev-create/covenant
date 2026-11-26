// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;
import {CreditManagerCore, ILocalMarket} from "../../CreditManagerCore.sol";

/// @notice Testnet signal hints for a fixed simulated market; never grants financial authority.
contract RiskSignalRegistry {
    CreditManagerCore public immutable manager;
    address public immutable market;
    mapping(bytes32 => uint64) public latestGeneration;
    mapping(bytes32 => bool) public outstanding;
    mapping(bytes32 => uint256) public lastEmission;
    uint256 public constant RESIGNAL_DELAY = 60 seconds;
    error InvalidSignal();
    event RiskSignaled(bytes32 indexed agreementId, uint64 indexed generation, address indexed manager);
    event RiskSignalRetired(bytes32 indexed agreementId, uint64 indexed generation);

    constructor(address manager_, address market_) {
        if (block.chainid != 84532 || manager_.code.length == 0 || market_.code.length == 0) revert InvalidSignal();
        manager = CreditManagerCore(manager_);
        market = market_;
    }

    function signal(bytes32 agreementId) external returns (uint64 generation) {
        (CreditManagerCore.Terms memory t, CreditManagerCore.State state,) = manager.agreement(agreementId);
        if (
            state != CreditManagerCore.State.Active || t.market != market || block.timestamp >= t.drawDeadline
                || !_eligible(t)
        ) revert InvalidSignal();
        generation = latestGeneration[agreementId];
        if (outstanding[agreementId]) return generation;
        generation++;
        latestGeneration[agreementId] = generation;
        outstanding[agreementId] = true;
        lastEmission[agreementId] = block.timestamp;
        emit RiskSignaled(agreementId, generation, address(manager));
    }

    /// @notice Re-emit an unchanged eligible hint if no Reactive request was recorded.
    function resignal(bytes32 agreementId) external {
        (CreditManagerCore.Terms memory t, CreditManagerCore.State state,) = manager.agreement(agreementId);
        if (
            !outstanding[agreementId] || state != CreditManagerCore.State.Active || t.market != market
                || block.timestamp >= t.drawDeadline || block.timestamp < lastEmission[agreementId] + RESIGNAL_DELAY
                || !_eligible(t)
        ) revert InvalidSignal();
        lastEmission[agreementId] = block.timestamp;
        emit RiskSignaled(agreementId, latestGeneration[agreementId], address(manager));
    }

    function retire(bytes32 agreementId) external {
        if (!outstanding[agreementId]) revert InvalidSignal();
        (CreditManagerCore.Terms memory t, CreditManagerCore.State state,) = manager.agreement(agreementId);
        if (state == CreditManagerCore.State.Active && block.timestamp < t.drawDeadline && _eligible(t)) {
            revert InvalidSignal();
        }
        if (state == CreditManagerCore.State.Active && manager.pendingDraw(agreementId) != bytes32(0) && !_eligible(t))
        {
            manager.clearRecoveredRisk(agreementId);
        }
        outstanding[agreementId] = false;
        emit RiskSignalRetired(agreementId, latestGeneration[agreementId]);
    }

    function eligible(bytes32 agreementId) external view returns (bool) {
        (CreditManagerCore.Terms memory t, CreditManagerCore.State state,) = manager.agreement(agreementId);
        return state == CreditManagerCore.State.Active && t.market == market && block.timestamp < t.drawDeadline
            && _eligible(t);
    }

    function _eligible(CreditManagerCore.Terms memory t) private view returns (bool) {
        ILocalMarket m = ILocalMarket(market);
        return m.isDistressed(t.borrower) && m.health(t.borrower) <= t.maxHealth
            && m.debt(t.borrower) >= t.autonomousRepayment;
    }
}
