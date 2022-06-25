// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

enum ActionType {
    DEFAULT, CHANGE_OWNER, CHANGE_DECISION_PARAMETERS, ISSUE_SHARES, DESTROY_SHARES, RAISE_FUNDS, BUY_BACK, SWAP, CANCEL_ORDER, WITHDRAW_FUNDS, REVERSE_SPLIT, DISTRIBUTE_DIVIDEND, DISTRIBUTE_OPTIONAL_DIVIDEND, EXTERNAL
}

enum VoteChoice {
    NO_VOTE, IN_FAVOR, AGAINST, ABSTAIN
}

enum VoteResult {
    NON_EXISTENT, PENDING, PARTIAL_VOTE_COUNT, PARTIAL_EXECUTION, APPROVED, REJECTED, EXPIRED, WITHDRAWN, NO_OUTSTANDING_SHARES
}

struct DecisionParameters {
    uint64 decisionTime; //How much time in seconds shareholders have to approve a request
    uint64 executionTime; //How much time in seconds the owner has to execute an approved request after the decisionTime has ended
    //to approve a vote, both the quorum and the majority need to be reached.
    //a vote is approved if and only if the quorum and the majority are reached on the decisionTime, otherwise it is rejected
    uint32 quorumNumerator;     //the required quorum is calculated as quorumNumerator/quorumDenominator
    uint32 quorumDenominator;   //the required quorum is compared to the number of votes that are in favor, against or abstain divided by the total number of votes
    uint32 majorityNumerator;   //the required majority is calculated as majorityNumerator/majorityDenominator and must be greater than 1/2
    uint32 majorityDenominator; //the required majority is compared to the number of votes that are in favor divided by the number of votes that are either in favor or against
}

error DoNotAcceptEtherPayments();
error RequestPending();
error NoRequestPending();
error RequestNotResolved();
error CannotVote();
error CannotExecuteAtOnce();
error CannotFinish();

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
      optionalAmount: the maximum amount of orders executed on the exchange, 0 if no maximum.

      for SWAP:
      numberOfShares: the amount of swaps
      exchange: the exchange on which the swap order will be placed
      currency: the ERC20 token A that is offered for a swap
      amount: the amount of the ERC20 token A that is offered for a swap
      optionalCurrency: the ERC20 token B that is requested for a swap
      optionalAmount: the minimum amount of the ERC20 token B that is requested for a swap

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
    event RequestCorporateAction(uint256 indexed id, ActionType indexed decisionType, uint256 numberOfShares, address exchange, address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount);
    event CorporateAction(uint256 indexed id, VoteResult indexed voteResult, ActionType indexed decisionType, uint256 numberOfShares, address exchange, address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount);

    function getLockedUpAmount(address tokenAddress) external view returns (uint256);
    function getAvailableAmount(address tokenAddress) external view returns (uint256);
    function getTreasuryShareCount() external view returns (uint256);
    function getOutstandingShareCount() external view returns (uint256);
    function getMaxOutstandingShareCount() external view returns (uint256);

    function getExchangeCount(address tokenAddress) external view returns (uint256);
    function getExchangePackSize(address tokenAddress) external view returns (uint256);
    function packExchanges(address tokenAddress, uint256 amountToPack) external;
    function getShareholderCount() external view returns (uint256);
    function getShareholderNumber(address shareholder) external returns (uint256);
    function getShareholderPackSize() external view returns (uint256);
    function packShareholders(uint256 amountToPack) external;

    function getNumberOfProposals() external view returns (uint256);
    function getDecisionParameters(uint256 id) external view returns (uint16, uint64, uint64, uint32, uint32, uint32, uint32);
    function getDecisionTimes(uint256 id) external view returns (uint64, uint64, uint64);
    function getNumberOfVotes(uint256 id) external view returns (uint256);
    function getDetailedVoteResult(uint256 id) external view returns (VoteResult, uint32, uint32, uint32, uint32, uint256, uint256, uint256, uint256);
    function getVoteResult(uint256 id) external view returns (VoteResult);

    function getProposedOwner(uint256 id) external view returns (address);
    function getProposedDecisionParameters(uint256 id) external view returns (uint16, uint64, uint64, uint32, uint32, uint32, uint32);
    function getProposedCorporateAction(uint256 id) external view returns (ActionType, uint256, address, address, uint256, address, uint256);

    function makeExternalProposal() external returns (uint256);
    function makeExternalProposal(uint16 subType) external returns (uint256);

    function changeOwner(address newOwner) external returns (uint256);

    function getDecisionParameters(ActionType voteType) external returns (uint64, uint64, uint32, uint32, uint32, uint32);
    function getExternalProposalDecisionParameters(uint16 subType) external returns (uint64, uint64, uint32, uint32, uint32, uint32);
    function changeDecisionParameters(ActionType voteType, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) external returns (uint256);
    function changeExternalProposalDecisionParameters(uint16 subType, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) external returns (uint256);

    function issueShares(uint256 numberOfShares) external returns (uint256);
    function destroyShares(uint256 numberOfShares) external returns (uint256);
    function raiseFunds(address exchangeAddress, uint256 numberOfShares, address currency, uint256 price, uint256 maxOrders) external returns (uint256);
    function buyBack(address exchangeAddress, uint256 numberOfShares, address currency, uint256 price, uint256 maxOrders) external returns (uint256);
    function swap(address exchangeAddress, address offer, uint256 offerRatio, address request, uint256 requestRatio, uint256 amountOfSwaps) external returns (uint256);
    function cancelOrder(address exchangeAddress, uint256 orderId) external returns (uint256);
    function withdrawFunds(address destination, address currency, uint256 amount) external returns (uint256);

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