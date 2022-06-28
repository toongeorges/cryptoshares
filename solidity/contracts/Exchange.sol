// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import 'contracts/IExchange.sol';

enum Type {
    ASK, BID
}

enum Status {
    ACTIVE, CANCELLED, EXECUTED
}

struct Order {
    address owner;
    Type orderType;
    Status status;
    address offer;
    uint256 offerRatio;
    address request;
    uint256 requestRatio;
    uint256 remaining;
    Execution[] executions;
}

struct Execution {
    uint256 matchedId;
    uint256 price;
    uint256 amount;
}

/*
struct OrderList {
    mapping(uint256 => Order) asks;
    mapping(address => uint256[]) asksByUser;
    uint256 activeAskSize;
    uint256 firstAsk;
    mapping(uint256 => uint256) nextAsk;

    mapping(uint256 => Order) bids;
    mapping(address => uint256[]) bidsByUser;
    uint256 activeBidSize;
    uint256 firstBid;
    mapping(uint256 => uint256) nextBid;
}

struct OrderBook {
    uint256 orderId;
    address[] currencies;
    mapping(address => OrderList) ordersByCurrency;
}
*/

contract Exchange is IExchange {
    using SafeERC20 for IERC20;

    mapping(address => mapping(address => uint256)) lockedUpTokens;

    uint256 orderId;

    /*
    address[] public listedTokens; //listed ERC20 tokens
    mapping(address => OrderBook) public orderbook;

    event Ask(uint256 orderId, address indexed owner, address indexed asset, uint256 amount, address indexed currency, uint256 price);
    event Bid(uint256 orderId, address indexed owner, address indexed asset, uint256 amount, address indexed currency, uint256 price);
    event SplitAsk(uint256 orderId, address indexed owner, address indexed asset, uint256 splitAmount, address indexed currency, uint256 splitOrderId);
    event SplitBid(uint256 orderId, address indexed owner, address indexed asset, uint256 splitAmount, address indexed currency, uint256 splitOrderId);
    event CancelAsk(uint256 orderId, address indexed owner, address indexed asset, uint256 amount, address indexed currency);
    event CancelBid(uint256 orderId, address indexed owner, address indexed asset, uint256 amount, address indexed currency);
    event ExecuteAsk(uint256 orderId, address indexed owner, address indexed asset, uint256 amount, address indexed currency);
    event ExecuteBid(uint256 orderId, address indexed owner, address indexed asset, uint256 amount, address indexed currency);
    event Trade(address indexed asset, uint256 amount, address indexed currency, uint256 price);
    */

    receive() external payable { //used to receive wei when msg.data is empty
        revert DoNotAcceptEtherPayments(); //as long as Ether is not ERC20 compliant
    }
    
    fallback() external payable { //used to receive wei when msg.data is not empty
        revert DoNotAcceptEtherPayments(); //as long as Ether is not ERC20 compliant
    }

    function getLockedUpAmount(address erc2OAddress) external view returns (uint256) {
        return lockedUpTokens[msg.sender][erc2OAddress];
    }

    //will execute up to maxOrders orders where assets are sold for the currency at a ratio >= currencyAmount/assetAmount
    function ask(address asset, uint256 assetAmount, address currency, uint256 currencyAmount, uint256 maxOrders) external virtual override returns (uint256) {
        lockUp(msg.sender, asset, assetAmount);
        return 0;
    }

    //will execute up to maxOrders orders where assets are bought for the currency at a ratio <= currencyAmount/assetAmount
    function bid(address asset, uint256 assetAmount, address currency, uint256 currencyAmount, uint256 maxOrders) external virtual override returns (uint256) {
        lockUp(msg.sender, currency, currencyAmount);
        return 0;
    }

    function cancel(uint256 orderId) external virtual override {
        //TODO return allowances
    }

    function lockUp(address owner, address tokenAddress, uint256 amount) internal {
        IERC20(tokenAddress).safeTransferFrom(owner, address(this), amount); //we have to transfer, we cannot be happy with having an allowance only, because the same allowance can be given away multiple times, but the token can be transferred only once
        lockedUpTokens[owner][tokenAddress] += amount; //the remaining amount is returned to the owner on completion or cancellation of an order
    }
}