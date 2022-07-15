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

enum Ordering {
    LESS_THAN, EQUAL_TO, GREATER_THAN
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
    uint256 previous; //the previous order in the order book with the same currencyAmount/assetAmount ratio, 0 if none
    uint256 next; //the next order in the order book with the same currencyAmount/assetAmount ratio, 0 if none
    Execution[] executions;
}

struct Execution {
    uint256 matchedId;
    uint256 price;
    uint256 amount;
}

struct OrderHead {
    uint256 id;
    uint256 assetAmount;
    uint256 currencyAmount;
    uint256 numberOfOrders;
    uint256 firstOrder;
    uint256 lastOrder;
    uint256 remaining;
    uint256 previous;
    uint256 next;
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

    uint256 private constant MAX_LOW_INT = 2**128 - 1;

    mapping(address => mapping(address => uint256)) lockedUpTokens;

    Order[] private orders;

    mapping(address => mapping(address => OrderHead)) private initialAskOrderHeads;
    mapping(address => mapping(address => OrderHead)) private initialBidOrderHeads;
    mapping(uint256 => OrderHead) private orderHeads; //mapping used to retrieve permanent storage for an OrderHead

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
    function ask(address asset, uint256 assetAmount, address currency, uint256 currencyAmount, uint256) external virtual override returns (uint256) {
        lockUp(msg.sender, asset, assetAmount);
        (uint256 id, Order storage order) = createOrder(OrderType.BID, asset, assetAmount, currency, currencyAmount);
        //TODO only if the order cannot be fully executed
        insertAskOrder(order, id, asset, assetAmount, currency, currencyAmount, assetAmount);

        return id;
    }

    //will execute up to maxOrders orders where assets are bought for the currency at a ratio <= currencyAmount/assetAmount
    function bid(address asset, uint256 assetAmount, address currency, uint256 currencyAmount, uint256) external virtual override returns (uint256) {
        lockUp(msg.sender, currency, currencyAmount);
        (uint256 id, Order storage order) = createOrder(OrderType.BID, asset, assetAmount, currency, currencyAmount);
        //TODO only if the order cannot be fully executed
        insertBidOrder(order, id, asset, assetAmount, currency, currencyAmount, assetAmount);

        return id;
    }

    function cancel(uint256 orderId) external virtual override {
        //TODO return allowances
    }



