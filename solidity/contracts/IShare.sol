// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import 'contracts/libraries/Voting.sol';

enum ActionType {
    DEFAULT, CHANGE_OWNER, CHANGE_DECISION_PARAMETERS, ISSUE_SHARES, DESTROY_SHARES, WITHDRAW_FUNDS, CHANGE_EXCHANGE, ASK, BID, CANCEL_ORDER, REVERSE_SPLIT, DISTRIBUTE_DIVIDEND, DISTRIBUTE_OPTIONAL_DIVIDEND, EXTERNAL
}

error RequestPending();
error NoRequestPending();
error RequestNotResolved();
error CannotFinish();

struct CorporateActionData {
    uint256 numberOfShares;
    address currency;
    uint256 amount;
    address optionalCurrency;
    uint256 optionalAmount;
}

interface IShare {
    //external proposals
    event RequestExternalProposal(uint256 indexed id);
    event ExternalProposal(uint256 indexed id, VoteResult indexed voteResult);

    //who manages the smart contract
    event RequestChangeOwner(uint256 indexed id, address indexed newOwner);
    event ChangeOwner(uint256 indexed id, VoteResult indexed voteResult, address indexed newOwner);

    //actions changing how decisions are made
    event RequestChangeDecisionParameters(uint256 indexed id, uint16 indexed voteType, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator);
    event ChangeDecisionParameters(uint256 indexed id, VoteResult indexed voteResult, uint16 indexed voteType, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator);

    /*corporate actions
      the meaning of the event parameters depend on the decisionType and are as follows:
    
      for ISSUE_SHARES and DESTROY_SHARES:
      numberOfShares: the number of shares to be issued or destroyed
      currency: not applicable
      amount: not applicable
      optionalCurrency: not applicable
      optionalAmount: not applicable

      for WITHDRAW_FUNDS:
      numberOfShares: the maximum amount of outstanding shares.  Some shares may still be in treasury but locked up by exchanges, because exchanges may sell them through a pending ask order.
      currency: the currency that needs to be transferred
      amount: the amount of currency that needs to be transferred
      optionalCurrency: the account the funds have to be transferred to
      optionalAmount: not applicable

      for CHANGE_EXCHANGE:
      numberOfShares: the maximum amount of outstanding shares.  Some shares may still be in treasury but locked up by exchanges, because exchanges may sell them through a pending ask order.
      currency: the old exchange address
      amount: not applicable
      optionalCurrency: the new exchange address
      optionalAmount: not applicable

      for ASK and BID:
      numberOfShares: the maximum amount of orders executed on the exchange
      currency: the asset that is sold or bought (could be the own stock)
      amount: the amount of the asset to be sold or bought
      optionalCurrency: the currency in which the asset is sold or bought
      optionalAmount: for ASK, the minimum price to receive for selling an asset, for BID, the maximum price for buying an asset

      for CANCEL_ORDER:
      numberOfShares: the maximum amount of outstanding shares.  Some shares may still be in treasury but locked up by exchanges, because exchanges may sell them through a pending ask order.
      currency: not applicable
      amount: the id of the order that needs to be canceled
      optionalCurrency: not applicable
      optionalAmount: not applicable

      for REVERSE_SPLIT:
      numberOfShares: the maximum amount of outstanding shares.  Some shares may still be in treasury but locked up by exchanges, because exchanges may sell them through a pending ask order.
      currency: the currency for which 1 fractional share that cannot be reverse split will be compensated
      amount: the amount for which 1 fractional share that cannot be reverse split will be compensated
      optionalCurrency: not applicable
      optionalAmount: the reverse split ratio, optionalAmount shares will become 1 share

      for DISTRIBUTE_DIVIDEND and DISTRIBUTE_OPTIONAL_DIVIDEND
      numberOfShares: the maximum amount of outstanding shares.  Some shares may still be in treasury but locked up by exchanges, because exchanges may sell them through a pending ask order.
      currency: the currency to be distributed
      amount: the amount of the currency to be distributed
      optionalCurrency: only applicable when an optional dividend is distributed, the optional currency to be distributed
      optionalAmount: only applicable when an optional dividend is distributed, the amount of the optional currency to be distributed

      in case of an optional dividend, first a DISTRIBUTE_DIVIDEND corporate action is initiated and if approved, a DISTRIBUTE_OPTIONAL_DIVIDEND corporate action is initiated where shareholders can decide to opt for the optional dividend instead of the regular dividend
    */
    event RequestCorporateAction(uint256 indexed id, ActionType indexed decisionType, uint256 numberOfShares, address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount);
    event CorporateAction(uint256 indexed id, VoteResult indexed voteResult, ActionType indexed decisionType, uint256 numberOfShares, address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount);

