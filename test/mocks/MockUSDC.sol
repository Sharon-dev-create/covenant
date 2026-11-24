// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {IERC20} from "../../src/interfaces/IVaults.sol";

contract MockUSDC is IERC20 {
    uint8 public constant decimals = 6;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    bool public failTransfers;
    bool public chargeFee;
    bool public malformedReturn;
    address public reenterTarget;
    bool public reentrySucceeded;
    bytes4 public reentryError;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external {
        allowance[msg.sender][spender] = amount;
    }

    function configure(bool fail, bool fee, address target) external {
        failTransfers = fail;
        chargeFee = fee;
        reenterTarget = target;
    }

    function setMalformedReturn(bool enabled) external {
        malformedReturn = enabled;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        return _move(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        return _move(from, to, amount);
    }

    function _move(address from, address to, uint256 amount) private returns (bool) {
        if (failTransfers) return false;
        if (reenterTarget != address(0)) {
            (bool ok, bytes memory result) = reenterTarget.call(abi.encodeWithSignature("withdraw(uint256)", 1));
            reentrySucceeded = ok;
            reentryError = bytes4(result);
        }
        balanceOf[from] -= amount;
        balanceOf[to] += chargeFee ? amount - 1 : amount;
        if (malformedReturn) {
            assembly ("memory-safe") {
                mstore(0, 2)
                return(0, 32)
            }
        }
        return true;
    }
}
