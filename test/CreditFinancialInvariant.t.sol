// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {CreditManager} from "../src/CreditManager.sol";
import {CreditManagerCore} from "../src/CreditManagerCore.sol";
import {CreditLiquidityVault} from "../src/CreditLiquidityVault.sol";
import {LocalCreditFactory} from "../src/LocalCreditFactory.sol";
import {CollateralVault} from "../src/CollateralVault.sol";
import {CollateralState, ReservationState} from "../src/ProtocolTypes.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {
    LocalCollateralFixture,
    LocalOracleFixture,
    LocalLendingMarket,
    LocalRepaymentAdapter
} from "./mocks/LocalCreditFixtures.sol";

interface FinancialVm {
    function addr(uint256) external returns (address);
    function sign(uint256, bytes32) external returns (uint8, bytes32, bytes32);
    function prank(address) external;
    function warp(uint256) external;
    function deal(address, uint256) external;
}

contract FinancialHandler {
    FinancialVm private constant vm = FinancialVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant D = 630720000;
    uint256 private constant CAP = 500e6;
    uint256 private constant DRAW = 200e6;
    MockUSDC public immutable token;
    LocalCollateralFixture public immutable collateral;
    LocalOracleFixture public immutable oracle;
    LocalLendingMarket public immutable market;
    LocalRepaymentAdapter public immutable adapter;
    CreditManager public immutable manager;
    CreditLiquidityVault public immutable vault;
    CollateralVault public immutable custody;

    struct Metrics {
        uint256 calls;
        uint256 ineligible;
        uint256 transitions;
        uint256 financial;
        uint256 amount;
    }
    mapping(bytes4 => Metrics) public metrics;
    mapping(bytes32 => uint256) public transitionCounts;
    bool private acted;
    modifier measured() {
        metrics[msg.sig].calls++;
        acted = false;
        _;
        if (!acted) metrics[msg.sig].ineligible++;
    }

    function _success(uint256 amount, bool financial) private {
        Metrics storage m = metrics[msg.sig];
        m.transitions++;
        if (financial) m.financial++;
        m.amount += amount;
        acted = true;
    }

    function _select(uint256 seed, uint8 kind) private view returns (uint256) {
        uint256 n = loans.length;
        if (n == 0) return type(uint256).max;
        for (uint256 i; i < n; i++) {
            uint256 index = (seed % n + i) % n;
            Ghost storage g = loans[index];
            bool eligible;
            if (kind == 1) eligible = g.state == 1 && block.timestamp < g.deadline;
            if (kind == 2) eligible = g.state == 1 || g.state == 2;
            if (kind == 3) eligible = g.state == 2 && g.op == bytes32(0) && block.timestamp < g.deadline;
            if (kind == 4) eligible = g.state == 2 && g.op != bytes32(0) && block.timestamp < g.deadline;
            if (kind == 5) eligible = (g.state == 1 || g.state == 2) && block.timestamp >= g.deadline;
            if (kind == 6) eligible = g.state == 2 && g.op != bytes32(0);
            if (kind == 7) eligible = g.state == 3 || g.state == 5;
            if (kind == 8) eligible = g.state == 3 && block.timestamp >= g.maturity;
            if (eligible) return index;
        }
        return type(uint256).max;
    }

    struct Ghost {
        bytes32 id;
        bytes32 op;
        address borrower;
        address lender;
        uint256 principal;
        uint256 interest;
        uint256 remainder;
        uint256 last;
        uint256 interestRecognized;
        uint256 interestPaid;
        uint256 principalPaid;
        uint256 maturity;
        uint256 deadline;
        uint8 state;
    }
    Ghost[] private loans;
    mapping(address => uint256) public free;
    mapping(address => uint256) public reserved;
    uint256 public deposits;
    uint256 public withdrawals;
    uint256 public draws;
    uint256 public repayments;
    uint256 public donations;
    uint256 public nonce;
    uint256 public paymentNonce;

    constructor() {
        custody = new CollateralVault(address(this));
        token = new MockUSDC();
        collateral = new LocalCollateralFixture();
        oracle = new LocalOracleFixture();
        market = new LocalLendingMarket(address(token));
        adapter = new LocalRepaymentAdapter(address(token), address(market));
        LocalCreditFactory factory =
            new LocalCreditFactory(address(token), address(collateral), address(oracle), address(adapter));
        manager = CreditManager(factory.manager());
        vault = CreditLiquidityVault(factory.vault());
        adapter.configure(false, false, false, address(manager), bytes32(0), bytes32(0));
    }

    function loanCount() external view returns (uint256) {
        return loans.length;
    }

    function loan(uint256 i) external view returns (Ghost memory) {
        return loans[i];
    }

    function actor(uint256 i) public returns (address) {
        return vm.addr(0xA110 + i % 3);
    }

    function lender(uint256 i) public returns (address) {
        return vm.addr(0xB110 + i % 3);
    }

    function deposit(uint8 who, uint32 seed) external measured {
        _deposit(lender(who), uint256(seed) % 100e6 + 1);
        assert(vault.free(lender(who)) == free[lender(who)]);
        _success(uint256(seed) % 100e6 + 1, true);
    }

    function _deposit(address who, uint256 amount) private {
        token.mint(who, amount);
        vm.prank(who);
        token.approve(address(vault), amount);
        vm.prank(who);
        vault.deposit(amount);
        free[who] += amount;
        deposits += amount;
    }

    function register(uint8 who) external measured {
        uint256 index = who % 3;
        uint256 n = ++nonce;
        address b = vm.addr(0xA110 + n);
        address l = lender(index);
        CreditManagerCore.Terms memory t = CreditManagerCore.Terms(
            b,
            l,
            address(custody),
            block.chainid,
            bytes32(0),
            1 ether,
            address(market),
            b,
            bytes32(uint256(1)),
            CAP,
            DRAW,
            11e17,
            n,
            n,
            uint64(block.timestamp + 30 days),
            uint64(block.timestamp + 60 days),
            uint64(block.timestamp + 90 days),
            1 days,
            5000
        );
        t.lotId = keccak256(abi.encode("LOT_V1", t.collateralChainId, t.collateralVault, manager.agreementId(t)));
        bytes32 digest = manager.digest(t);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xA110 + n, digest);
        bytes memory bs = abi.encodePacked(r, s, v);
        (v, r, s) = vm.sign(0xB110 + index, digest);
        bytes32 id = manager.register(t, bs, abi.encodePacked(r, s, v));
        custody.bind(id, b, 1 ether);
        vm.deal(b, 1 ether);
        vm.prank(b);
        assert(custody.lock{value: 1 ether}(id) == t.lotId);
        loans.push(Ghost(id, bytes32(0), b, l, 0, 0, 0, 0, 0, 0, 0, t.maturity + t.grace, t.drawDeadline, 1));
        assert(custody.borrowers(id) == b && custody.totalLocked() == loans.length * 1 ether);
        _success(1 ether, false);
    }

    function activate(uint256 seed) external measured {
        uint256 selected = _select(seed, 1);
        if (selected == type(uint256).max) return;
        Ghost storage g = loans[selected];
        if (g.state != 1 || block.timestamp >= g.deadline) return;
        if (free[g.lender] < CAP) _deposit(g.lender, CAP - free[g.lender]);
        (CreditManagerCore.Terms memory t,,) = manager.agreement(g.id);
        collateral.set(g.id, t.lotId, g.borrower, 1 ether);
        oracle.set(2000e6, block.timestamp);
        vm.prank(g.lender);
        vault.setCommitment(g.id, CAP);
        manager.activate(g.id);
        free[g.lender] -= CAP;
        reserved[g.lender] += CAP;
        g.state = 2;
        assert(vault.reserved(g.lender) == reserved[g.lender]);
        transitionCounts["reservation"]++;
        _success(CAP, true);
    }

    function cancel(uint256 seed) external measured {
        uint256 selected = _select(seed, 2);
        if (selected == type(uint256).max) return;
        Ghost storage g = loans[selected];
        if (g.state != 1 && g.state != 2) return;
        vm.prank(g.borrower);
        manager.cancelUnused(g.id);
        if (g.state == 2) {
            reserved[g.lender] -= CAP;
            free[g.lender] += CAP;
        }
        g.state = 4;
        assert(vault.free(g.lender) == free[g.lender]);
        _success(0, false);
    }

    function observe(uint256 seed) external measured {
        uint256 selected = _select(seed, 3);
        if (selected == type(uint256).max) return;
        Ghost storage g = loans[selected];
        if (g.state != 2 || g.op != bytes32(0) || block.timestamp >= g.deadline) return;
        market.setPosition(g.borrower, 800e6, 840e6);
        g.op = manager.observeRisk(g.id);
        assert(g.op != bytes32(0));
        _success(0, false);
    }

    function execute(uint256 seed) external measured {
        uint256 selected = _select(seed, 4);
        if (selected == type(uint256).max) return;
        Ghost storage g = loans[selected];
        if (g.state != 2 || g.op == bytes32(0) || block.timestamp >= g.deadline) return;
        market.setPosition(g.borrower, 800e6, 840e6);
        oracle.set(2000e6, block.timestamp);
        manager.executePending(g.id, g.op, DRAW);
        reserved[g.lender] -= CAP;
        free[g.lender] += CAP - DRAW;
        draws += DRAW;
        g.principal = DRAW;
        g.last = block.timestamp;
        g.state = 3;
        assert(manager.principal(g.id) == DRAW && market.debt(g.borrower) == 600e6);
        _success(DRAW, true);
    }

    function advance(uint32 secondsSeed) external measured {
        vm.warp(block.timestamp + uint256(secondsSeed % 30 days) + 1);
        _success(0, false);
    }

    function expire(uint256 seed) external measured {
        uint256 selected = _select(seed, 5);
        if (selected == type(uint256).max) return;
        Ghost storage g = loans[selected];
        if ((g.state != 1 && g.state != 2) || block.timestamp < g.deadline) return;
        manager.expireUnused(g.id);
        if (g.state == 2) {
            reserved[g.lender] -= CAP;
            free[g.lender] += CAP;
        }
        g.state = 4;
        assert(vault.free(g.lender) == free[g.lender]);
        _success(0, false);
    }

    function revoke(uint8 seed) external measured {
        address b = actor(seed);
        address l = lender(seed);
        uint256 n = ++nonce;
        vm.prank(b);
        manager.invalidateBorrowerNonce(n);
        vm.prank(l);
        manager.invalidateLenderNonce(n);
        assert(manager.usedBorrowerNonce(b, n) && manager.usedLenderNonce(l, n));
        _success(0, false);
    }

    function clearRecovered(uint256 seed) external measured {
        uint256 selected = _select(seed, 6);
        if (selected == type(uint256).max) return;
        Ghost storage g = loans[selected];
        if (g.state != 2 || g.op == bytes32(0)) return;
        market.setPosition(g.borrower, 800e6, 1000e6);
        manager.clearRecoveredRisk(g.id);
        g.op = bytes32(0);
        _success(0, false);
    }

    function checkpoint(uint256 seed) external measured {
        uint256 selected = _select(seed, 7);
        if (selected == type(uint256).max) return;
        Ghost storage g = loans[selected];
        if (g.state != 3 && g.state != 5) return;
        _accrue(g);
        manager.accrueInterest(g.id);
        assert(manager.accruedInterest(g.id) == g.interest);
        _success(0, false);
    }

    function repay(uint256 seed, uint64 amountSeed, bool full) external measured {
        uint256 selected = _select(seed, 7);
        if (selected == type(uint256).max) return;
        Ghost storage g = loans[selected];
        if (g.state != 3 && g.state != 5) return;
        bool wasDefault = g.state == 5;
        _accrue(g);
        uint256 total = g.principal + g.interest + (g.remainder == 0 ? 0 : 1);
        uint256 amount = full ? total : uint256(amountSeed) % total + 1;
        if (amount == total && g.remainder != 0) {
            g.interest++;
            g.interestRecognized++;
            g.remainder = 0;
        }
        uint256 ip = amount < g.interest ? amount : g.interest;
        uint256 pp = amount - ip;
        g.interest -= ip;
        g.principal -= pp;
        g.interestPaid += ip;
        g.principalPaid += pp;
        if (g.principal == 0 && g.remainder != 0) {
            g.interest++;
            g.interestRecognized++;
            g.remainder = 0;
        }
        if (g.principal == 0 && g.interest == 0) g.state = 4;
        token.mint(g.borrower, amount);
        vm.prank(g.borrower);
        token.approve(address(vault), amount);
        vm.prank(g.borrower);
        manager.repay(g.id, amount, ++paymentNonce);
        free[g.lender] += amount;
        repayments += amount;
        assert(manager.principal(g.id) == g.principal && vault.free(g.lender) == free[g.lender]);
        if (g.state == 4) transitionCounts["fullRepay"]++;
        else transitionCounts["partialRepay"]++;
        if (wasDefault) transitionCounts["afterDefault"]++;
        _success(amount, true);
    }

    function markDefault(uint256 seed) external measured {
        uint256 selected = _select(seed, 8);
        if (selected == type(uint256).max) return;
        Ghost storage g = loans[selected];
        if (g.state != 3 || block.timestamp < g.maturity) return;
        _accrue(g);
        manager.markDefault(g.id);
        g.state = 5;
        assert(manager.principal(g.id) == g.principal);
        _success(0, false);
    }

    function withdraw(uint8 who, uint32 seed) external measured {
        address l = lender(who);
        if (free[l] == 0) _deposit(l, uint256(seed) % 10e6 + 1);
        uint256 amount = uint256(seed) % free[l] + 1;
        vm.prank(l);
        vault.withdraw(amount);
        free[l] -= amount;
        withdrawals += amount;
        assert(vault.free(l) == free[l]);
        _success(amount, true);
    }

    function donate(uint32 seed) external measured {
        uint256 amount = uint256(seed) + 1;
        token.mint(address(vault), amount);
        donations += amount;
        assert(vault.surplus() == donations);
        _success(amount, true);
    }

    function _accrue(Ghost storage g) private {
        if (g.principal != 0) {
            uint256 n = g.principal * (block.timestamp - g.last) + g.remainder;
            uint256 interest = n / D;
            g.remainder = n % D;
            g.interest += interest;
            g.interestRecognized += interest;
        }
        g.last = block.timestamp;
    }
}

