// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import 'contracts/IShareInfo.sol';
import 'contracts/IShare.sol';

contract ShareInfo is IShareInfo {
    mapping(address => mapping(address => mapping(address => uint256))) private approvedExchangeIndexByToken;
    mapping(address => mapping(address => address[])) private approvedExchangesByToken;



    receive() external payable { //used to receive wei when msg.data is empty
        revert();
    }

    fallback() external payable { //used to receive wei when msg.data is not empty
        revert();
    }



    function getLockedUpAmount(address shareAddress, address tokenAddress) public view override returns (uint256) {
        address[] storage exchanges = approvedExchangesByToken[shareAddress][tokenAddress];
        IERC20 token = IERC20(tokenAddress);

        uint256 lockedUpAmount = 0;
        for (uint256 i = 0; i < exchanges.length; i++) {
            lockedUpAmount += token.allowance(shareAddress, exchanges[i]);
        }
        return lockedUpAmount;
    }

    function getAvailableAmount(address shareAddress, address tokenAddress) public view override returns (uint256) {
        IERC20 token = IERC20(tokenAddress);
        return token.balanceOf(shareAddress) - getLockedUpAmount(shareAddress, tokenAddress);
    }

    function getTreasuryShareCount(address shareAddress) public view override returns (uint256) { //return the number of shares held by the company
        return IERC20(shareAddress).balanceOf(shareAddress) - getLockedUpAmount(shareAddress, shareAddress);
    }

    function getOutstandingShareCount(address shareAddress) public view override returns (uint256) { //return the number of shares not held by the company
        IERC20 share = IERC20(shareAddress);
        return share.totalSupply() - share.balanceOf(shareAddress);
    }

    //getMaxOutstandingShareCount() >= getOutstandingShareCount(), we are also counting the shares that have been locked up in exchanges and may be sold
    function getMaxOutstandingShareCount(address shareAddress) external view override returns (uint256) {
        IERC20 share = IERC20(shareAddress);
        return share.totalSupply() - getTreasuryShareCount(shareAddress);
    }



    function registerApprovedExchange(address tokenAddress, address exchange) external override returns (uint256) {
        mapping(address => uint256) storage approvedExchangeIndex = approvedExchangeIndexByToken[msg.sender][tokenAddress];
        uint256 index = approvedExchangeIndex[exchange];
        if (index == 0) { //the exchange has not been registered yet OR was the first registered exchange
            address[] storage approvedExchanges = approvedExchangesByToken[msg.sender][tokenAddress];
            if ((approvedExchanges.length == 0) || (approvedExchanges[0] != exchange)) { //the exchange has not been registered yet
                index = approvedExchanges.length;
                approvedExchangeIndex[exchange] = index;
                approvedExchanges.push(exchange);
            }
        }
        return index;
    }

    function packApprovedExchanges(address tokenAddress) external override {
        mapping(address => uint256) storage approvedExchangeIndex = approvedExchangeIndexByToken[msg.sender][tokenAddress];
        address[] memory old = approvedExchangesByToken[msg.sender][tokenAddress]; //dynamic memory arrays do not exist, only dynamic storage arrays, so copy the original values to memory and then modify storage
        approvedExchangesByToken[msg.sender][tokenAddress] = new address[](0); //empty the new storage again, do not use the delete keyword, because this has an unbounded gas cost
        address[] storage approvedExchanges = approvedExchangesByToken[msg.sender][tokenAddress];
        uint256 packedIndex = 0;
        IERC20 token = IERC20(tokenAddress);

        for (uint256 i = 0; i < old.length; i++) {
            address exchange = old[i];
            if (token.allowance(msg.sender, exchange) > 0) {
                approvedExchangeIndex[exchange] = packedIndex;
                approvedExchanges.push(exchange);
                packedIndex++;
            } else {
                approvedExchangeIndex[exchange] = 0;
            }
        }
    }
}
