// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import 'contracts/IExchange.sol';

enum OrderType {
    ASK, BID
}

enum OrderStatus {
    ACTIVE, CANCELLED, EXECUTED
}

struct Order {
    address owner;
    OrderType orderType;
    OrderStatus status;
    address asset;
    uint256 assetAmount;
    address currency;
    uint256 currencyAmount;
    uint256 remaining;
    uint256 orderHead;
    uint256 previousOrder; //the previous order in the order book with the same currencyAmount/assetAmount ratio, 0 if none
    uint256 nextOrder; //the next order in the order book with the same currencyAmount/assetAmount ratio, 0 if none
    Execution[] executions;
}

struct Execution {
    uint256 matchedId;
    uint256 price;
    uint256 amount;
}

struct OrderHead {
    uint256 assetAmount;
    uint256 currencyAmount;
    uint256 firstOrder;
    uint256 lastOrder;
    uint256 remaining;
    uint256 nextOrderHead;
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

    Order[] private orders;
    OrderHead[] private orderHeads;
    
    mapping(address => mapping(address => OrderHead)) private initialOrderHeads;

    event ActiveOrder(uint256 orderId, OrderType orderType, address indexed owner, address indexed asset, uint256 assetAmount, address indexed currency, uint256 currencyAmount);

    /*
    address[] public listedTokens; //listed ERC20 tokens
    mapping(address => OrderBook) public orderbook;

    event SplitAsk(uint256 orderId, address indexed owner, address indexed asset, uint256 splitAmount, address indexed currency, uint256 splitOrderId);
    event SplitBid(uint256 orderId, address indexed owner, address indexed asset, uint256 splitAmount, address indexed currency, uint256 splitOrderId);
    event CancelAsk(uint256 orderId, address indexed owner, address indexed asset, uint256 amount, address indexed currency);
    event CancelBid(uint256 orderId, address indexed owner, address indexed asset, uint256 amount, address indexed currency);
    event ExecuteAsk(uint256 orderId, address indexed owner, address indexed asset, uint256 amount, address indexed currency);
    event ExecuteBid(uint256 orderId, address indexed owner, address indexed asset, uint256 amount, address indexed currency);
    event Trade(address indexed asset, uint256 amount, address indexed currency, uint256 price);
    */

    constructor() {
        orders.push(); //push an order so there cannot be an order with id == 0, if there is a reference to an order with id == 0, it means there is a reference to no order
    }

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
        (uint256 id, Order storage order) = createOrder(OrderType.BID, asset, assetAmount, currency, currencyAmount);

        return id;
    }

    //will execute up to maxOrders orders where assets are bought for the currency at a ratio <= currencyAmount/assetAmount
    function bid(address asset, uint256 assetAmount, address currency, uint256 currencyAmount, uint256 maxOrders) external virtual override returns (uint256) {
        lockUp(msg.sender, currency, currencyAmount);
        (uint256 id, Order storage order) = createOrder(OrderType.BID, asset, assetAmount, currency, currencyAmount);

        return id;
    }

    function createOrder(OrderType orderType, address asset, uint256 assetAmount, address currency, uint256 currencyAmount) internal returns (uint256, Order storage) {
        uint256 id = orders.length;

        Order storage order = orders.push();
        order.owner = msg.sender;
        order.orderType = orderType;
        order.status = OrderStatus.ACTIVE;
        order.asset = asset;
        order.assetAmount = assetAmount;
        order.currency = currency;
        order.currencyAmount = currencyAmount;
        order.remaining = assetAmount;

        emit ActiveOrder(id, orderType, msg.sender, asset, assetAmount, currency, currencyAmount);

        return (id, order);
    }

    function findOrCreateOrderHead() internal {
        
    }

    function cancel(uint256 orderId) external virtual override {
        //TODO return allowances
    }

    function lockUp(address owner, address tokenAddress, uint256 amount) internal {
        IERC20(tokenAddress).safeTransferFrom(owner, address(this), amount); //we have to transfer, we cannot be happy with having an allowance only, because the same allowance can be given away multiple times, but the token can be transferred only once
        lockedUpTokens[owner][tokenAddress] += amount; //the remaining amount is returned to the owner on completion or cancellation of an order
    }
}