contract ForceCollateralEther {
    constructor() payable {}

    function force(address payable target) external {
        selfdestruct(target);
    }
}

contract CreditFinancialInvariant {
    FinancialVm private constant vm = FinancialVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    event Counts(
        bytes4 selector, uint256 calls, uint256 ineligible, uint256 transitions, uint256 financial, uint256 amount
    );

    function _report(bytes4 selector) private {
        (uint256 calls, uint256 ineligible, uint256 transitions, uint256 financial, uint256 amount) =
            handler.metrics(selector);
        emit Counts(selector, calls, ineligible, transitions, financial, amount);
    }

    FinancialHandler handler;

    function setUp() public {
        handler = new FinancialHandler();
    }

    function testReferenceModelDirectedLifecycle() public {
        handler.register(0);
        handler.activate(0);
        handler.observe(0);
        handler.execute(0);
        invariant_CashAndDebtMatchIndependentLedger();
        handler.advance(1 days);
        handler.checkpoint(0);
        handler.repay(0, 10e6, false);
        invariant_CashAndDebtMatchIndependentLedger();
        handler.register(1);
        handler.activate(1);
        handler.cancel(1);
        handler.donate(42);
        handler.withdraw(0, 1);
        invariant_CashAndDebtMatchIndependentLedger();
        handler.advance(29 days);
        handler.advance(29 days);
        handler.advance(29 days);
        handler.advance(29 days);
        handler.markDefault(0);
        handler.repay(0, 0, true);
        invariant_CashAndDebtMatchIndependentLedger();
    }

    function testMeasuredRareTransitionsAndActualCustody() public {
        handler.register(0);
        handler.register(1);
        handler.register(2);
        handler.activate(0);
        handler.activate(1);
        handler.activate(2);
        handler.observe(0);
        handler.clearRecovered(0);
        handler.observe(0);
        handler.execute(0);
        handler.cancel(1);
        handler.deposit(1, 3);
        handler.donate(8);
        handler.withdraw(1, 1);
        handler.revoke(1);
        handler.advance(29 days);
        handler.advance(2 days);
        handler.advance(29 days);
        handler.expire(2);
        (,, uint256 expired,,) = handler.metrics(handler.expire.selector);
        assert(expired == 1);
        handler.checkpoint(0);
        handler.repay(0, 100, false);
        handler.advance(29 days);
        handler.advance(29 days);
        handler.advance(29 days);
        handler.markDefault(0);
        handler.repay(0, 0, true);
        invariant_CashAndDebtMatchIndependentLedger();
        assert(handler.transitionCounts("reservation") == 3);
        assert(handler.transitionCounts("partialRepay") == 1);
        assert(handler.transitionCounts("fullRepay") == 1);
        assert(handler.transitionCounts("afterDefault") == 1);
        FinancialHandler.Ghost memory g = handler.loan(0);
        CollateralVault custody = handler.custody();
        vm.prank(address(handler));
        (bool rebound,) = address(custody).call(abi.encodeCall(custody.bind, (g.id, address(0x1234), 1 ether)));
        assert(!rebound);
        vm.deal(address(this), 1 ether);
        ForceCollateralEther force = new ForceCollateralEther{value: 1 ether}();
        force.force(payable(address(custody)));
        assert(custody.surplus() == 1 ether && custody.totalLocked() == 3 ether);
        invariant_CashAndDebtMatchIndependentLedger();
        _report(handler.register.selector);
        _report(handler.activate.selector);
        _report(handler.cancel.selector);
        _report(handler.expire.selector);
        _report(handler.observe.selector);
        _report(handler.clearRecovered.selector);
        _report(handler.execute.selector);
        _report(handler.checkpoint.selector);
        _report(handler.repay.selector);
        _report(handler.markDefault.selector);
        _report(handler.withdraw.selector);
        _report(handler.donate.selector);
    }

    function testFuzzRepaymentLedgerSequence(uint32 first, uint32 second, uint64 payment, uint32 donation) public {
        handler.register(0);
        handler.activate(0);
        handler.observe(0);
        handler.execute(0);
        handler.advance(first % 10 days);
        handler.checkpoint(0);
        invariant_CashAndDebtMatchIndependentLedger();
        handler.repay(0, payment % 100e6, false);
        invariant_CashAndDebtMatchIndependentLedger();
        _failedRepaymentChecks();
        invariant_CashAndDebtMatchIndependentLedger();
        handler.donate(donation);
        handler.withdraw(0, donation);
        handler.advance(second % 10 days);
        handler.checkpoint(0);
        invariant_CashAndDebtMatchIndependentLedger();
        handler.advance(29 days);
        handler.advance(29 days);
        handler.advance(29 days);
        handler.advance(29 days);
        handler.markDefault(0);
        invariant_CashAndDebtMatchIndependentLedger();
        handler.repay(0, 1, false);
        invariant_CashAndDebtMatchIndependentLedger();
        handler.repay(0, 0, true);
        invariant_CashAndDebtMatchIndependentLedger();
    }

    function testDeterministicMultiAgreementCampaign() public {
        uint8[3] memory seeds = [uint8(0), uint8(1), uint8(2)];
        for (uint256 i; i < seeds.length; i++) {
            handler.register(seeds[i]);
            invariant_CashAndDebtMatchIndependentLedger();
            handler.activate(i);
            invariant_CashAndDebtMatchIndependentLedger();
        }
        for (uint256 i; i < seeds.length; i++) {
            handler.observe(i);
            invariant_CashAndDebtMatchIndependentLedger();
            handler.execute(i);
            invariant_CashAndDebtMatchIndependentLedger();
        }
        handler.advance(1 days);
        for (uint256 i; i < seeds.length; i++) {
            handler.checkpoint(i);
            invariant_CashAndDebtMatchIndependentLedger();
            handler.repay(i, uint64(1e6 + i), false);
            invariant_CashAndDebtMatchIndependentLedger();
            handler.repay(i, 0, true);
            invariant_CashAndDebtMatchIndependentLedger();
        }
        handler.execute(0); // Deliberately ineligible, measured separately.
        _report(handler.register.selector);
        _report(handler.activate.selector);
        _report(handler.observe.selector);
        _report(handler.execute.selector);
        _report(handler.checkpoint.selector);
        _report(handler.repay.selector);
        assert(handler.transitionCounts("reservation") == 3);
        assert(handler.transitionCounts("partialRepay") == 3);
        assert(handler.transitionCounts("fullRepay") == 3);
    }

    function _repaymentSnapshot(FinancialHandler.Ghost memory g, bytes32 paymentId) private view returns (bytes32) {
        CreditManager manager = handler.manager();
        (, CreditManagerCore.State state,) = manager.agreement(g.id);
        return keccak256(
            abi.encode(
                manager.principal(g.id),
                manager.accruedInterest(g.id),
                manager.interestRemainder(g.id),
                manager.lastAccrued(g.id),
                manager.totalInterestAccrued(g.id),
                manager.totalInterestPaid(g.id),
                manager.totalPrincipalPaid(g.id),
                handler.vault().free(g.lender),
                handler.token().balanceOf(address(handler.vault())),
                handler.vault().repaymentUsed(paymentId),
                state
            )
        );
    }

    function _failedRepaymentChecks() private {
        FinancialHandler.Ghost memory g = handler.loan(0);
        uint256 nonce = handler.paymentNonce() + 1;
        bytes32 paymentId =
            keccak256(abi.encode("REPAYMENT_V1", block.chainid, address(handler.manager()), g.id, g.borrower, nonce));
        handler.token().mint(g.borrower, 1);
        vm.prank(g.borrower);
        handler.token().approve(address(handler.vault()), 1);
        bytes32 before_ = _repaymentSnapshot(g, paymentId);
        handler.token().configure(true, false, address(0));
        vm.prank(g.borrower);
        (bool ok,) = address(handler.manager()).call(abi.encodeCall(handler.manager().repay, (g.id, 1, nonce)));
        assert(!ok && _repaymentSnapshot(g, paymentId) == before_);
        handler.token().configure(false, false, address(0));
        vm.prank(g.borrower);
        (ok,) =
            address(handler.manager()).call(abi.encodeCall(handler.manager().repay, (g.id, type(uint256).max, nonce)));
        assert(!ok && _repaymentSnapshot(g, paymentId) == before_);
        uint256 previous = handler.paymentNonce();
        bytes32 used = keccak256(
            abi.encode("REPAYMENT_V1", block.chainid, address(handler.manager()), g.id, g.borrower, previous)
        );
        assert(handler.vault().repaymentUsed(used));
        bytes32 beforeUsed = _repaymentSnapshot(g, used);
        vm.prank(g.borrower);
        (ok,) = address(handler.manager()).call(abi.encodeCall(handler.manager().repay, (g.id, 1, previous)));
        assert(!ok && _repaymentSnapshot(g, used) == beforeUsed);
    }

    struct SelectorTarget {
        address addr;
        bytes4[] selectors;
    }

    function targetContracts() external view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    function targetSelectors() external view returns (SelectorTarget[] memory targets) {
        bytes4[] memory s = new bytes4[](15);
        s[0] = FinancialHandler.deposit.selector;
        s[1] = FinancialHandler.register.selector;
        s[2] = FinancialHandler.activate.selector;
        s[3] = FinancialHandler.cancel.selector;
        s[4] = FinancialHandler.observe.selector;
        s[5] = FinancialHandler.execute.selector;
        s[6] = FinancialHandler.advance.selector;
        s[7] = FinancialHandler.checkpoint.selector;
        s[8] = FinancialHandler.repay.selector;
        s[9] = FinancialHandler.donate.selector;
        s[10] = FinancialHandler.expire.selector;
        s[11] = FinancialHandler.revoke.selector;
        s[12] = FinancialHandler.clearRecovered.selector;
        s[13] = FinancialHandler.markDefault.selector;
        s[14] = FinancialHandler.withdraw.selector;
        targets = new SelectorTarget[](1);
        targets[0] = SelectorTarget(address(handler), s);
    }

    function invariant_CashAndDebtMatchIndependentLedger() public {
        CreditLiquidityVault vault = handler.vault();
        uint256 cash = handler.deposits() + handler.repayments() - handler.withdrawals() - handler.draws();
        assert(vault.totalFree() + vault.totalReserved() == cash);
        assert(handler.token().balanceOf(address(vault)) == cash + handler.donations());
        assert(vault.surplus() == handler.donations());
        uint256 freeSum;
        uint256 reservedSum;
        for (uint256 j; j < 3; j++) {
            address l = handler.lender(j);
            assert(vault.free(l) == handler.free(l));
            assert(vault.reserved(l) == handler.reserved(l));
            freeSum += handler.free(l);
            reservedSum += handler.reserved(l);
        }
        assert(vault.totalFree() == freeSum && vault.totalReserved() == reservedSum);
        uint256 reservedLoans;
        for (uint256 j; j < handler.loanCount(); j++) {
            reservedLoans += _checkLoan(handler.loan(j));
        }
        assert(reservedLoans == reservedSum);
        assert(handler.custody().totalLocked() == handler.loanCount() * 1 ether);
        assert(address(handler.custody()).balance == handler.custody().totalLocked() + handler.custody().surplus());
    }

    function _checkCustody(FinancialHandler.Ghost memory g) private view {
        (address owner, bytes32 linked, uint256 locked, CollateralState collateralState) =
            handler.custody().positions(handler.custody().positionId(g.id));
        assert(owner == g.borrower && linked == g.id && locked == 1 ether && collateralState == CollateralState.Locked);
    }

    function _checkLoan(FinancialHandler.Ghost memory g) private view returns (uint256 reservedLoan) {
        _checkCustody(g);
        CreditManager manager = handler.manager();
        (, CreditManagerCore.State state, bytes32 reservation) = manager.agreement(g.id);
        assert(uint8(state) == (g.state == 3 ? 4 : g.state == 4 ? 3 : g.state));
        assert(manager.principal(g.id) == g.principal);
        assert(manager.accruedInterest(g.id) == g.interest && manager.interestRemainder(g.id) == g.remainder);
        assert(
            manager.totalInterestAccrued(g.id) == g.interestRecognized
                && manager.totalInterestPaid(g.id) == g.interestPaid
                && manager.totalPrincipalPaid(g.id) == g.principalPaid
        );
        assert(g.interestRecognized == g.interest + g.interestPaid);
        uint256 previewNumerator = g.principal * (g.last == 0 ? 0 : block.timestamp - g.last) + g.remainder;
        uint256 expectedInterest = g.interest + previewNumerator / 630720000;
        uint256 previewRemainder = previewNumerator % 630720000;
        (uint256 previewPrincipal, uint256 previewInterest, uint256 previewTotal) = manager.debtPreview(g.id);
        assert(previewPrincipal == g.principal && previewInterest == expectedInterest);
        assert(previewTotal == g.principal + expectedInterest + (previewRemainder == 0 ? 0 : 1));
        if (g.state == 2) {
            (,,, ReservationState rs) = handler.vault().reservations(reservation);
            assert(rs == ReservationState.Reserved);
            reservedLoan = 500e6;
        }
        if (g.state == 3 || g.state == 5) {
            assert(g.principal + g.principalPaid == 200e6);
            assert(manager.completedDraw(g.op) && handler.market().debt(g.borrower) == 600e6);
        }
        if (g.state == 4) assert(g.principal == 0 && g.interest == 0 && g.remainder == 0);
    }
}
