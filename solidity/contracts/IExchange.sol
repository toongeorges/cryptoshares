// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface IExchange {
    function ask(address asset, uint256 amount, address currency, uint256 price, uint256 maxOrders) external returns (uint256);
    function bid(address asset, uint256 amount, address currency, uint256 price, uint256 maxOrders) external returns (uint256);
    function cancel(uint256 orderId) external;
}