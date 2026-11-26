// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @dev Local test input only. This is not source-chain finality verification.
contract LocalCollateralFixture {
    struct Evidence {
        bytes32 lot;
        address borrower;
        uint256 amount;
    }
    mapping(bytes32 => Evidence) public evidence;

    function set(bytes32 id, bytes32 lot, address borrower, uint256 amount) external {
        evidence[id] = Evidence(lot, borrower, amount);
    }

    function verify(bytes32 id, bytes32 lot, address borrower, uint256 amount) external view returns (bool) {
        Evidence storage e = evidence[id];
        return e.lot == lot && e.borrower == borrower && e.amount == amount && amount != 0;
    }
}

contract LocalOracleFixture {
    uint256 public value;
    uint256 public updatedAt;

    function set(uint256 value_, uint256 updatedAt_) external {
        value = value_;
        updatedAt = updatedAt_;
    }

    function valueUSDC(uint256 amount) external view returns (uint256, uint256) {
        require(amount <= type(uint128).max && value <= type(uint128).max);
        return (amount * value / 1 ether, updatedAt);
    }
}

interface IFixtureToken {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external;
}

/// @dev Deterministic adversarial market for local tests only.
contract LocalLendingMarket {
    address public immutable asset;
    mapping(address => uint256) public debt;
    mapping(address => uint256) public collateral;
    bool public fail;
    bool public partialMode;

    constructor(address asset_) {
        asset = asset_;
    }

    function setPosition(address borrower, uint256 debt_, uint256 collateral_) external {
        debt[borrower] = debt_;
        collateral[borrower] = collateral_;
    }

    function configure(bool fail_, bool partial_) external {
        fail = fail_;
        partialMode = partial_;
    }

    function health(address borrower) public view returns (uint256) {
        return debt[borrower] == 0 ? type(uint256).max : collateral[borrower] * 1e18 / debt[borrower];
    }

    function isDistressed(address borrower) external view returns (bool) {
        uint256 h = health(borrower);
        return h > 1e18 && h <= 11e17;
    }

    function repay(address borrower, uint256 amount) external returns (uint256) {
        require(!fail);
        uint256 applied = partialMode ? amount / 2 : amount;
        require(applied != 0 && applied <= debt[borrower]);
        require(IFixtureToken(asset).transferFrom(msg.sender, address(this), applied));
        debt[borrower] -= applied;
        return applied;
    }
}

/// @dev The target and token are immutable; no arbitrary call or execution destination.
contract LocalRepaymentAdapter {
    address public immutable asset;
    address public immutable market;
    bool public lie;
    bool public falseSuccess;
    bool public reenter;
    bool public reentrySucceeded;
    bool public leaveAllowance;
    bool public addResidual;
    address public manager;
    bytes32 public reentryAgreement;
    bytes32 public reentryOperation;

    constructor(address asset_, address market_) {
        asset = asset_;
        market = market_;
    }

    function configure(bool lie_, bool falseSuccess_, bool reenter_, address manager_, bytes32 id_, bytes32 operation_)
        external
    {
        lie = lie_;
        falseSuccess = falseSuccess_;
        reenter = reenter_;
        manager = manager_;
        reentryAgreement = id_;
        reentryOperation = operation_;
    }

    function configurePost(bool leaveAllowance_, bool addResidual_) external {
        leaveAllowance = leaveAllowance_;
        addResidual = addResidual_;
    }

    function repay(address borrower, uint256 amount) external returns (uint256) {
        require(msg.sender == manager && manager != address(0));
        if (reenter) {
            (reentrySucceeded,) = manager.call(
                abi.encodeWithSignature(
                    "executePending(bytes32,bytes32,uint256)", reentryAgreement, reentryOperation, amount
                )
            );
        }
        if (falseSuccess) return amount;
        require(IFixtureToken(asset).transferFrom(msg.sender, address(this), amount));
        IFixtureToken(asset).approve(market, amount + (leaveAllowance ? 1 : 0));
        uint256 actual = LocalLendingMarket(market).repay(borrower, amount);
        if (!leaveAllowance) IFixtureToken(asset).approve(market, 0);
        if (addResidual) require(IFixtureToken(asset).transfer(manager, 1));
        return lie ? amount + 1 : actual;
    }
}
