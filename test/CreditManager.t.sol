// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {CreditManager} from "../src/CreditManager.sol";
import {CreditManagerCore} from "../src/CreditManagerCore.sol";
import {LocalCreditFactory} from "../src/LocalCreditFactory.sol";
import {CreditLiquidityVault} from "../src/CreditLiquidityVault.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {LocalCollateralFixture, LocalOracleFixture} from "./mocks/LocalCreditFixtures.sol";
import {InsufficientLiquidity} from "../src/ProtocolTypes.sol";

interface CreditVm {
    function addr(uint256) external returns (address);
    function sign(uint256, bytes32) external returns (uint8, bytes32, bytes32);
    function prank(address) external;
    function warp(uint256) external;
    function chainId(uint256) external;
    function getNonce(address) external view returns (uint64);
    function computeCreateAddress(address, uint256) external pure returns (address);
    function expectCall(address, bytes calldata) external;
    function expectRevert(bytes4) external;
    function expectRevert() external;
}

// Isolated failure-injection harness. Production factory remains unchanged.
contract RollbackHarness {
    address public recordedManager;
    address public recordedVault;
    error InjectedBindingFailure();

    function deploy(address asset, address verifier, address oracle, address adapter, bool inject) external {
        uint64 next = vmNonce();
        address managerAddress =
            address(uint160(uint256(keccak256(abi.encodePacked(hex"d694", address(this), uint8(next))))));
        address vaultAddress =
            address(uint160(uint256(keccak256(abi.encodePacked(hex"d694", address(this), uint8(next + 1))))));
        CreditManager createdManager = new CreditManager(vaultAddress, asset, verifier, oracle, adapter);
        CreditLiquidityVault createdVault =
            new CreditLiquidityVault(MockUSDC(asset), managerAddress, inject ? address(0xBAD) : managerAddress);
        require(address(createdManager) == managerAddress && address(createdVault) == vaultAddress);
        if (createdVault.consumer() != managerAddress) revert InjectedBindingFailure();
        recordedManager = managerAddress;
        recordedVault = vaultAddress;
    }

    function vmNonce() private view returns (uint64) {
        return CreditVm(address(uint160(uint256(keccak256("hevm cheat code"))))).getNonce(address(this));
    }
}

