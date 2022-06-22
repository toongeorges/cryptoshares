// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

enum ActionType {
    DEFAULT, EXTERNAL, CHANGE_OWNER, CHANGE_DECISION_PARAMETERS, WITHDRAW_FUNDS, ISSUE_SHARES, DESTROY_SHARES, RAISE_FUNDS, BUY_BACK, CANCEL_ORDER, REVERSE_SPLIT, DISTRIBUTE_DIVIDEND, DISTRIBUTE_OPTIONAL_DIVIDEND
}

enum VoteChoice {
    NO_VOTE, IN_FAVOR, AGAINST, ABSTAIN
}

enum VoteResult {
    NON_EXISTENT, PENDING, PARTIAL, APPROVED, REJECTED, EXPIRED, WITHDRAWN, NO_OUTSTANDING_SHARES
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
error NoExternalProposal();
error RequestPending();
error NoRequestPending();
error RequestNotResolved();
error CannotVote();

interface IShare {
    //external proposals
    event RequestExternalProposal(uint256 indexed id);
    event ExternalProposal(uint256 indexed id, VoteResult indexed voteResult);

    //who manages the smart contract
    event RequestChangeOwner(uint256 indexed id, address indexed newOwner);
    event ChangeOwner(uint256 indexed id, VoteResult indexed voteResult, address indexed newOwner);

    //actions changing how decisions are made
    event RequestChangeDecisionParameters(uint256 indexed id, ActionType indexed voteType, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator);
    event ChangeDecisionParameters(uint256 indexed id, VoteResult indexed voteResult, ActionType indexed voteType, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator);

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

    function getNumberOfProposals() external view returns (uint256);
    function getDecisionParameters(uint256 id) external view returns (uint64, uint64, uint32, uint32, uint32, uint32);
    function getDecisionTimes(uint256 id) external view returns (uint64, uint64, uint64);
    function getDetailedVoteResult(uint256 id) external view returns (VoteResult, uint32, uint32, uint32, uint32, uint256, uint256, uint256, uint256);
    function getVoteResult(uint256 id) external view returns (VoteResult);

    function isExternalProposal(uint256 id) external view returns (bool);
    function getProposedOwner(uint256 id) external view returns (address);
    function getProposedDecisionParameters(uint256 id) external view returns (ActionType, uint64, uint64, uint32, uint32, uint32, uint32);
    function getProposedCorporateAction(uint256 id) external view returns (ActionType, uint256, address, address, uint256, address, uint256);

    function makeExternalProposal() external returns (uint256);
    function resolveExternalProposal(uint256 id) external;
    function withdrawExternalProposal(uint256 id) external;

    function changeOwner(address newOwner) external;
    function resolveChangeOwnerVote() external;
    function withdrawChangeOwnerVote() external;

    function getDecisionParameters(ActionType voteType) external returns (uint64, uint64, uint32, uint32, uint32, uint32);
    function changeDecisionParameters(ActionType voteType, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) external;
    function resolveChangeDecisionParametersVote() external;
    function withdrawChangeDecisionParametersVote() external;

    function vote(uint256 id, VoteChoice decision) external;
}