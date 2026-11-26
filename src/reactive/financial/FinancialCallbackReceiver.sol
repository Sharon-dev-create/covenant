// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;
import {CreditManagerCore} from "../../CreditManagerCore.sol";
import {OmniPayer} from "../transport/OmniPayer.sol";
import {FinancialTriggerV1, FinancialTrigger} from "./FinancialTrigger.sol";
import {RiskSignalRegistry} from "./RiskSignalRegistry.sol";

/// @notice Authenticated testnet trigger ingress. Manager remains the sole financial ledger.
contract FinancialCallbackReceiver is OmniPayer {
    enum Outcome {
        None,
        Executed,
        SkippedUnknown,
        SkippedRecovered,
        SkippedExpired,
        SkippedTerminal,
        AlreadyDrawn,
        SkippedStale
    }

    struct Record {
        Outcome outcome;
        bytes32 operationId;
    }
    address public immutable reactive;
    CreditManagerCore public immutable manager;
    RiskSignalRegistry public immutable registry;
    mapping(bytes32 => Record) public records;
    bool private entered;
    error InvalidCallback();
    error ReentrantCallback();
    event Disposition(bytes32 indexed triggerId, bytes32 indexed agreementId, Outcome outcome, bytes32 operationId);
    event Duplicate(bytes32 indexed triggerId, Outcome originalOutcome, bytes32 operationId);

    constructor(address reactive_, address manager_, address registry_) OmniPayer(FinancialTrigger.BASE_PROXY) {
        if (
            block.chainid != FinancialTrigger.BASE || reactive_ == address(0) || manager_.code.length == 0
                || registry_.code.length == 0
        ) revert InvalidCallback();
        reactive = reactive_;
        manager = CreditManagerCore(manager_);
        registry = RiskSignalRegistry(registry_);
        if (address(registry.manager()) != manager_) revert InvalidCallback();
    }

    function onRiskSignal(address reactiveSender, bytes32 triggerId, FinancialTriggerV1 calldata t) external {
        if (
            msg.data.length != 4 + 9 * 32 || msg.sender != _SERVICE_PROVIDER || reactiveSender != reactive
                || block.chainid != FinancialTrigger.BASE || t.version != 1 || t.originChainId != FinancialTrigger.BASE
                || t.destinationChainId != FinancialTrigger.BASE || t.originRegistry != address(registry)
                || t.manager != address(manager) || t.agreementId == bytes32(0) || t.generation == 0
                || triggerId != FinancialTrigger.id(reactive, address(this), t)
        ) revert InvalidCallback();
        if (entered) revert ReentrantCallback();
        entered = true;
        Record memory previous = records[triggerId];
        if (previous.outcome != Outcome.None) {
            emit Duplicate(triggerId, previous.outcome, previous.operationId);
            entered = false;
            return;
        }
        (CreditManagerCore.Terms memory terms, CreditManagerCore.State state,) = manager.agreement(t.agreementId);
        Outcome result;
        bytes32 operation;
        if (state == CreditManagerCore.State.Absent) {
            result = Outcome.SkippedUnknown;
        } else if (state == CreditManagerCore.State.Drawn) {
            result = Outcome.AlreadyDrawn;
        } else if (state != CreditManagerCore.State.Active) {
            result = Outcome.SkippedTerminal;
        } else if (block.timestamp >= terms.drawDeadline) {
            result = Outcome.SkippedExpired;
        } else if (!registry.outstanding(t.agreementId) || registry.latestGeneration(t.agreementId) != t.generation) {
            result = Outcome.SkippedStale;
        } else if (!registry.eligible(t.agreementId)) {
            registry.retire(t.agreementId);
            result = Outcome.SkippedRecovered;
        } else {
            operation = manager.pendingDraw(t.agreementId);
            if (operation == bytes32(0)) operation = manager.observeRisk(t.agreementId);
            manager.executePending(t.agreementId, operation, terms.autonomousRepayment);
            if (!manager.completedDraw(operation) || manager.principal(t.agreementId) != terms.autonomousRepayment) {
                revert InvalidCallback();
            }
            result = Outcome.Executed;
        }
        records[triggerId] = Record(result, operation);
        emit Disposition(triggerId, t.agreementId, result, operation);
        entered = false;
    }
}
