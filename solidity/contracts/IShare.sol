// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import 'contracts/IScrutineer.sol';

enum CorporateActionType {
    ISSUE_SHARES, DESTROY_SHARES, RAISE_FUNDS, BUY_BACK, CANCEL_ORDER, REVERSE_SPLIT, DISTRIBUTE_DIVIDEND, DISTRIBUTE_OPTIONAL_DIVIDEND, WITHDRAW_FUNDS
}

interface IShare {
    //who manages the smart contract
    event RequestNewOwner(uint256 indexed id, address indexed newOwner);
    event NewOwner(uint256 indexed id, address indexed newOwner, VoteResult indexed voteResult);

    //actions changing how decisions are made
    event RequestDecisionParametersChange(uint256 indexed id, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator);
    event DecisionParametersChange(uint256 indexed id, VoteResult indexed voteResult, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator);

    /*corporate actions
      the meaning of the event parameters depend on the decisionType and are as follows:
    
      for ISSUE_SHARES and DESTROY_SHARES:
      numberOfShares: the number of shares to be issued or destroyed
      exchange: not applicable
      currency: not applicable
      amount: not applicable
      optionalCurrency: not applicable
      optionalAmount: not applicable
    
      for RAISE_FUNDS and BUY_BACK:
      numberOfShares: the number of shares to be sold or bought back
      exchange: the exchange on which the ask or bid order will be placed
      currency: the ERC20 token the share will be traded against
      amount: the amount of ERC20 tokens for 1 share
      optionalCurrency: not applicable
      optionalAmount: not applicable

      for CANCEL_ORDER:
      numberOfShares: the maximum amount of outstanding shares.  Some shares may still be in treasury but locked up by exchanges, because exchanges may sell them through a pending ask order.
      exchange: the exchange on which the ask or bid order needs to be canceled
      currency: not applicable
      amount: the id of the order that needs to be canceled
      optionalCurrency: not applicable
      optionalAmount: not applicable

      for REVERSE_SPLIT:
      numberOfShares: the maximum amount of outstanding shares.  Some shares may still be in treasury but locked up by exchanges, because exchanges may sell them through a pending ask order.
      exchange: not applicable
      currency: the currency for which 1 fractional share that cannot be reverse split will be compensated
      amount: the amount for which 1 fractional share that cannot be reverse split will be compensated
      optionalCurrency: not applicable
      optionalAmount: the reverse split ratio, optionalAmount shares will become 1 share

      for DISTRIBUTE_DIVIDEND and DISTRIBUTE_OPTIONAL_DIVIDEND
      numberOfShares: the maximum amount of outstanding shares.  Some shares may still be in treasury but locked up by exchanges, because exchanges may sell them through a pending ask order.
      exchange: not applicable
      currency: the currency to be distributed
      amount: the amount of the currency to be distributed
      optionalCurrency: only applicable when an optional dividend is distributed, the optional currency to be distributed
      optionalAmount: only applicable when an optional dividend is distributed, the amount of the optional currency to be distributed

      in case of an optional dividend, first a DISTRIBUTE_DIVIDEND corporate action is taken and if approved, a DISTRIBUTE_OPTIONAL_DIVIDEND corporate action is taken where shareholders can decide to opt for the optional dividend

      for WITHDRAW_FUNDS:
      numberOfShares: the maximum amount of outstanding shares.  Some shares may still be in treasury but locked up by exchanges, because exchanges may sell them through a pending ask order.
      exchange: the account the funds have to be transferred to
      currency: the currency that needs to be transferred
      amount: the amount of currency that needs to be transferred
      optionalCurrency: not applicable
      optionalAmount: not applicable
    */
    event RequestCorporateAction(uint256 indexed id, CorporateActionType indexed decisionType, uint256 numberOfShares, address exchange, address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount);
    event CorporateAction(uint256 indexed id, CorporateActionType indexed decisionType, VoteResult indexed voteResult, uint256 numberOfShares, address exchange, address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount);

    function registerShareholder(address shareholder) external returns (uint256);
    function getProposedOwner(uint256 id) external view returns (address);
    function getProposedDecisionParameters(uint256 id) external view returns (uint64, uint64, uint32, uint32, uint32, uint32);
    function getProposedCorporateAction(uint256 id) external view returns (CorporateActionType, uint256, address, address, uint256, address, uint256);

    function changeOwner(address newOwner) external;
    function changeOwnerOnApproval() external;
    function withdrawChangeOwnerRequest() external;

    function changeDecisionParameters(uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) external;
    function changeDecisionParametersOnApproval() external;
    function withdrawChangeDecisionParametersRequest() external;

    function issueShares(uint256 numberOfShares) external;
    function destroyShares(uint256 numberOfShares) external;
    function raiseFunds(uint256 numberOfShares, address exchangeAddress, address currency, uint256 price) external;
    function buyBack(uint256 numberOfShares, address exchangeAddress, address currency, uint256 price) external;
    function cancelOrder(address exchangeAddress, uint256 orderId) external;
    function reverseSplit(address currency, uint256 amount, uint256 reverseSplitToOne) external;
    function distributeDividend(address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount) external;
    function withdrawFunds(address destination, address currency, uint256 amount) external;
    function corporateActionOnApproval() external;
    function withdrawCorporateActionRequest() external;
}