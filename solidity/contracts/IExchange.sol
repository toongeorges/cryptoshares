// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

error DoNotAcceptEtherPayments();
error StrictlyPositiveAssetAmountRequired();
error StrictlyPositivePriceRequired();
error CannotCancel();
error EmptyArray();
error ArraysOfDifferentLength(uint256 firstLength, uint256 secondLength);
error ArbitrageGainTooSmall(uint256 requiredGain, uint256 initialAmount, uint256 roundTripAmount);
error OrderCountTooHigh(uint256 maxOrders, uint256 actualOrders);

interface IExchange {
    //tokens that are sold have to be locked up in the exchange before trade.  These tokens are released either on execution of the order or when the order is cancelled.
    function getLockedUpAmount(address erc2OAddress) external view returns (uint256);
    //will execute up to maxOrders orders where assets are sold for the currency at a price greater than or equal the price given
    function ask(address asset, uint256 assetAmount, address currency, uint256 price, uint256 maxOrders) external returns (uint256);
    //will execute up to maxOrders orders where assets are bought for the currency at a price smaller than or equal to the price given
    function bid(address asset, uint256 assetAmount, address currency, uint256 price, uint256 maxOrders) external returns (uint256);
    //cancels the not executed part of the order
    function cancel(uint256 orderId) external;
}