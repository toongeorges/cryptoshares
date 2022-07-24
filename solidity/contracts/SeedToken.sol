// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract SeedToken is ERC20 {
    address public owner;

    modifier isOwner() {
        require(msg.sender == owner);
        _;
    }

    constructor(address ownerAddress, string memory name, string memory symbol) ERC20(name, symbol) {
        owner = ownerAddress;
    }

    function changeOwner(address newOwner) external isOwner {
        owner = newOwner;
    }

    function mint(uint256 amountOfTokens) external isOwner {
        _mint(msg.sender, amountOfTokens * 10**uint(decimals()));
    }
}