    function getLockedUpAmount(address tokenAddress) external view returns (uint256);
    function getOutstandingShareCount() external view returns (uint256);
    function getMaxOutstandingShareCount() external view returns (uint256);

    function getShareholderCount() external view returns (uint256);
    function getShareholderNumber(address shareholder) external returns (uint256);
    function getShareholderPackSize() external view returns (uint256);
    function packShareholders(uint256 amountToPack) external;

    function getTradedTokenCount() external view returns (uint256);
    function getTradedTokenNumber(address tokenAddress) external returns (uint256);
    function getTradedTokenPackSize() external view returns (uint256);
    function packTradedTokens(uint256 amountToPack) external;

    function getNumberOfProposals() external view returns (uint256);
    function getDecisionParameters(uint256 id) external view returns (uint16, uint64, uint64, uint32, uint32, uint32, uint32);
    function getDecisionTimes(uint256 id) external view returns (uint64, uint64, uint64);
    function getNumberOfVotes(uint256 id) external view returns (uint256);
    function getDetailedVoteResult(uint256 id) external view returns (VoteResult, uint32, uint32, uint32, uint32, uint256, uint256, uint256, uint256);
    function getVoteResult(uint256 id) external view returns (VoteResult);

    function getProposedOwner(uint256 id) external view returns (address);
    function getProposedDecisionParameters(uint256 id) external view returns (uint16, uint64, uint64, uint32, uint32, uint32, uint32);
    function getProposedCorporateAction(uint256 id) external view returns (ActionType, uint256, address, uint256, address, uint256);

    function makeExternalProposal() external returns (uint256);
    function makeExternalProposal(uint16 subType) external returns (uint256);

    function changeOwner(address newOwner) external returns (uint256);

    function getDecisionParameters(ActionType voteType) external returns (uint64, uint64, uint32, uint32, uint32, uint32);
    function getExternalProposalDecisionParameters(uint16 subType) external returns (uint64, uint64, uint32, uint32, uint32, uint32);
    function changeDecisionParameters(ActionType voteType, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) external returns (uint256);
    function changeExternalProposalDecisionParameters(uint16 subType, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) external returns (uint256);

    function issueShares(uint256 numberOfShares) external returns (uint256);
    function destroyShares(uint256 numberOfShares) external returns (uint256);
    function withdrawFunds(address destination, address currency, uint256 amount) external returns (uint256);
    function changeExchange(address newExchangeAddress) external returns (uint256);
    function ask(address asset, uint256 assetAmount, address currency, uint256 price, uint256 maxOrders) external returns (uint256);
    function bid(address asset, uint256 assetAmount, address currency, uint256 price, uint256 maxOrders) external returns (uint256);
    function cancelOrder(uint256 orderId) external returns (uint256);

    function startReverseSplit(uint256 reverseSplitToOne, address currency, uint256 amount) external returns (uint256);
    function startDistributeDividend(address currency, uint256 amount) external returns (uint256);
    function startDistributeOptionalDividend(address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount) external returns (uint256);
    function finish() external;
    function finish(uint256 pageSize) external returns (uint256);

    function resolveVote() external;
    function resolveVote(uint256 pageSize) external returns (uint256);
    function withdrawVote() external;

    function vote(uint256 id, VoteChoice decision) external;
}