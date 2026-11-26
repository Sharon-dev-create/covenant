// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @notice Restricted, synthetic six-decimal test token. This is not Circle USDC.
contract DemoToken {
    string public constant name = "Covenant Demonstration Token";
    string public constant symbol = "cMOCK";
    uint8 public constant decimals = 6;
    uint256 public constant MAX_SUPPLY = 100_000e6;
    address public authority;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    error Unauthorized();
    error InvalidAmount();

    constructor(address authority_) {
        if (block.chainid != 84532 || authority_ == address(0)) revert Unauthorized();
        authority = authority_;
    }

    function mint(address to, uint256 amount) external {
        if (msg.sender != authority) revert Unauthorized();
        if (to == address(0) || amount == 0 || amount > MAX_SUPPLY - totalSupply) revert InvalidAmount();
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 permitted = allowance[from][msg.sender];
        if (permitted != type(uint256).max) allowance[from][msg.sender] = permitted - amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) private {
        if (to == address(0)) revert InvalidAmount();
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}
