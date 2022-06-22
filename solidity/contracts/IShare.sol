// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

enum ActionType {
    EXTERNAL, CHANGE_OWNER, CHANGE_DECISION_PARAMETERS, WITHDRAW_FUNDS, ISSUE_SHARES, DESTROY_SHARES, RAISE_FUNDS, BUY_BACK, CANCEL_ORDER, REVERSE_SPLIT, DISTRIBUTE_DIVIDEND, DISTRIBUTE_OPTIONAL_DIVIDEND
}

error DoNotAcceptEtherPayments();

interface IShare {
    function getLockedUpAmount(address tokenAddress) external view returns (uint256);
    function getAvailableAmount(address tokenAddress) external view returns (uint256);
    function getTreasuryShareCount() external view returns (uint256);
    function getOutstandingShareCount() external view returns (uint256);
    function getMaxOutstandingShareCount() external view returns (uint256);

    function getExchangeCount(address tokenAddress) external view returns (uint256);
    function getExchangePackSize(address tokenAddress) external view returns (uint256);
    function packExchanges(address tokenAddress, uint256 amountToPack) external;
    function getShareholderCount() external view returns (uint256);
    function registerShareholder(address shareholder) external returns (uint256);
    function getShareholderPackSize() external view returns (uint256);
    function packShareholders(uint256 amountToPack) external;
}