contract CreditManagerTest {
    CreditVm private constant vm = CreditVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant BORROWER_KEY = 0xA11CE;
    uint256 private constant LENDER_KEY = 0xB0B;
    MockUSDC private token;
    LocalCollateralFixture private collateral;
    LocalOracleFixture private oracle;
    CreditManager private manager;
    CreditLiquidityVault private vault;
    LocalCreditFactory private factory;
    CreditManagerCore.Terms private terms;

    function setUp() public {
        vm.warp(10000);
        token = new MockUSDC();
        collateral = new LocalCollateralFixture();
        oracle = new LocalOracleFixture();
        factory = new LocalCreditFactory(address(token), address(collateral), address(oracle), address(0x123));
        manager = CreditManager(factory.manager());
        vault = CreditLiquidityVault(factory.vault());
        terms = CreditManagerCore.Terms(
            vm.addr(BORROWER_KEY),
            vm.addr(LENDER_KEY),
            address(0x55),
            1301,
            bytes32(0),
            1 ether,
            address(0x42),
            vm.addr(BORROWER_KEY),
            bytes32(uint256(1)),
            500e6,
            200e6,
            11e17,
            1,
            10,
            11000,
            12000,
            13000,
            100,
            5000
        );
        terms.lotId =
            keccak256(abi.encode("LOT_V1", terms.collateralChainId, terms.collateralVault, manager.agreementId(terms)));
        token.mint(terms.lender, 1000e6);
        vm.prank(terms.lender);
        token.approve(address(vault), 1000e6);
        vm.prank(terms.lender);
        vault.deposit(1000e6);
        oracle.set(2000e6, block.timestamp);
    }

    function testDeploymentBindingsAndNoFactoryDeploymentEntry() public view {
        assert(factory.manager() == factory.predict(address(factory), 1));
        assert(factory.vault() == factory.predict(address(factory), 2));
        assert(manager.vault() == address(vault) && manager.asset() == address(token));
        assert(vault.manager() == address(manager) && vault.consumer() == address(manager));
    }

    function testRegisterActivateCancelAndReplay() public {
        bytes32 id = _register();
        collateral.set(id, terms.lotId, terms.borrower, terms.collateralAmount);
        vm.prank(terms.lender);
        vault.setCommitment(id, terms.cap);
        manager.activate(id);
        (, CreditManagerCore.State state, bytes32 reservation) = manager.agreement(id);
        assert(state == CreditManagerCore.State.Active && vault.reserved(terms.lender) == terms.cap);
        vm.expectRevert(CreditManagerCore.InvalidState.selector);
        manager.activate(id);
        vm.prank(terms.borrower);
        manager.cancelUnused(id);
        assert(vault.free(terms.lender) == 1000e6 && vault.reserved(terms.lender) == 0);
        (,, uint256 amount,) = vault.reservations(reservation);
        assert(amount == 0);
        vm.prank(terms.borrower);
        vm.expectRevert(CreditManagerCore.InvalidState.selector);
        manager.cancelUnused(id);
        bytes memory borrowerSignature = _signature(BORROWER_KEY);
        bytes memory lenderSignature = _signature(LENDER_KEY);
        vm.expectRevert(CreditManagerCore.InvalidState.selector);
        manager.register(terms, borrowerSignature, lenderSignature);
    }

    function testWrongSignaturesAndTerms() public {
        bytes memory wrongSignature = _signature(LENDER_KEY);
        vm.expectRevert(CreditManagerCore.InvalidAuthorization.selector);
        manager.register(terms, wrongSignature, wrongSignature);
        assert(!manager.usedBorrowerNonce(terms.borrower, terms.borrowerNonce));
        assert(!manager.usedLenderNonce(terms.lender, terms.lenderNonce));
        terms.ltvBps = 5001;
        vm.expectRevert(CreditManagerCore.InvalidTerms.selector);
        manager.register(terms, "", "");
    }

    function testCollateralOracleCommitmentAndCashGuards() public {
        bytes32 id = _register();
        vm.expectRevert(CreditManagerCore.InvalidCollateral.selector);
        manager.activate(id);
        collateral.set(id, terms.lotId, address(0x99), terms.collateralAmount);
        vm.expectRevert(CreditManagerCore.InvalidCollateral.selector);
        manager.activate(id);
        collateral.set(id, terms.lotId, terms.borrower, terms.collateralAmount - 1);
        vm.expectRevert(CreditManagerCore.InvalidCollateral.selector);
        manager.activate(id);
        collateral.set(id, terms.lotId, terms.borrower, terms.collateralAmount);
        oracle.set(2000e6, block.timestamp - 3601);
        vm.expectRevert(CreditManagerCore.InvalidPrice.selector);
        manager.activate(id);
        oracle.set(999e6, block.timestamp);
        vm.expectRevert(CreditManagerCore.InvalidPrice.selector);
        manager.activate(id);
        oracle.set(2000e6, block.timestamp);
        vm.expectRevert();
        manager.activate(id);
        vm.prank(terms.lender);
        vault.setCommitment(id, terms.cap);
        vm.prank(terms.lender);
        vault.withdraw(1000e6);
        vm.expectRevert(InsufficientLiquidity.selector);
        manager.activate(id);
        (, CreditManagerCore.State state,) = manager.agreement(id);
        assert(state == CreditManagerCore.State.Draft);
    }

    function testCancelAndExpiryAuthorization() public {
        bytes32 id = _register();
        vm.prank(address(0xBEEF));
        vm.expectRevert(CreditManagerCore.InvalidAuthorization.selector);
        manager.cancelUnused(id);
        vm.expectRevert(CreditManagerCore.InvalidState.selector);
        manager.expireUnused(id);
        vm.warp(terms.drawDeadline);
        manager.expireUnused(id);
        (, CreditManagerCore.State state,) = manager.agreement(id);
        assert(state == CreditManagerCore.State.Closed);
        vm.expectRevert(CreditManagerCore.InvalidState.selector);
        manager.expireUnused(id);
    }

    function testActiveExpiryReturnsReservation() public {
        bytes32 id = _register();
        collateral.set(id, terms.lotId, terms.borrower, terms.collateralAmount);
        vm.prank(terms.lender);
        vault.setCommitment(id, terms.cap);
        manager.activate(id);
        vm.warp(terms.drawDeadline);
        manager.expireUnused(id);
        assert(vault.free(terms.lender) == 1000e6 && vault.reserved(terms.lender) == 0);
        vm.expectRevert(CreditManagerCore.InvalidState.selector);
        manager.activate(id);
    }

    function testConflictingLotAndNonceCannotRegister() public {
        bytes32 id = _register();
        bytes32 firstLot = terms.lotId;
        terms.borrowerNonce = 2;
        terms.lenderNonce = 11;
        terms.lotId = firstLot;
        vm.expectRevert(CreditManagerCore.InvalidTerms.selector);
        manager.register(terms, "", "");
        terms.lotId =
            keccak256(abi.encode("LOT_V1", terms.collateralChainId, terms.collateralVault, manager.agreementId(terms)));
        bytes32 second = _register();
        collateral.set(id, terms.lotId, terms.borrower, terms.collateralAmount);
        vm.expectRevert(CreditManagerCore.InvalidCollateral.selector);
        manager.activate(id);
        assert(second != id);
    }

    function testFactoryRejectsWrongChainInvalidDependenciesAndRepeatCalls() public {
        address failedFactory = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        address failedManager = factory.predict(failedFactory, 1);
        address failedVault = factory.predict(failedFactory, 2);
        vm.expectRevert(CreditManagerCore.InvalidTerms.selector);
        new LocalCreditFactory(address(0), address(collateral), address(oracle), address(0x123));
        assert(failedFactory.code.length == 0 && failedManager.code.length == 0 && failedVault.code.length == 0);
        (bool ok,) = address(factory)
            .call(
                abi.encodeWithSignature(
                    "deploy(address,address,address,address)",
                    address(token),
                    address(collateral),
                    address(oracle),
                    address(0x123)
                )
            );
        assert(!ok);
        vm.chainId(84532);
        vm.expectRevert(LocalCreditFactory.InvalidDeployment.selector);
        new LocalCreditFactory(address(token), address(collateral), address(oracle), address(0x123));
    }

    function testHarnessRollsBackBothCreatedContractsAfterBindingFailure() public {
        RollbackHarness deployer = new RollbackHarness();
        uint64 nonce = vm.getNonce(address(deployer));
        address predictedManager = vm.computeCreateAddress(address(deployer), nonce);
        address predictedVault = vm.computeCreateAddress(address(deployer), nonce + 1);
        vm.expectCall(predictedVault, abi.encodeWithSignature("consumer()"));
        (bool ok, bytes memory reason) = address(deployer)
            .call(
                abi.encodeCall(
                    RollbackHarness.deploy, (address(token), address(collateral), address(oracle), address(0x123), true)
                )
            );
        assert(!ok && bytes4(reason) == RollbackHarness.InjectedBindingFailure.selector);
        assert(deployer.recordedManager() == address(0) && deployer.recordedVault() == address(0));
        assert(vm.getNonce(address(deployer)) == nonce);
        assert(predictedManager.code.length == 0 && predictedVault.code.length == 0);
        deployer.deploy(address(token), address(collateral), address(oracle), address(0x123), false);
        assert(deployer.recordedManager() == predictedManager && deployer.recordedVault() == predictedVault);
        assert(vm.getNonce(address(deployer)) == nonce + 2);
    }

    function testFuzzLtvBoundary(uint64 value) public {
        bytes32 id = _register();
        collateral.set(id, terms.lotId, terms.borrower, terms.collateralAmount);
        vm.prank(terms.lender);
        vault.setCommitment(id, terms.cap);
        oracle.set(uint256(value), block.timestamp);
        if (uint256(value) / 2 < terms.cap) {
            vm.expectRevert(CreditManagerCore.InvalidPrice.selector);
            manager.activate(id);
        } else {
            manager.activate(id);
            assert(vault.reserved(terms.lender) == terms.cap);
        }
    }

    function testSignedLotSubstitutionAndFinancialChangesAreRejected() public {
        bytes memory borrowerSignature = _signature(BORROWER_KEY);
        bytes memory lenderSignature = _signature(LENDER_KEY);
        bytes32 originalId = manager.agreementId(terms);
        terms.lotId = bytes32(uint256(999));
        assert(manager.agreementId(terms) == originalId);
        vm.expectRevert(CreditManagerCore.InvalidTerms.selector);
        manager.register(terms, borrowerSignature, lenderSignature);
        terms.cap += 1;
        terms.lotId =
            keccak256(abi.encode("LOT_V1", terms.collateralChainId, terms.collateralVault, manager.agreementId(terms)));
        vm.expectRevert(CreditManagerCore.InvalidAuthorization.selector);
        manager.register(terms, borrowerSignature, lenderSignature);
    }

    function testSignaturesAreBoundToContractChainAndBorrowerNonce() public {
        bytes memory borrowerSignature = _signature(BORROWER_KEY);
        bytes memory lenderSignature = _signature(LENDER_KEY);
        LocalCreditFactory other =
            new LocalCreditFactory(address(token), address(collateral), address(oracle), address(0x123));
        CreditManager otherManager = CreditManager(other.manager());
        terms.lotId = keccak256(
            abi.encode("LOT_V1", terms.collateralChainId, terms.collateralVault, otherManager.agreementId(terms))
        );
        vm.expectRevert(CreditManagerCore.InvalidAuthorization.selector);
        otherManager.register(terms, borrowerSignature, lenderSignature);
        vm.chainId(31338);
        terms.lotId =
            keccak256(abi.encode("LOT_V1", terms.collateralChainId, terms.collateralVault, manager.agreementId(terms)));
        vm.expectRevert(CreditManagerCore.InvalidAuthorization.selector);
        manager.register(terms, borrowerSignature, lenderSignature);
        vm.chainId(31337);
        terms.lotId =
            keccak256(abi.encode("LOT_V1", terms.collateralChainId, terms.collateralVault, manager.agreementId(terms)));
        manager.register(terms, borrowerSignature, lenderSignature);
        terms.cap -= 1;
        terms.lotId =
            keccak256(abi.encode("LOT_V1", terms.collateralChainId, terms.collateralVault, manager.agreementId(terms)));
        bytes memory freshBorrowerSignature = _signature(BORROWER_KEY);
        bytes memory freshLenderSignature = _signature(LENDER_KEY);
        vm.expectRevert(CreditManagerCore.InvalidState.selector);
        manager.register(terms, freshBorrowerSignature, freshLenderSignature);
    }

    function testExternalSigningVector() public view {
        assert(address(manager) == 0x5B0091f49210e7B2A57B03dfE1AB9D08289d9294);
        assert(manager.TERMS_TYPEHASH() == 0x669c38bed1ae421d32d2b337fb86ee03fb2ce82f79fedaf8c20d96b007d63523);
        assert(manager.termsHash(terms) == 0x68a098dca601dc92404b99a70d5c8e02dc28048d718c566e111f51c8a4b2f95a);
        assert(manager.digest(terms) == 0x5f96effdd1145a4f26cb13636e71ec8a15c7455e8c2124b53494d6f476c22f76);
        assert(manager.agreementId(terms) == 0x9a6feae81eb522ed255e907548fac414b691acb459ec64dd14c01cc0bcab4a79);
        assert(terms.lotId == 0x1ed0ed3f7ed90759e91a056a5dd284c0e95bd503ea9478e16fc14a00553a5eba);
    }

    function testAutonomousConditionsAreBoundByBothSignatures() public {
        bytes memory borrowerSig = _signature(BORROWER_KEY);
        bytes memory lenderSig = _signature(LENDER_KEY);
        terms.autonomousRepayment += 1;
        _updateLot();
        vm.expectRevert(CreditManagerCore.InvalidAuthorization.selector);
        manager.register(terms, borrowerSig, lenderSig);
        terms.autonomousRepayment -= 1;
        terms.maxHealth -= 1;
        _updateLot();
        vm.expectRevert(CreditManagerCore.InvalidAuthorization.selector);
        manager.register(terms, borrowerSig, lenderSig);
        assert(!manager.usedBorrowerNonce(terms.borrower, terms.borrowerNonce));
        assert(!manager.usedLenderNonce(terms.lender, terms.lenderNonce));
    }

    function testIndependentNonceReuseAndFailureAtomicity() public {
        _register();
        assert(manager.usedBorrowerNonce(terms.borrower, 1) && manager.usedLenderNonce(terms.lender, 10));
        terms.lenderNonce = 11;
        _updateLot();
        bytes memory borrowerSig = _signature(BORROWER_KEY);
        bytes memory lenderSig = _signature(LENDER_KEY);
        vm.expectRevert(CreditManagerCore.InvalidState.selector);
        manager.register(terms, borrowerSig, lenderSig);
        assert(!manager.usedLenderNonce(terms.lender, 11));
        terms.borrowerNonce = 2;
        terms.lenderNonce = 10;
        _updateLot();
        borrowerSig = _signature(BORROWER_KEY);
        lenderSig = _signature(LENDER_KEY);
        vm.expectRevert(CreditManagerCore.InvalidState.selector);
        manager.register(terms, borrowerSig, lenderSig);
        assert(!manager.usedBorrowerNonce(terms.borrower, 2));
    }

    function testRevocationOnlyAffectsCallerAndRole() public {
        bytes memory borrowerSig = _signature(BORROWER_KEY);
        bytes memory lenderSig = _signature(LENDER_KEY);
        vm.prank(address(0xBEEF));
        manager.invalidateBorrowerNonce(1);
        vm.prank(address(0xBEEF));
        manager.invalidateLenderNonce(10);
        assert(!manager.usedBorrowerNonce(terms.borrower, 1));
        assert(!manager.usedLenderNonce(terms.lender, 10));
        vm.prank(terms.borrower);
        manager.invalidateBorrowerNonce(1);
        vm.expectRevert(CreditManagerCore.InvalidState.selector);
        manager.register(terms, borrowerSig, lenderSig);
        assert(!manager.usedLenderNonce(terms.lender, 10));
        terms.borrowerNonce = 2;
        _updateLot();
        borrowerSig = _signature(BORROWER_KEY);
        lenderSig = _signature(LENDER_KEY);
        vm.prank(terms.lender);
        manager.invalidateLenderNonce(10);
        vm.expectRevert(CreditManagerCore.InvalidState.selector);
        manager.register(terms, borrowerSig, lenderSig);
        assert(!manager.usedBorrowerNonce(terms.borrower, 2));
        vm.prank(terms.lender);
        vm.expectRevert(CreditManagerCore.InvalidState.selector);
        manager.invalidateLenderNonce(10);
    }

    function testOutOfOrderAuthorizationsAndExistingReservation() public {
        bytes memory firstBorrower = _signature(BORROWER_KEY);
        bytes memory firstLender = _signature(LENDER_KEY);
        CreditManagerCore.Terms memory first = terms;
        terms.borrowerNonce = 100;
        terms.lenderNonce = 200;
        _updateLot();
        bytes32 second = _register();
        collateral.set(second, terms.lotId, terms.borrower, terms.collateralAmount);
        vm.prank(terms.lender);
        vault.setCommitment(second, terms.cap);
        manager.activate(second);
        bytes32 otherCommitment = bytes32(uint256(999));
        vm.prank(terms.lender);
        vault.setCommitment(otherCommitment, 25e6);
        vm.prank(terms.borrower);
        manager.invalidateBorrowerNonce(500);
        vm.prank(terms.lender);
        manager.invalidateLenderNonce(500);
        (, CreditManagerCore.State state,) = manager.agreement(second);
        assert(state == CreditManagerCore.State.Active && vault.reserved(terms.lender) == terms.cap);
        assert(vault.commitments(terms.lender, otherCommitment) == 25e6);
        manager.register(first, firstBorrower, firstLender);
        assert(manager.usedBorrowerNonce(terms.borrower, 1) && manager.usedLenderNonce(terms.lender, 10));
    }

    function testChangingEitherNonceInvalidatesSignatures() public {
        bytes memory borrowerSig = _signature(BORROWER_KEY);
        bytes memory lenderSig = _signature(LENDER_KEY);
        terms.borrowerNonce = 2;
        _updateLot();
        vm.expectRevert(CreditManagerCore.InvalidAuthorization.selector);
        manager.register(terms, borrowerSig, lenderSig);
        assert(!manager.usedBorrowerNonce(terms.borrower, 2) && !manager.usedLenderNonce(terms.lender, 10));
        terms.borrowerNonce = 1;
        terms.lenderNonce = 11;
        _updateLot();
        vm.expectRevert(CreditManagerCore.InvalidAuthorization.selector);
        manager.register(terms, borrowerSig, lenderSig);
        assert(!manager.usedBorrowerNonce(terms.borrower, 1) && !manager.usedLenderNonce(terms.lender, 11));
    }

    function testSameAddressHasSeparateRoleNamespaces() public {
        terms.lender = terms.borrower;
        terms.lenderNonce = terms.borrowerNonce;
        _updateLot();
        bytes memory signature = _signature(BORROWER_KEY);
        manager.register(terms, signature, signature);
        assert(manager.usedBorrowerNonce(terms.borrower, 1) && manager.usedLenderNonce(terms.borrower, 1));
        vm.prank(terms.borrower);
        manager.invalidateBorrowerNonce(77);
        assert(manager.usedBorrowerNonce(terms.borrower, 77) && !manager.usedLenderNonce(terms.borrower, 77));
        vm.prank(terms.borrower);
        manager.invalidateLenderNonce(77);
        assert(manager.usedLenderNonce(terms.borrower, 77));
    }

    function _updateLot() private {
        terms.lotId =
            keccak256(abi.encode("LOT_V1", terms.collateralChainId, terms.collateralVault, manager.agreementId(terms)));
    }

    function _register() private returns (bytes32) {
        return manager.register(terms, _signature(BORROWER_KEY), _signature(LENDER_KEY));
    }

    function _signature(uint256 key) private returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, manager.digest(terms));
        return abi.encodePacked(r, s, v);
    }
}
