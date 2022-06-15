// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface IShareInfo {
    //getters that anyone can check for any shareAddress
    function getLockedUpAmount(address shareAddress, address tokenAddress) external view returns (uint256);
    function getAvailableAmount(address shareAddress, address tokenAddress) external view returns (uint256);
    function getTreasuryShareCount(address shareAddress) external view returns (uint256);
    function getOutstandingShareCount(address shareAddress) external view returns (uint256);
    function getMaxOutstandingShareCount(address shareAddress) external view returns (uint256);

    //these methods implicitly assume that the shareAddress == msg.sender, so they can only (meaningfully) be executed by a share smart contract
    function registerApprovedExchange(address tokenAddress, address exchange) external returns (uint256);
    function packApprovedExchanges(address tokenAddress) external;
}
