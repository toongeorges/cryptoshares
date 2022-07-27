// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import 'contracts/Share.sol';

contract ShareFactory {
    address[] public shares;

    event ShareCreation(address shareAddress, address indexed owner, string indexed name, string symbol, address indexed exchange);

    function getNumberOfShares() external view returns (uint256) {
        return shares.length;
    }

    function create(string memory name, string memory symbol, address exchangeAddress) external {
        address shareAddress = address(new Share(msg.sender, name, symbol, exchangeAddress));
        shares.push(shareAddress);

        emit ShareCreation(shareAddress, msg.sender, name, symbol, exchangeAddress);
    }
}
