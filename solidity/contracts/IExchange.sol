// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface IExchange {
    function getOrderIds(address owner) external returns (uint256[] memory);
    function getExecuted(uint256 orderId) external returns (address, uint256, address, uint256, bool);
    function getRemaining(uint256 orderId) external returns (address, uint256, address, uint256, bool);
    function getCanceled(uint256 orderId) external returns (address, uint256, address, uint256, bool);
    function ask(address asset, uint256 amount, address currency, uint256 price) external;
    function bid(address asset, uint256 amount, address currency, uint256 price) external;
    function cancel(uint256 orderId) external;
    function collect() external;
}