// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface IExchange {
    function bid(address asset, uint256 amount, address currency, uint256 price) external;
    function ask(address asset, uint256 amount, address currency, uint256 price) external;
    function cancel(uint256 orderId) external;
}