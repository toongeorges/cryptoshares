// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract TestGold is ERC20 {
    constructor(uint amountOfTokens) ERC20('Test Gold', 'GLD') {
        // Mint tokens to msg.sender
        // Similar to how
        // 1 dollar = 100 cents
        // 1 token = 1 * (10 ** decimals)
        _mint(msg.sender, amountOfTokens * 10**uint(decimals()));
    }
}