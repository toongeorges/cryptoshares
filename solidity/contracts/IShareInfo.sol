// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface IShareInfo {
    function getLockedUpAmount(address shareAddress, address tokenAddress) external view returns (uint256);
    function getAvailableAmount(address shareAddress, address tokenAddress) external view returns (uint256);
    function getTreasuryShareCount(address shareAddress) external view returns (uint256);
    function getOutstandingShareCount(address shareAddress) external view returns (uint256);
    function getShareholderCount(address shareAddress) external view returns (uint256);
    function getShareholders() external view returns (address[] memory);

    function registerShareholder(address shareholder) external returns (uint256);
    function packShareholders() external;
    function registerApprovedExchange(address tokenAddress, address exchange) external returns (uint256);
    function packApprovedExchanges(address tokenAddress) external;
}
