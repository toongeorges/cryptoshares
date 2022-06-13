// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface IShareholderData {
    function getLockedUpAmount(address tokenAddress) external view returns (uint256);
    function getAvailableAmount(address tokenAddress) external view returns (uint256);
    function getTreasuryShareCount() external view returns (uint256);
    function getOutstandingShareCount() external view returns (uint256);
    function getShareholderCount() external view returns (uint256);
    function getShareholders() external view returns (address[] memory);

    function registerShareholder(address shareholder) external returns (uint256);
    function packShareholders() external;
    function registerApprovedExchange(address tokenAddress, address exchange) external returns (uint256);
    function packApprovedExchanges(address tokenAddress) external;
}