    function lockUp(address owner, address tokenAddress, uint256 amount) internal {
        IERC20(tokenAddress).safeTransferFrom(owner, address(this), amount); //we have to transfer, we cannot be happy with having an allowance only, because the same allowance can be given away multiple times, but the token can be transferred only once
        lockedUpTokens[owner][tokenAddress] += amount; //the remaining amount is returned to the owner on completion or cancellation of an order
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

    function insertAskOrder(Order storage order, uint256 orderId, address asset, uint256 assetAmount, address currency, uint256 currencyAmount, uint256 remaining) internal {
        OrderHead storage selected = initialAskOrderHeads[asset][currency];
        uint256 selectedId = selected.id;
        if (selectedId == 0) { //an OrderHead has not been created yet
            initialAskOrderHeads[asset][currency] = initOrderHead(order, orderId, assetAmount, currencyAmount, remaining);
        } else {
            Ordering ordering = compare(assetAmount, currencyAmount, selected.assetAmount, selected.currencyAmount);
            if (ordering == Ordering.LESS_THAN) { //the new order has a lower price
                OrderHead storage newInitial = initOrderHead(order, orderId, assetAmount, currencyAmount, remaining);
                initialAskOrderHeads[asset][currency] = newInitial;

                newInitial.next = selectedId;
                selected.previous = orderId;
            } else if (ordering == Ordering.EQUAL_TO) { //the new order has the same price
                addOrderToEnd(selected, order, orderId, remaining);
            } else { //ordering == Ordering.GREATER_THAN, the new order has a higher price
                uint256 previousId = selectedId;
                selectedId = selected.next;

                while (selectedId != 0) {
                    OrderHead storage previous = selected;
                    selected = orderHeads[selectedId];
        
                    ordering = compare(assetAmount, currencyAmount, selected.assetAmount, selected.currencyAmount);
                    if (ordering == Ordering.LESS_THAN) { //the new order has a lower price
                        OrderHead storage newOrderHead = initOrderHead(order, orderId, assetAmount, currencyAmount, remaining);

                        previous.next = orderId;
                        newOrderHead.previous = previousId;
                        newOrderHead.next = selectedId;
                        selected.previous = orderId;

                        return; //do not initiate a new order head at the end of the list
                    } else if (ordering == Ordering.EQUAL_TO) { //the new order has the same price
                        addOrderToEnd(selected, order, orderId, remaining);

                        return; //do not initiate a new order head at the end of the list
                    }

                    previousId = selectedId;
                    selectedId = selected.next;
                }

                //we reached the end of the list
                OrderHead storage lastOrderHead = initOrderHead(order, orderId, assetAmount, currencyAmount, remaining);

                selected.next = orderId; //selected has not been updated before exiting the while loop
                lastOrderHead.previous = previousId; //previousId has been updated before exiting the while loop
            }
        }
    }

    function insertBidOrder(Order storage order, uint256 orderId, address asset, uint256 assetAmount, address currency, uint256 currencyAmount, uint256 remaining) internal {
        OrderHead storage selected = initialBidOrderHeads[asset][currency];
        uint256 selectedId = selected.id;
        if (selectedId == 0) { //an OrderHead has not been created yet
            initialBidOrderHeads[asset][currency] = initOrderHead(order, orderId, assetAmount, currencyAmount, remaining);
        } else {
            Ordering ordering = compare(assetAmount, currencyAmount, selected.assetAmount, selected.currencyAmount);
            if (ordering == Ordering.GREATER_THAN) { //the new order has a higher price
                OrderHead storage newInitial = initOrderHead(order, orderId, assetAmount, currencyAmount, remaining);
                initialBidOrderHeads[asset][currency] = newInitial;

                newInitial.next = selectedId;
                selected.previous = orderId;
            } else if (ordering == Ordering.EQUAL_TO) { //the new order has the same price
                addOrderToEnd(selected, order, orderId, remaining);
            } else { //ordering == Ordering.LESS_THAN, the new order has a lower price
                uint256 previousId = selectedId;
                selectedId = selected.next;

                while (selectedId != 0) {
                    OrderHead storage previous = selected;
                    selected = orderHeads[selectedId];
        
                    ordering = compare(assetAmount, currencyAmount, selected.assetAmount, selected.currencyAmount);
                    if (ordering == Ordering.GREATER_THAN) { //the new order has a higher price
                        OrderHead storage newOrderHead = initOrderHead(order, orderId, assetAmount, currencyAmount, remaining);

                        previous.next = orderId;
                        newOrderHead.previous = previousId;
                        newOrderHead.next = selectedId;
                        selected.previous = orderId;

                        return; //do not initiate a new order head at the end of the list
                    } else if (ordering == Ordering.EQUAL_TO) { //the new order has the same price
                        addOrderToEnd(selected, order, orderId, remaining);

                        return; //do not initiate a new order head at the end of the list
                    }

                    previousId = selectedId;
                    selectedId = selected.next;
                }

                //we reached the end of the list
                OrderHead storage lastOrderHead = initOrderHead(order, orderId, assetAmount, currencyAmount, remaining);

                selected.next = orderId; //selected has not been updated before exiting the while loop
                lastOrderHead.previous = previousId; //previousId has been updated before exiting the while loop
            }
        }
    }

    function initOrderHead(Order storage order, uint256 orderId, uint256 assetAmount, uint256 currencyAmount, uint256 remaining) private returns (OrderHead storage) {
        OrderHead storage orderHead = orderHeads[orderId];

        orderHead.id = orderId;
        orderHead.assetAmount = assetAmount;
        orderHead.currencyAmount = currencyAmount;
        orderHead.numberOfOrders = 1;
        orderHead.firstOrder = orderId;
        orderHead.lastOrder = orderId;
        orderHead.remaining = remaining;

        order.orderHead = orderId;

        return orderHead;
    }

    function addOrderToEnd(OrderHead storage orderHead, Order storage order, uint256 orderId, uint256 remaining) private {
        uint256 secondLast = orderHead.lastOrder;
        orders[secondLast].next = orderId;
        order.orderHead = orderHead.id;
        order.previous = secondLast;
        orderHead.numberOfOrders++;
        orderHead.lastOrder = orderId;
        orderHead.remaining += remaining;
    }

    function compare(uint256 leftAssetAmount, uint256 leftCurrencyAmount, uint256 rightAssetAmount, uint256 rightCurrencyAmount) internal pure returns (Ordering) {
        //leftPrice == leftCurrencyAmount/leftAssetAmount < rightPrice == rightCurrencyAmount/rightAssetAmount
        //<=> leftCurrencyAmount*rightAssetAmount < rightCurrencyAmount*leftAssetAmount

        //see https://medium.com/wicketh/mathemagic-full-multiply-27650fec525d
        uint256 leftLow;
        uint256 leftHigh;
        uint256 rightLow;
        uint256 rightHigh;
        assembly {
            let leftMM := mulmod(leftCurrencyAmount, rightAssetAmount, not(0))
            leftLow := mul(leftCurrencyAmount, rightAssetAmount)
            leftHigh := sub(sub(leftMM, leftLow), lt(leftMM, leftLow))

            let rightMM := mulmod(rightCurrencyAmount, leftAssetAmount, not(0))
            rightLow := mul(rightCurrencyAmount, leftAssetAmount)
            rightHigh := sub(sub(rightMM, rightLow), lt(rightMM, rightLow))
        }

        if (leftHigh < rightHigh) {
            return Ordering.LESS_THAN;
        } else if (leftHigh > rightHigh) {
            return Ordering.GREATER_THAN;
        } else if (leftLow < rightLow) {
            return Ordering.LESS_THAN;
        } else if (leftLow > rightLow) {
            return Ordering.GREATER_THAN;
        } else {
            return Ordering.EQUAL_TO;
        }
    }
}