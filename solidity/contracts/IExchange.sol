// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

error DoNotAcceptEtherPayments();
error InsufficientAllowance();

interface IExchange {
    //tokens that are sold have to be locked up in the exchange before trade.  These tokens are released either on execution of the order or when the order is cancelled.
    function getLockedUpAmount(address erc2OAddress) external view returns (uint256);
    //will execute up to maxOrders orders where assets are sold for the currency at a ratio >= currencyAmount/assetAmount
    function ask(address asset, uint256 assetAmount, address currency, uint256 currencyAmount, uint256 maxOrders) external returns (uint256);
    //will execute up to maxOrders orders where assets are bought for the currency at a ratio <= currencyAmount/assetAmount
    function bid(address asset, uint256 assetAmount, address currency, uint256 currencyAmount, uint256 maxOrders) external returns (uint256);
    //cancels the not executed part of the order
    function cancel(uint256 orderId) external;
}