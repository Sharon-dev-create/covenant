// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {CreditManagerCore} from "../src/CreditManagerCore.sol";
import {CreditLiquidityVault} from "../src/CreditLiquidityVault.sol";
import {CollateralVault} from "../src/CollateralVault.sol";
import {DemoToken} from "../src/demo/DemoToken.sol";
import {DemoOracle} from "../src/demo/DemoOracle.sol";
import {DemoMarket} from "../src/demo/DemoMarket.sol";
import {DemoAdapter} from "../src/demo/DemoAdapter.sol";
import {DemoDeploymentFactory} from "../src/demo/DemoDeploymentFactory.sol";
import {CollateralAttestationVerifier} from "../src/demo/CollateralAttestationVerifier.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

interface M3CVm {
    function addr(uint256) external returns (address);
    function sign(uint256, bytes32) external returns (uint8, bytes32, bytes32);
    function prank(address) external;
    function warp(uint256) external;
    function chainId(uint256) external;
    function getNonce(address) external view returns (uint64);
    function computeCreateAddress(address, uint256) external pure returns (address);
    function deal(address, uint256) external;
    function expectRevert() external;
    function expectRevert(bytes4) external;
    function mockCallRevert(address callee, bytes calldata data, bytes calldata revertData) external;
}

contract M3CDemoTest {
    M3CVm constant vm = M3CVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 constant BK = 0xA11CE;
    uint256 constant LK = 0xB0B;
    address borrower;
    address lender;
    CollateralVault source;
    DemoToken token;
    DemoOracle oracle;
    DemoMarket market;
    DemoAdapter adapter;
    CollateralAttestationVerifier verifier;
    DemoDeploymentFactory factory;
    CreditManagerCore manager;
    CreditLiquidityVault vault;
    CreditManagerCore.Terms terms;
    bytes32 id;
    uint256[4] keys = [uint256(101), 102, 103, 104];

    function setUp() public {
        vm.warp(10000);
        borrower = vm.addr(BK);
        lender = vm.addr(LK);
        vm.chainId(1301);
        source = new CollateralVault(address(this));
        vm.chainId(84532);
        token = new DemoToken(address(this));
        oracle = new DemoOracle(address(this));
        market = new DemoMarket(address(token), address(this));
        uint256 n = vm.getNonce(address(this));
        address demoFactory = vm.computeCreateAddress(address(this), n + 2);
        address childFactory = vm.computeCreateAddress(demoFactory, 1);
        address expectedManager = vm.computeCreateAddress(childFactory, 1);
        address[4] memory signers;
        for (uint256 i; i < 4; i++) signers[i] = vm.addr(keys[i]);
        verifier = new CollateralAttestationVerifier(
            address(source), expectedManager, address(this), address(0xBEEF), signers
        );
        adapter = new DemoAdapter(address(token), address(market), expectedManager);
        factory = new DemoDeploymentFactory(address(token), address(verifier), address(oracle), address(adapter));
        assert(
            address(factory) == demoFactory && factory.factory() == childFactory && factory.manager() == expectedManager
        );
        manager = CreditManagerCore(factory.manager());
        vault = CreditLiquidityVault(factory.vault());
        terms = CreditManagerCore.Terms(
            borrower,
            lender,
            address(source),
            1301,
            bytes32(0),
            0.001 ether,
            address(market),
            borrower,
            bytes32(uint256(1)),
            300e6,
            200e6,
            11e17,
            1,
            1,
            uint64(block.timestamp + 1 days),
            uint64(block.timestamp + 2 days),
            uint64(block.timestamp + 3 days),
            100,
            5000
        );
        terms.lotId =
            keccak256(abi.encode("LOT_V1", terms.collateralChainId, terms.collateralVault, manager.agreementId(terms)));
        bytes32 d = manager.digest(terms);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(BK, d);
        bytes memory bs = abi.encodePacked(r, s, v);
        (v, r, s) = vm.sign(LK, d);
        id = manager.register(terms, bs, abi.encodePacked(r, s, v));
        vm.chainId(1301);
        source.bind(id, borrower, terms.collateralAmount);
        vm.deal(borrower, 1 ether);
        vm.prank(borrower);
        assert(source.lock{value: 0.001 ether}(id) == terms.lotId);
        vm.chainId(84532);
        token.mint(lender, 1000e6);
        token.mint(borrower, 800e6);
        vm.prank(lender);
        token.approve(address(vault), 1000e6);
        vm.prank(lender);
        vault.deposit(1000e6);
        vm.prank(lender);
        vault.setCommitment(id, 300e6);
        oracle.update(1_000_000e6);
        market.setPosition(borrower, 800e6, 840e6);
    }

    function _attestation() private view returns (CollateralAttestationVerifier.CollateralLockAttestationV1 memory a) {
        a = CollateralAttestationVerifier.CollateralLockAttestationV1(
            1301,
            address(source),
            84532,
            address(verifier),
            address(manager),
            100,
            bytes32(uint256(12)),
            bytes32(uint256(13)),
            0,
            id,
            terms.lotId,
            borrower,
            0.001 ether,
            manager.termsHash(terms),
            1,
            1,
            uint64(block.timestamp + 30 minutes)
        );
    }

    function _sigs(CollateralAttestationVerifier.CollateralLockAttestationV1 memory a, uint256 count)
        private
        returns (bytes[] memory sigs)
    {
        bytes32 d = verifier.digest(a);
        sigs = new bytes[](count);
        for (uint256 i; i < count; i++) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(keys[i], d);
            sigs[i] = abi.encodePacked(r, s, v);
        }
    }

    function _accept() private {
        CollateralAttestationVerifier.CollateralLockAttestationV1 memory a = _attestation();
        verifier.acceptLock(a, _sigs(a, 3));
    }

    function testCompleteDemoAndPausedRepayment() public {
        _accept();
        manager.activate(id);
        assert(vault.free(lender) == 700e6 && vault.reserved(lender) == 300e6);
        bytes32 op = manager.observeRisk(id);
        manager.executePending(id, op, 200e6);
        assert(market.debt(borrower) == 600e6 && manager.principal(id) == 200e6 && vault.free(lender) == 800e6);
        vm.prank(address(0xBEEF));
        verifier.setPaused(true);
        assert(!verifier.verify(id, terms.lotId, borrower, 0.001 ether));
        vm.warp(block.timestamp + 1 days);
        (,, uint256 amount) = manager.debtPreview(id);
        vm.prank(borrower);
        token.approve(address(vault), amount);
        vm.prank(borrower);
        manager.repay(id, amount, 1);
        assert(manager.principal(id) == 0 && vault.free(lender) == 800e6 + amount && amount > 200e6);
        assert(source.totalLocked() == 0.001 ether && address(source).balance == 0.001 ether);
    }

    function testThresholdDuplicateAndIdenticalIdempotent() public {
        CollateralAttestationVerifier.CollateralLockAttestationV1 memory a = _attestation();
        bytes[] memory s = _sigs(a, 2);
        vm.expectRevert(CollateralAttestationVerifier.InvalidSignatures.selector);
        verifier.acceptLock(a, s);
        s = _sigs(a, 3);
        s[2] = s[1];
        vm.expectRevert(CollateralAttestationVerifier.InvalidSignatures.selector);
        verifier.acceptLock(a, s);
        s = _sigs(a, 3);
        verifier.acceptLock(a, s);
        verifier.acceptLock(a, s);
        assert(verifier.verify(id, terms.lotId, borrower, 0.001 ether));
        assert(!verifier.verify(id, bytes32(uint256(4)), borrower, 0.001 ether));
    }

    function testWrongDomainEpochAndExpiry() public {
        CollateralAttestationVerifier.CollateralLockAttestationV1 memory a = _attestation();
        a.sourceChainId = 1;
        vm.expectRevert(CollateralAttestationVerifier.InvalidEvidence.selector);
        verifier.acceptLock(a, new bytes[](0));
        a = _attestation();
        a.sourceVault = address(9);
        vm.expectRevert(CollateralAttestationVerifier.InvalidEvidence.selector);
        verifier.acceptLock(a, new bytes[](0));
        a = _attestation();
        a.destinationChainId = 1;
        vm.expectRevert(CollateralAttestationVerifier.InvalidEvidence.selector);
        verifier.acceptLock(a, new bytes[](0));
        a = _attestation();
        a.destinationVerifier = address(9);
        vm.expectRevert(CollateralAttestationVerifier.InvalidEvidence.selector);
        verifier.acceptLock(a, new bytes[](0));
        a = _attestation();
        a.destinationManager = address(9);
        vm.expectRevert(CollateralAttestationVerifier.InvalidEvidence.selector);
        verifier.acceptLock(a, new bytes[](0));
        a = _attestation();
        a.borrower = address(9);
        vm.expectRevert(CollateralAttestationVerifier.InvalidEvidence.selector);
        verifier.acceptLock(a, new bytes[](0));
        a = _attestation();
        a.agreementId = bytes32(uint256(7));
        vm.expectRevert(CollateralAttestationVerifier.InvalidEvidence.selector);
        verifier.acceptLock(a, new bytes[](0));
        a = _attestation();
        a.lotId = bytes32(uint256(7));
        vm.expectRevert(CollateralAttestationVerifier.InvalidEvidence.selector);
        verifier.acceptLock(a, new bytes[](0));
        a = _attestation();
        a.signerEpoch = 2;
        vm.expectRevert(CollateralAttestationVerifier.InvalidEvidence.selector);
        verifier.acceptLock(a, new bytes[](0));
        a = _attestation();
        a.expiresAt = uint64(block.timestamp);
        vm.expectRevert(CollateralAttestationVerifier.InvalidEvidence.selector);
        verifier.acceptLock(a, new bytes[](0));
        a = _attestation();
        a.expiresAt = uint64(block.timestamp + 30 minutes + 1);
        vm.expectRevert(CollateralAttestationVerifier.InvalidEvidence.selector);
        verifier.acceptLock(a, new bytes[](0));
    }

    function testConflictFreezesAndPauseStopsActivation() public {
        CollateralAttestationVerifier.CollateralLockAttestationV1 memory a = _attestation();
        verifier.acceptLock(a, _sigs(a, 3));
        a.sourceBlockHash = bytes32(uint256(99));
        verifier.acceptLock(a, _sigs(a, 3));
        assert(verifier.conflict(id) && !verifier.verify(id, terms.lotId, borrower, 0.001 ether));
        vm.expectRevert(CreditManagerCore.InvalidCollateral.selector);
        manager.activate(id);
    }

    function testRotationGovernanceAndExpiry() public {
        _accept();
        address[4] memory next = [vm.addr(201), vm.addr(202), vm.addr(203), vm.addr(204)];
        vm.prank(address(99));
        vm.expectRevert(CollateralAttestationVerifier.Unauthorized.selector);
        verifier.proposeRotation(next, 2);
        verifier.proposeRotation(next, 2);
        vm.expectRevert(CollateralAttestationVerifier.InvalidRotation.selector);
        verifier.activateRotation();
        vm.warp(block.timestamp + 24 hours);
        verifier.activateRotation();
        assert(verifier.signerEpoch() == 2 && !verifier.verify(id, terms.lotId, borrower, 0.001 ether));
        CollateralAttestationVerifier.CollateralLockAttestationV1 memory rotated = _attestation();
        rotated.signerEpoch = 2;
        rotated.policyVersion = 2;
        bytes[] memory oldSigs = _sigs(rotated, 3);
        vm.expectRevert(CollateralAttestationVerifier.InvalidSignatures.selector);
        verifier.acceptLock(rotated, oldSigs);
        bytes[] memory newSigs = new bytes[](3);
        bytes32 rotatedDigest = verifier.digest(rotated);
        for (uint256 i; i < 3; i++) {
            (uint8 v, bytes32 r, bytes32 ss) = vm.sign(201 + i, rotatedDigest);
            newSigs[i] = abi.encodePacked(r, ss, v);
        }
        verifier.acceptLock(rotated, newSigs);
        assert(verifier.verify(id, terms.lotId, borrower, 0.001 ether));
        vm.prank(address(0xBEEF));
        verifier.setPaused(true);
        vm.prank(address(0xBEEF));
        vm.expectRevert(CollateralAttestationVerifier.Unauthorized.selector);
        verifier.setPaused(false);
        verifier.setPaused(false);
    }

    function testPausedBeforeDrawAndRecoveredPosition() public {
        _accept();
        manager.activate(id);
        bytes32 op = manager.observeRisk(id);
        vm.prank(address(0xBEEF));
        verifier.setPaused(true);
        vm.expectRevert(CreditManagerCore.InvalidCollateral.selector);
        manager.executePending(id, op, 200e6);
        assert(manager.pendingDraw(id) == op && manager.principal(id) == 0 && vault.reserved(lender) == 300e6);
        verifier.setPaused(false);
        market.setPosition(borrower, 800e6, 1000e6);
        vm.expectRevert(CreditManagerCore.InvalidExecution.selector);
        manager.executePending(id, op, 200e6);
        assert(manager.pendingDraw(id) == op && market.debt(borrower) == 800e6);
    }

    function testDemoFactoryRejectsOtherAssetAndOperatorControls() public {
        MockUSDC notDemo = new MockUSDC();
        vm.expectRevert(DemoDeploymentFactory.InvalidDemoDeployment.selector);
        new DemoDeploymentFactory(address(notDemo), address(verifier), address(oracle), address(adapter));
        vm.prank(address(99));
        vm.expectRevert(DemoToken.Unauthorized.selector);
        token.mint(address(99), 1);
        vm.prank(address(99));
        vm.expectRevert(DemoOracle.Unauthorized.selector);
        oracle.update(1);
        vm.prank(address(99));
        vm.expectRevert(DemoMarket.Unauthorized.selector);
        market.setPosition(borrower, 1, 1);
        vm.prank(address(99));
        vm.expectRevert(DemoAdapter.Unauthorized.selector);
        adapter.repay(borrower, 1);
        assert(
            manager.asset() == address(token) && manager.localAdapter() == address(adapter)
                && manager.localOracle() == address(oracle) && manager.localCollateralVerifier() == address(verifier)
        );
    }

    function testExpiredEvidenceAndIdenticalFactRenewal() public {
        _accept();
        vm.warp(block.timestamp + 30 minutes);
        assert(!verifier.verify(id, terms.lotId, borrower, 0.001 ether));
        _accept();
        assert(verifier.verify(id, terms.lotId, borrower, 0.001 ether));
        manager.activate(id);
    }

    function testPauseRejectsEvidenceAndActivationThenResumes() public {
        CollateralAttestationVerifier.CollateralLockAttestationV1 memory a = _attestation();
        bytes[] memory sigs = _sigs(a, 3);
        vm.prank(address(0xBEEF));
        verifier.setPaused(true);
        vm.expectRevert(CollateralAttestationVerifier.Paused.selector);
        verifier.acceptLock(a, sigs);
        vm.expectRevert(CreditManagerCore.InvalidCollateral.selector);
        manager.activate(id);
        assert(vault.free(lender) == 1000e6 && vault.reserved(lender) == 0);
        verifier.setPaused(false);
        verifier.acceptLock(a, sigs);
        manager.activate(id);
        assert(vault.reserved(lender) == 300e6);
    }

    function testSignerMembershipAndReorderedThreshold() public {
        CollateralAttestationVerifier.CollateralLockAttestationV1 memory a = _attestation();
        bytes[] memory sigs = _sigs(a, 3);
        (uint8 v, bytes32 r, bytes32 ss) = vm.sign(9999, verifier.digest(a));
        sigs[2] = abi.encodePacked(r, ss, v);
        vm.expectRevert(CollateralAttestationVerifier.InvalidSignatures.selector);
        verifier.acceptLock(a, sigs);
        sigs = _sigs(a, 3);
        bytes memory temp = sigs[0];
        sigs[0] = sigs[2];
        sigs[2] = temp;
        verifier.acceptLock(a, sigs);
        assert(verifier.verify(id, terms.lotId, borrower, 0.001 ether));
    }

    function testDuplicateRotationSignersAndWrongEpochRevert() public {
        address[4] memory next = [vm.addr(201), vm.addr(202), vm.addr(203), vm.addr(203)];
        vm.expectRevert(CollateralAttestationVerifier.InvalidRotation.selector);
        verifier.proposeRotation(next, 2);
        CollateralAttestationVerifier.CollateralLockAttestationV1 memory a = _attestation();
        a.signerEpoch = 2;
        vm.expectRevert(CollateralAttestationVerifier.InvalidEvidence.selector);
        verifier.acceptLock(a, new bytes[](0));
    }

    function testZeroOracleRejectedAndHealthyPositionNeverObserved() public {
        vm.expectRevert(DemoOracle.InvalidValue.selector);
        oracle.update(0);
        _accept();
        manager.activate(id);
        market.setPosition(borrower, 800e6, 1000e6);
        vm.expectRevert(CreditManagerCore.InvalidExecution.selector);
        manager.observeRisk(id);
        assert(manager.principal(id) == 0 && vault.reserved(lender) == 300e6);
    }

    function testMarketFailureRollsBackAllFinancialEffects() public {
        _accept();
        manager.activate(id);
        bytes32 op = manager.observeRisk(id);
        uint256 beforeCash = token.balanceOf(address(vault));
        vm.mockCallRevert(
            address(market),
            abi.encodeCall(DemoMarket.repay, (borrower, 200e6)),
            abi.encodeWithSignature("Error(string)", "injected failure")
        );
        vm.expectRevert();
        manager.executePending(id, op, 200e6);
        assert(manager.pendingDraw(id) == op && manager.principal(id) == 0);
        assert(vault.reserved(lender) == 300e6 && token.balanceOf(address(vault)) == beforeCash);
        assert(market.debt(borrower) == 800e6 && token.balanceOf(address(adapter)) == 0);
        assert(
            token.allowance(address(manager), address(adapter)) == 0
                && token.allowance(address(adapter), address(market)) == 0
        );
    }

    function testStaleOracleRollsBackExecution() public {
        _accept();
        manager.activate(id);
        bytes32 op = manager.observeRisk(id);
        vm.warp(block.timestamp + 1 hours + 1);
        vm.expectRevert(CreditManagerCore.InvalidCollateral.selector);
        manager.executePending(id, op, 200e6);
        // Renew evidence; oracle remains stale.
        _accept();
        vm.expectRevert(CreditManagerCore.InvalidPrice.selector);
        manager.executePending(id, op, 200e6);
        assert(manager.pendingDraw(id) == op && manager.principal(id) == 0 && vault.reserved(lender) == 300e6);
    }
}
