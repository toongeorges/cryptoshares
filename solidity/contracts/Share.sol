// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import 'contracts/IShare.sol';
import 'contracts/IExchange.sol';

/**
Deleting an array or resetting an array to an empty array is broken in Solidity,
since the gas cost for both is O(n) with n the number of elements in the original array and n can be unbounded.

Whenever an array is used, a mechanism must be provided to reduce the size of the array, to prevent iterating over the array becoming too costly.
This mechanism however cannot rely on deleting or resetting the array, since these operations fail themselves at this point.

Iteration over an array has to happen in a paged manner

Arrays can be reduced as follows:
- we need to store an extra field for the length of the array in exchangesLength (the length property of the exchanges array is only useful to determine whether we have to push or overwrite an existing value)
- we need to store an extra field for the length of the packed array in packedLength (during packing)
- we need to store an extra field for the array index from where the array has not been packed yet in unpackedIndex

if unpackedIndex == 0, all elements of the array are  in [0, exchangesLength[

if unpackedIndex > 0, all elements of the array are in [0, packedLength[ and [unpackedIndex, exchangesLength[
*/
struct ExchangeInfo {
    uint256 unpackedIndex;
    uint256 packedLength;
    mapping(address => uint256) exchangeIndex;
    uint256 exchangesLength;
    address[] exchanges;
}

