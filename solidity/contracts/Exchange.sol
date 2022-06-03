// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

enum Status {
    ACTIVE, CANCELLED, EXECUTED
}

struct Order {
    address owner;
    uint256 amount;
    uint256 price;
    Status status;
    bool split;
}

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


contract Exchange {
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

    receive() external payable { //used to receive wei when msg.data is empty
        revert("Payments need to happen through wrapped Ether"); //as long as Ether is not ERC20 compliant
    }
    
    fallback() external payable { //used to receive wei when msg.data is not empty
        revert("Payments need to happen through wrapped Ether"); //as long as Ether is not ERC20 compliant
    }

    function verifyTokenBalance(address owner, address erc20Token) public view returns (uint256) {
        IERC20 token = IERC20(erc20Token);
        return token.allowance(owner, address(this));
    }
}