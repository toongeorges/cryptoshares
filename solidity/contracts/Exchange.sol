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
    uint256 price;
    uint256 remaining;
    uint256 orderHead;
    uint256 previous; //the previous order in the order book with the same price, 0 if none
    uint256 next; //the next order in the order book with the same price, 0 if none
    Execution[] executions;
}

struct Execution {
    uint256 matchedId;
    uint256 price;
    uint256 amount;
}

struct OrderBookItem {
    uint256 price;
    uint256 numberOfOrders;
    uint256 remaining;
}

struct OrderHead {
    uint256 id;
    uint256 price;
    uint256 numberOfOrders;
    uint256 firstOrder;
    uint256 lastOrder;
    uint256 remaining;
    uint256 previous;
    uint256 next;
}

contract Exchange is IExchange {
    using SafeERC20 for IERC20;

    uint256 private constant MAX_LOW_INT = 2**128 - 1;

    mapping(address => mapping(address => uint256)) lockedUpTokens;

    Order[] private orders;

    mapping(address => mapping(address => OrderHead)) private initialAskOrderHeads;
    mapping(address => mapping(address => OrderHead)) private initialBidOrderHeads;
    mapping(uint256 => OrderHead) private orderHeads; //mapping used to retrieve permanent storage for an OrderHead

    event ActiveOrder(uint256 orderId, OrderType orderType, address indexed owner, address indexed asset, uint256 assetAmount, address indexed currency, uint256 price);
    event Trade(uint256 indexed sellId, uint256 indexed buyId, address indexed asset, uint256 assetAmount, address currency, uint256 price);
    event ExecutedOrder(uint256 orderId, OrderType orderType, address indexed owner, address indexed asset, uint256 assetAmount, address indexed currency, uint256 price, uint256 numberOfExecutions);
    event CancelledOrder(uint256 orderId, OrderType orderType, address indexed owner, address indexed asset, uint256 assetAmount, address indexed currency, uint256 price, uint256 numberOfExecutions);

    /*
    address[] public listedTokens; //listed ERC20 tokens
    mapping(address => OrderBook) public orderbook;
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

    //will execute up to maxOrders orders where assets are sold for the currency at a price greater than or equal to the price given
    function ask(address asset, uint256 assetAmount, address currency, uint256 price, uint256 maxOrders) external virtual override returns (uint256) {
        if (assetAmount == 0) { //do not allow fake orders
            revert StrictlyPositiveAssetAmountRequired();
        }
        lockUp(msg.sender, asset, assetAmount);
        (uint256 id, Order storage order) = createOrder(OrderType.BID, asset, assetAmount, currency, price);
        uint256 remaining = matchAskOrder(id, order, asset, currency, price, assetAmount, maxOrders);
        insertAskOrder(id, order, asset, currency, price, remaining);

        return id;
    }

    //will execute up to maxOrders orders where assets are bought for the currency at a price less than or equal to the price given
    function bid(address asset, uint256 assetAmount, address currency, uint256 price, uint256 maxOrders) external virtual override returns (uint256) {
        if (assetAmount == 0) { //do not allow fake orders
            revert StrictlyPositiveAssetAmountRequired();
        }
        lockUp(msg.sender, currency, assetAmount*price);
        (uint256 id, Order storage order) = createOrder(OrderType.BID, asset, assetAmount, currency, price);
        uint256 remaining = matchBidOrder(id, order, asset, currency, price, assetAmount, maxOrders);
        insertBidOrder(id, order, asset, currency, price, remaining);

        return id;
    }

    function cancel(uint256 orderId) external virtual override {
        Order storage order = orders[orderId];
        if ((order.status != OrderStatus.ACTIVE) || (order.owner != msg.sender)) {
            revert CannotCancel();
        } else {
            order.status = OrderStatus.CANCELLED;

            OrderHead storage head = orderHeads[order.orderHead];

            uint256 numberOfOrders = head.numberOfOrders;
            numberOfOrders--;
            uint256 remaining = order.remaining;

            head.numberOfOrders = numberOfOrders;
            head.remaining -= remaining;

            if (order.orderType == OrderType.ASK) {
                if (numberOfOrders == 0) { //remove order head
                    removeOrderHead(head, order, setInitialAskOrderHead);
                } else { //remove order in order head
                    removeOrderFromHead(head, order);
                }

                release(msg.sender, order.asset, remaining);
            } else { //order.orderType == OrderType.BID
                if (numberOfOrders == 0) { //remove order head
                    removeOrderHead(head, order, setInitialBidOrderHead);
                } else { //remove order in order head
                    removeOrderFromHead(head, order);
                }

                release(msg.sender, order.currency, order.remaining*order.price);
            }
        }
    }


    function getAskOrderBook(address asset, address currency, uint256 depth) external virtual view returns (OrderBookItem[] memory) {
        return getOrderBook(asset, currency, depth, initialAskOrderHeads[asset][currency]);
    }

    function getBidOrderBook(address asset, address currency, uint256 depth) external virtual view returns (OrderBookItem[] memory) {
        return getOrderBook(asset, currency, depth, initialBidOrderHeads[asset][currency]);
    }

    function getOrderBook(address asset, address currency, uint256 depth, OrderHead storage head) internal view returns (OrderBookItem[] memory) {
        OrderBookItem[] memory orderBook = new OrderBookItem[](depth);
        for (uint256 i = 0; i < depth; i++) {
            orderBook[i] = OrderBookItem({
                price: head.price,
                numberOfOrders: head.numberOfOrders,
                remaining: head.remaining
            });

            uint256 nextHeadId = head.next;
            if (nextHeadId == 0) {
                break;
            }
            head = orderHeads[nextHeadId];
        }

        return orderBook;
    }
    
    function getOrderDetails(uint256 orderId) external virtual view returns (address, OrderType, OrderStatus, address, uint256, address, uint256, uint256, uint256) {
        Order storage o = orders[orderId];
        return (o.owner, o.orderType, o.status, o.asset, o.assetAmount, o.currency, o.price, o.remaining, o.executions.length);
    }



    function lockUp(address owner, address tokenAddress, uint256 amount) internal {
        IERC20(tokenAddress).safeTransferFrom(owner, address(this), amount); //we have to transfer, we cannot be happy with having an allowance only, because the same allowance can be given away multiple times, but the token can be transferred only once
        lockedUpTokens[owner][tokenAddress] += amount; //the remaining amount is returned to the owner on completion or cancellation of an order
    }

    function release(address owner, address tokenAddress, uint256 amount) internal {
        lockedUpTokens[owner][tokenAddress] -= amount;
        IERC20(tokenAddress).safeTransfer(owner, amount);
    }

    function createOrder(OrderType orderType, address asset, uint256 assetAmount, address currency, uint256 price) internal returns (uint256, Order storage) {
        uint256 id = orders.length;

        Order storage order = orders.push();
        order.owner = msg.sender;
        order.orderType = orderType;
        order.status = OrderStatus.ACTIVE;
        order.asset = asset;
        order.assetAmount = assetAmount;
        order.currency = currency;
        order.price = price;
        order.remaining = assetAmount;

        emit ActiveOrder(id, orderType, msg.sender, asset, assetAmount, currency, price);

        return (id, order);
    }

    function matchAskOrder(uint256 sellId, Order storage sellOrder, address asset, address currency, uint256 price, uint256 remaining, uint maxOrders) internal returns (uint256) {
        if (maxOrders > 0) {
            OrderHead storage bids = initialBidOrderHeads[asset][currency];
            uint256 matchedPrice = bids.price;
            uint256 buyId = bids.firstOrder;

            //while bid orders are willing to pay at least the ask price
            while ((buyId > 0) && (maxOrders > 0) && (remaining > 0) && (price <= matchedPrice)) {
                Order storage buyOrder = orders[buyId];
                (remaining, bids) = singleAskTrade(bids, sellId, sellOrder, buyId, buyOrder, asset, currency, matchedPrice, remaining);
                maxOrders--;
                matchedPrice = bids.price;
                buyId = bids.firstOrder;
            }
        }

        return remaining;
    }

    function singleAskTrade(OrderHead storage bids, uint256 sellId, Order storage sellOrder, uint256 buyId, Order storage buyOrder, address asset, address currency, uint256 matchedPrice, uint256 remaining) internal returns (uint256, OrderHead storage) {
        uint256 buyOrderRemaining = buyOrder.remaining;
        if (buyOrderRemaining > remaining) {
            trade(sellId, sellOrder, buyId, buyOrder, asset, currency, matchedPrice, remaining);

            markOrderExecuted(sellId, sellOrder);

            bids.remaining -= remaining;

            return (0, bids);
        } else if (buyOrderRemaining == remaining) {
            trade(sellId, sellOrder, buyId, buyOrder, asset, currency, matchedPrice, remaining);

            markOrderExecuted(sellId, sellOrder);
            markOrderExecuted(buyId, buyOrder);

            bids.remaining -= remaining;

            bids = popBidOrder(bids, buyOrder, asset, currency);

            return (0, bids);
        } else {
            trade(sellId, sellOrder, buyId, buyOrder, asset, currency, matchedPrice, buyOrderRemaining);

            markOrderExecuted(buyId, buyOrder);

            bids.remaining -= buyOrderRemaining;

            bids = popBidOrder(bids, buyOrder, asset, currency);

            return ((remaining - buyOrderRemaining), bids);
        }
    }

    function insertAskOrder(uint256 orderId, Order storage order, address asset, address currency, uint256 price, uint256 remaining) internal {
        if (remaining > 0) {
            OrderHead storage selected = initialAskOrderHeads[asset][currency];
            uint256 selectedId = selected.id;
            if (selectedId == 0) { //an OrderHead has not been created yet
                initialAskOrderHeads[asset][currency] = initOrderHead(orderId, order, price, remaining);
            } else {
                uint256 selectedPrice = selected.price;
                if (price < selectedPrice) { //the new order has a lower price
                    OrderHead storage newInitial = initOrderHead(orderId, order, price, remaining);
                    initialAskOrderHeads[asset][currency] = newInitial;

                    newInitial.next = selectedId;
                    selected.previous = orderId;
                } else if (price == selectedPrice) { //the new order has the same price
                    addOrderToEnd(selected, orderId, order, remaining);
                } else { //ordering == Ordering.GREATER_THAN, the new order has a higher price
                    uint256 previousOrderHeadId = selectedId;
                    selectedId = selected.next;

                    while (selectedId != 0) {
                        OrderHead storage previous = selected;
                        selected = orderHeads[selectedId];
                        selectedPrice = selected.price;
            
                        if (price < selectedPrice) { //the new order has a lower price
                            OrderHead storage newOrderHead = initOrderHead(orderId, order, price, remaining);

                            previous.next = orderId;
                            newOrderHead.previous = previousOrderHeadId;
                            newOrderHead.next = selectedId;
                            selected.previous = orderId;

                            return; //do not initiate a new order head at the end of the list
                        } else if (price == selectedPrice) { //the new order has the same price
                            addOrderToEnd(selected, orderId, order, remaining);

                            return; //do not initiate a new order head at the end of the list
                        }

                        previousOrderHeadId = selectedId;
                        selectedId = selected.next;
                    }

                    //we reached the end of the list
                    OrderHead storage lastOrderHead = initOrderHead(orderId, order, price, remaining);

                    selected.next = orderId; //selected has not been updated before exiting the while loop
                    lastOrderHead.previous = previousOrderHeadId; //previousOrderHeadId has been updated before exiting the while loop
                }
            }
        }
    }

    function matchBidOrder(uint256 buyId, Order storage buyOrder, address asset, address currency, uint256 price, uint256 remaining, uint maxOrders) internal returns (uint256) {
        if (maxOrders > 0) {
            OrderHead storage asks = initialAskOrderHeads[asset][currency];
            uint256 matchedPrice = asks.price;
            uint256 sellId = asks.firstOrder;

            //while bid orders are willing to pay at least the ask price
            while ((sellId > 0) && (maxOrders > 0) && (remaining > 0) && (price >= matchedPrice)) {
                Order storage sellOrder = orders[sellId];
                (remaining, asks) = singleBidTrade(asks, sellId, sellOrder, buyId, buyOrder, asset, currency, matchedPrice, remaining);
                maxOrders--;
                matchedPrice = asks.price;
                sellId = asks.firstOrder;
            }
        }

        return remaining;
    }

    function singleBidTrade(OrderHead storage asks, uint256 sellId, Order storage sellOrder, uint256 buyId, Order storage buyOrder, address asset, address currency, uint256 matchedPrice, uint256 remaining) internal returns (uint256, OrderHead storage) {
        uint256 sellOrderRemaining = sellOrder.remaining;
        if (sellOrderRemaining > remaining) {
            trade(sellId, sellOrder, buyId, buyOrder, asset, currency, matchedPrice, remaining);

            markOrderExecuted(buyId, buyOrder);

            asks.remaining -= remaining;

            return (0, asks);
        } else if (sellOrderRemaining == remaining) {
            trade(sellId, sellOrder, buyId, buyOrder, asset, currency, matchedPrice, remaining);

            markOrderExecuted(sellId, sellOrder);
            markOrderExecuted(buyId, buyOrder);

            asks.remaining -= remaining;

            asks = popAskOrder(asks, sellOrder, asset, currency);

            return (0, asks);
        } else {
            trade(sellId, sellOrder, buyId, buyOrder, asset, currency, matchedPrice, sellOrderRemaining);

            markOrderExecuted(sellId, sellOrder);

            asks.remaining -= sellOrderRemaining;

            asks = popAskOrder(asks, sellOrder, asset, currency);

            return ((remaining - sellOrderRemaining), asks);
        }
    }

    function insertBidOrder(uint256 orderId, Order storage order, address asset, address currency, uint256 price, uint256 remaining) internal {
        if (remaining > 0) {
            OrderHead storage selected = initialBidOrderHeads[asset][currency];
            uint256 selectedId = selected.id;
            if (selectedId == 0) { //an OrderHead has not been created yet
                initialBidOrderHeads[asset][currency] = initOrderHead(orderId, order,price, remaining);
            } else {
                uint256 selectedPrice = selected.price;
                if (price > selectedPrice) { //the new order has a higher price
                    OrderHead storage newInitial = initOrderHead(orderId, order, price, remaining);
                    initialBidOrderHeads[asset][currency] = newInitial;

                    newInitial.next = selectedId;
                    selected.previous = orderId;
                } else if (price == selectedPrice) { //the new order has the same price
                    addOrderToEnd(selected, orderId, order, remaining);
                } else { //the new order has a lower price
                    uint256 previousOrderHeadId = selectedId;
                    selectedId = selected.next;

                    while (selectedId != 0) {
                        OrderHead storage previous = selected;
                        selected = orderHeads[selectedId];
                        selectedPrice = selected.price;
            
                        if (price > selectedPrice) { //the new order has a higher price
                            OrderHead storage newOrderHead = initOrderHead(orderId, order, price, remaining);

                            previous.next = orderId;
                            newOrderHead.previous = previousOrderHeadId;
                            newOrderHead.next = selectedId;
                            selected.previous = orderId;

                            return; //do not initiate a new order head at the end of the list
                        } else if (price == selectedPrice) { //the new order has the same price
                            addOrderToEnd(selected, orderId, order, remaining);

                            return; //do not initiate a new order head at the end of the list
                        }

                        previousOrderHeadId = selectedId;
                        selectedId = selected.next;
                    }

                    //we reached the end of the list
                    OrderHead storage lastOrderHead = initOrderHead(orderId, order, price, remaining);

                    selected.next = orderId; //selected has not been updated before exiting the while loop
                    lastOrderHead.previous = previousOrderHeadId; //previousOrderHeadId has been updated before exiting the while loop
                }
            }
        }
    }

    function trade(uint256 sellId, Order storage sellOrder, uint256 buyId, Order storage buyOrder, address asset, address currency, uint256 price, uint256 amount) internal {
        address seller = sellOrder.owner;
        address buyer = buyOrder.owner;

        uint256 actualTotal = amount*price;
        uint256 maxBuyTotal = amount*buyOrder.price;
        lockedUpTokens[seller][asset] -= amount;
        lockedUpTokens[buyer][currency] -= maxBuyTotal;
        IERC20(asset).safeTransfer(buyer, amount);
        IERC20(currency).safeTransfer(seller, actualTotal);
        IERC20(currency).safeTransfer(buyer, (maxBuyTotal - actualTotal));

        sellOrder.remaining -= amount;
        sellOrder.executions.push(Execution({
            matchedId: buyId,
            price: price,
            amount: amount
        }));

        buyOrder.remaining -= amount;
        buyOrder.executions.push(Execution({
            matchedId: sellId,
            price: price,
            amount: amount
        }));

        emit Trade(sellId, buyId, asset, amount, currency, price);
    }

    function markOrderExecuted(uint256 orderId, Order storage order) internal {
        order.status = OrderStatus.EXECUTED;

        emit ExecutedOrder(orderId, order.orderType, order.owner, order.asset, order.assetAmount, order.currency, order.price, order.executions.length);
    }

    function popAskOrder(OrderHead storage head, Order storage firstOrder, address asset, address currency) internal returns (OrderHead storage) {
        uint256 numberOfOrders = head.numberOfOrders;
        numberOfOrders--;

        head.numberOfOrders = numberOfOrders;

        if (numberOfOrders == 0) {
            head = orderHeads[head.next];
            head.previous = 0;
            initialAskOrderHeads[asset][currency] = head;

            return head;
        } else {
            head.firstOrder = firstOrder.next;

            return head;
        }
    }

    function popBidOrder(OrderHead storage head, Order storage firstOrder, address asset, address currency) internal returns (OrderHead storage) {
        uint256 numberOfOrders = head.numberOfOrders;
        numberOfOrders--;

        head.numberOfOrders = numberOfOrders;

        if (numberOfOrders == 0) {
            head = orderHeads[head.next];
            head.previous = 0;
            initialBidOrderHeads[asset][currency] = head;

            return head;
        } else {
            head.firstOrder = firstOrder.next;

            return head;
        }
    }

    function initOrderHead(uint256 orderId, Order storage order, uint256 price, uint256 remaining) private returns (OrderHead storage) {
        OrderHead storage orderHead = orderHeads[orderId];

        orderHead.id = orderId;
        orderHead.price = price;
        orderHead.numberOfOrders = 1;
        orderHead.firstOrder = orderId;
        orderHead.lastOrder = orderId;
        orderHead.remaining = remaining;

        order.orderHead = orderId;

        return orderHead;
    }

    function removeOrderHead(OrderHead storage orderHead, Order storage order, function(address, address, OrderHead storage) setInitialOrderHead) internal {
        uint256 previousOrderHeadId = orderHead.previous;
        uint256 nextOrderHeadId = orderHead.next;

        if (previousOrderHeadId == 0) {
            orderHead = orderHeads[nextOrderHeadId];
            orderHead.previous = 0;
            setInitialOrderHead(order.asset, order.currency, orderHead);
        } else {
            orderHeads[previousOrderHeadId].next = nextOrderHeadId;

            if (nextOrderHeadId != 0) {
                orderHeads[nextOrderHeadId].previous = previousOrderHeadId;
            }
        }
    }

    function setInitialAskOrderHead(address asset, address currency, OrderHead storage orderHead) internal {
        initialAskOrderHeads[asset][currency] = orderHead;
    }

    function setInitialBidOrderHead(address asset, address currency, OrderHead storage orderHead) internal {
        initialBidOrderHeads[asset][currency] = orderHead;
    }

    function addOrderToEnd(OrderHead storage orderHead, uint256 orderId, Order storage order, uint256 remaining) private {
        uint256 secondLast = orderHead.lastOrder;
        orders[secondLast].next = orderId;
        order.orderHead = orderHead.id;
        order.previous = secondLast;
        orderHead.numberOfOrders++;
        orderHead.lastOrder = orderId;
        orderHead.remaining += remaining;
    }

    function removeOrderFromHead(OrderHead storage head, Order storage order) internal {
        uint256 previousOrderId = order.previous;
        uint256 nextOrderId = order.next;

        //this internal method is only called when there is still another order in the head,
        //so previousOrderId and nextOrderId cannot be 0 at the same time
        if (previousOrderId == 0) {
            head.firstOrder = nextOrderId;
            orders[nextOrderId].previous = 0;
        } else if (nextOrderId == 0) {
            head.lastOrder = previousOrderId;
            orders[previousOrderId].next = 0;
        } else {
            orders[previousOrderId].next = nextOrderId;
            orders[nextOrderId].previous = previousOrderId;
        }
    }
}