contract Share is ERC20, IShare {
    using SafeERC20 for IERC20;

    address public owner;

    mapping(address => ExchangeInfo) private exchangeInfo;

    /**
    In order to save gas costs while iterating over shareholders, they can be packed (old shareholders that are no shareholders anymore are removed)
    Packing is in progress if and only if unpackedShareholderIndex > 0

    if unpackedShareholderIndex == 0, we find all shareholders for the indices [1, shareholdersLength[
    
    if unpackedShareholderIndex > 0, we find all shareholders for the indices [1, packedShareholdersLength[ and [unpackedShareholderIndex, shareholdersLength[
     */
    uint256 private unpackedShareholderIndex; //up to where the packing went, 0 if no packing in progress
    uint256 private packedShareholdersLength; //up to where the packing went, 0 if no packing in progress
    mapping(address => uint256) private shareholderIndex;
    uint256 private shareholdersLength; //after packing, the (invalid) contents at a location from this index onwards are ignored
    address[] private shareholders; //we need to keep track of the shareholders in case of distributing a dividend

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        owner = msg.sender;
        shareholders.push(address(this)); //to make later operations on shareholders less costly
        shareholdersLength++;
    }



    function decimals() public pure override returns (uint8) {
        return 0;
    }

    receive() external payable { //used to receive wei when msg.data is empty
        revert DoNotAcceptEtherPayments();
    }

    fallback() external payable { //used to receive wei when msg.data is not empty
        revert DoNotAcceptEtherPayments();
    }



    function getLockedUpAmount(address tokenAddress) public view override returns (uint256) {
        ExchangeInfo storage info = exchangeInfo[tokenAddress];
        address[] storage exchanges = info.exchanges;
        IERC20 token = IERC20(tokenAddress);

        uint256 lockedUpAmount = 0;
        uint256 unpackedIndex = info.unpackedIndex;
        if (unpackedIndex == 0) {
            for (uint256 i = 0; i < info.exchangesLength; i++) {
                lockedUpAmount += token.allowance(address(this), exchanges[i]);
            }
        } else {
            for (uint256 i = 0; i < info.packedLength; i++) {
                lockedUpAmount += token.allowance(address(this), exchanges[i]);
            }
            for (uint256 i = unpackedIndex; i < info.exchangesLength; i++) {
                lockedUpAmount += token.allowance(address(this), exchanges[i]);
            }
        }
        return lockedUpAmount;
    }

    function getAvailableAmount(address tokenAddress) public view override returns (uint256) {
        return IERC20(tokenAddress).balanceOf(address(this)) - getLockedUpAmount(tokenAddress);
    }

    function getTreasuryShareCount() public view override returns (uint256) { //return the number of shares held by the company
        return balanceOf(address(this)) - getLockedUpAmount(address(this));
    }

    function getOutstandingShareCount() public view override returns (uint256) { //return the number of shares not held by the company
        return totalSupply() - balanceOf(address(this));
    }

    //getMaxOutstandingShareCount() >= getOutstandingShareCount(), we are also counting the shares that have been locked up in exchanges and may be sold
    function getMaxOutstandingShareCount() public view override returns (uint256) {
        return totalSupply() - getTreasuryShareCount();
    }



    function getExchangeCount(address tokenAddress) external view returns (uint256) {
        return exchangeInfo[tokenAddress].exchangesLength;        
    }

    function getExchangePackSize(address tokenAddress) external view returns (uint256) {
        ExchangeInfo storage info = exchangeInfo[tokenAddress];
        return info.exchangesLength - info.unpackedIndex;
    }

    function registerExchange(address tokenAddress, address exchange) internal {
        ExchangeInfo storage info = exchangeInfo[tokenAddress];
        mapping(address => uint256) storage exchangeIndex = info.exchangeIndex;
        uint256 index = exchangeIndex[exchange];
        if (index == 0) { //the exchange has not been registered yet OR was the first registered exchange
            address[] storage exchanges = info.exchanges;
            if ((exchanges.length == 0) || (exchanges[0] != exchange)) { //the exchange has not been registered yet
                if (IERC20(tokenAddress).allowance(address(this), exchange) > 0) {
                    index = info.exchangesLength;
                    exchangeIndex[exchange] = index;
                    if (index < exchanges.length) {
                        exchanges[index] = exchange;
                    } else {
                        exchanges.push(exchange);
                    }
                    info.exchangesLength++;
                }
            }
        }
    }

    function packExchanges(address tokenAddress, uint256 amountToPack) external override {
        require(amountToPack > 0);

        ExchangeInfo storage info = exchangeInfo[tokenAddress];

        uint256 start = info.unpackedIndex;
        uint256 end = start + amountToPack;
        uint maxEnd = info.exchangesLength;
        if (end > maxEnd) {
            end = maxEnd;
        }

        uint256 packedIndex;
        if (start == 0) { //start a new packing
            packedIndex = 0;
        } else {
            packedIndex = info.packedLength;
        }

        mapping(address => uint256) storage exchangeIndex = info.exchangeIndex;
        address[] storage exchanges = info.exchanges;
        IERC20 token = IERC20(tokenAddress);
        for (uint256 i = start; i < end; i++) {
            address exchange = exchanges[i];
            if (token.allowance(address(this), exchange) > 0) { //only register if the exchange still has locked up tokens
                exchangeIndex[exchange] = packedIndex;
                exchanges[packedIndex] = exchange;
                packedIndex++;
            } else {
                exchangeIndex[exchange] = 0;
            }
        }
        info.packedLength = packedIndex;

        if (end == maxEnd) {
            info.unpackedIndex = 0;
            info.exchangesLength = packedIndex;
        } else {
            info.unpackedIndex = end;
        }
    }

    function getShareholderCount() public view override returns (uint256) {
        return shareholdersLength - 1; //the first address is taken by this contract, which is not a shareholder
    }

    function registerShareholder(address shareholder) external override returns (uint256) {
        uint256 index = shareholderIndex[shareholder];
        if (index == 0) { //the shareholder has not been registered yet (the address at index 0 is this contract)
            if (balanceOf(shareholder) > 0) { //only register if the address is an actual shareholder
                index = shareholdersLength;
                shareholderIndex[shareholder] = index;
                if (index < shareholders.length) {
                    shareholders[index] = shareholder;
                } else {
                    shareholders.push(shareholder);
                }
                shareholdersLength++;
                return index;
            }
        }
        return index;
    }

    function getShareholderPackSize() external view returns (uint256) {
        return (unpackedShareholderIndex == 0) ? getShareholderCount() : (shareholdersLength - unpackedShareholderIndex);
    }

    function packShareholders(uint256 amountToPack) external override {
        require(amountToPack > 0);

        uint256 start = unpackedShareholderIndex;
        uint256 end = start + amountToPack;
        uint maxEnd = shareholdersLength;
        if (end > maxEnd) {
            end = maxEnd;
        }

        uint256 packedIndex;
        if (start == 0) { //start a new packing
            start = 1;
            packedIndex = 1;
        } else {
            packedIndex = packedShareholdersLength;
        }

        for (uint256 i = start; i < end; i++) {
            address shareholder = shareholders[i];
            if (balanceOf(shareholder) > 0) { //only register if the address is an actual shareholder
                shareholderIndex[shareholder] = packedIndex;
                shareholders[packedIndex] = shareholder;
                packedIndex++;
            } else {
                shareholderIndex[shareholder] = 0;
            }
        }
        packedShareholdersLength = packedIndex;

        if (end == maxEnd) {
            unpackedShareholderIndex = 0;
            shareholdersLength = packedIndex;
        } else {
            unpackedShareholderIndex = end;
        }
    }
}