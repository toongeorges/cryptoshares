// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

error DoNotAcceptEtherPayments();
error InsufficientAllowance();

interface IExchange {
    function getLockedUpAmount(address erc2OAddress) external view returns (uint256);
    //will make up to amountOfSwaps swaps in at most maxOrders orders where each swap sells offerRatio offer tokens and buys >= requestRatio request tokens
    function ask(address asset, uint256 assetAmount, address currency, uint256 currencyAmount, uint256 maxOrders) external returns (uint256);
    //will make up to amountOfSwaps swaps in at most maxOrders orders where each swap sells <= offerRatio offer tokens and buys requestRatio request tokens
    function bid(address asset, uint256 assetAmount, address currency, uint256 currencyAmount, uint256 maxOrders) external returns (uint256);
    function cancel(uint256 orderId) external;
}