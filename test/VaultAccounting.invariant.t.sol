// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {CollateralVault} from "../src/CollateralVault.sol";
import {LiquidityVault} from "../src/LiquidityVault.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {Reservation, ReservationState} from "../src/ProtocolTypes.sol";
import {Vm} from "./Vaults.t.sol";

contract VaultHandler {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address public constant CONSUMER = address(0xCAFE);
    MockUSDC public immutable token = new MockUSDC();
    LiquidityVault public immutable vault = new LiquidityVault(token, address(this), CONSUMER);
    CollateralVault public immutable collateral = new CollateralVault(address(this));
    bytes32[] public ids;
    bytes32[] private activeIds;
    mapping(bytes32 => Reservation) public expected;
    mapping(address => uint256) public expectedFree;
    mapping(address => uint256) public expectedReserved;
    uint256 public inflows;
    uint256 public outflows;
    uint256 public consumed;
    uint256 public donated;
    uint256 public locked;
    uint256 public forced;

    function lend(uint8 lenderSeed, uint64 amountSeed) external {
        address lender = actor(lenderSeed);
        uint256 amount = uint256(amountSeed) + 1;
        _deposit(lender, amount);
    }

    function _deposit(address lender, uint256 amount) private {
        token.mint(lender, amount);
        vm.prank(lender);
        token.approve(address(vault), amount);
        vm.prank(lender);
        vault.deposit(amount);
        inflows += amount;
        expectedFree[lender] += amount;
    }

    function withdraw(uint8 lenderSeed, uint64 amountSeed) external {
        address lender = actor(lenderSeed);
        uint256 amount = _fundAndBound(lender, amountSeed);
        vm.prank(lender);
        vault.withdraw(amount);
        expectedFree[lender] -= amount;
        outflows += amount;
    }

    function reserve(uint8 lenderSeed, uint64 amountSeed) external {
        _reserve(actor(lenderSeed), amountSeed);
    }

    function _fundAndBound(address lender, uint64 seed) private returns (uint256) {
        if (expectedFree[lender] == 0) _deposit(lender, uint256(seed) + 1);
        return uint256(seed) % expectedFree[lender] + 1;
    }

    function _reserve(address lender, uint64 seed) private {
        uint256 amount = _fundAndBound(lender, seed);
        bytes32 agreement = bytes32(ids.length + 1);
        vm.prank(lender);
        vault.setCommitment(agreement, amount);
        bytes32 id = vault.reserve(agreement, lender, amount);
        ids.push(id);
        activeIds.push(id);
        expected[id] = Reservation(lender, agreement, amount, ReservationState.Reserved);
        expectedFree[lender] -= amount;
        expectedReserved[lender] += amount;
    }

    function cancel(uint64 indexSeed, uint64 amountSeed) external {
        (bytes32 id, Reservation storage entry) = _takeActive(indexSeed, amountSeed);
        vault.cancel(id);
        _close(entry, ReservationState.Returned, 0);
    }

    function consume(uint64 indexSeed, uint64 amountSeed) external {
        (bytes32 id, Reservation storage entry) = _takeActive(indexSeed, amountSeed);
        uint256 amount = uint256(amountSeed) % entry.amount + 1;
        vault.consume(id, amount);
        _close(entry, ReservationState.Consumed, amount);
        consumed += amount;
    }

    function _takeActive(uint64 indexSeed, uint64 amountSeed) private returns (bytes32 id, Reservation storage entry) {
        if (activeIds.length == 0) _reserve(actor(uint8(indexSeed % 3)), amountSeed);
        uint256 index = uint256(indexSeed) % activeIds.length;
        id = activeIds[index];
        activeIds[index] = activeIds[activeIds.length - 1];
        activeIds.pop();
        entry = expected[id];
    }

    function _close(Reservation storage entry, ReservationState state, uint256 spent) private {
        expectedReserved[entry.lender] -= entry.amount;
        expectedFree[entry.lender] += entry.amount - spent;
        entry.amount = 0;
        entry.state = state;
    }

    function donate(uint64 amountSeed) external {
        uint256 amount = uint256(amountSeed) + 1;
        token.mint(address(vault), amount);
        donated += amount;
    }

    function forceEther(uint64 amountSeed) external {
        uint256 amount = uint256(amountSeed) + 1;
        vm.deal(address(collateral), address(collateral).balance + amount);
        forced += amount;
    }

    function lock(uint8 borrowerSeed, uint64 amountSeed) external {
        address borrower = actor(borrowerSeed);
        bytes32 agreement = keccak256(abi.encode(locked));
        uint256 amount = uint256(amountSeed) + 1;
        collateral.bind(agreement, borrower, amount);
        vm.deal(borrower, amount);
        vm.prank(borrower);
        collateral.lock{value: amount}(agreement);
        locked += amount;
    }

    function actor(uint8 seed) public pure returns (address) {
        return address(uint160(256 + uint256(seed) % 3));
    }

    function reservationCount() external view returns (uint256) {
        return ids.length;
    }
}

contract VaultAccountingInvariant {
    VaultHandler private handler;

    function setUp() public {
        handler = new VaultHandler();
    }

    function targetContracts() external view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    struct SelectorTarget {
        address addr;
        bytes4[] selectors;
    }

    function targetSelectors() external view returns (SelectorTarget[] memory targets) {
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = VaultHandler.lend.selector;
        selectors[1] = VaultHandler.withdraw.selector;
        selectors[2] = VaultHandler.reserve.selector;
        selectors[3] = VaultHandler.cancel.selector;
        selectors[4] = VaultHandler.consume.selector;
        selectors[5] = VaultHandler.donate.selector;
        selectors[6] = VaultHandler.forceEther.selector;
        selectors[7] = VaultHandler.lock.selector;
        targets = new SelectorTarget[](1);
        targets[0] = SelectorTarget(address(handler), selectors);
    }

    function invariant_ManagedCashAndCollateralReconcile() public view {
        LiquidityVault vault = handler.vault();
        uint256 cash = handler.inflows() - handler.outflows() - handler.consumed();
        assert(vault.totalFree() + vault.totalReserved() == cash);
        assert(vault.surplus() == handler.donated());
        assert(handler.token().balanceOf(address(vault)) == cash + handler.donated());
        assert(handler.collateral().totalLocked() == handler.locked());
        assert(address(handler.collateral()).balance == handler.locked() + handler.forced());
        assert(handler.collateral().surplus() == handler.forced());
        assert(handler.token().balanceOf(handler.CONSUMER()) == handler.consumed());
        assert(handler.collateral().totalReleased() == 0);

        uint256 free;
        uint256 reserved;
        for (uint8 i; i < 3; ++i) {
            address lender = handler.actor(i);
            assert(vault.free(lender) == handler.expectedFree(lender));
            assert(vault.reserved(lender) == handler.expectedReserved(lender));
            free += vault.free(lender);
            reserved += vault.reserved(lender);
        }
        assert(free == vault.totalFree() && reserved == vault.totalReserved());

        uint256 reservationSum;
        for (uint256 i; i < handler.reservationCount(); ++i) {
            bytes32 id = handler.ids(i);
            (address lender, bytes32 agreement, uint256 amount, ReservationState state) = vault.reservations(id);
            (address owner, bytes32 expectedAgreement, uint256 expectedAmount, ReservationState expectedState) =
                handler.expected(id);
            assert(lender == owner && agreement == expectedAgreement);
            assert(amount == expectedAmount && state == expectedState);
            assert((amount != 0) == (state == ReservationState.Reserved));
            reservationSum += amount;
        }
        assert(reservationSum == reserved);
    }
}
