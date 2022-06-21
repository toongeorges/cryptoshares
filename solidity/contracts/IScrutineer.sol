// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

enum VoteChoice {
    NO_VOTE, IN_FAVOR, AGAINST, ABSTAIN
}

enum VoteResult {
    NON_EXISTENT, PENDING, APPROVED, REJECTED, EXPIRED, WITHDRAWN, NO_OUTSTANDING_SHARES
}

struct Vote {
    address voter;
    VoteChoice choice;
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

error CannotVote(); //either voting has ended or the vote does not exist

interface IScrutineer {
    event ChangeDecisionParameters(address indexed owner, uint256 indexed voteType, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator);
    event VoteOpened(address indexed owner, uint256 indexed id, address indexed decisionToken, uint256 voteType, uint256 lastVoteDate, uint256 lastResolutionDate);
    event VoteResolved(address indexed owner, uint256 indexed id, VoteResult indexed result);

    function getDecisionParameters() external returns (uint64, uint64, uint32, uint32, uint32, uint32);
    function getDecisionParameters(uint256 voteType) external returns (uint64, uint64, uint32, uint32, uint32, uint32);
    function setDecisionParameters(uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) external;
    function setDecisionParameters(uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator, uint256 voteType) external;

    function getNumberOfProposals(address owner) external view returns (uint256);
    function getDecisionToken(address owner, uint256 id) external view returns (address); //the reference implementation assumes that the address is an IERC20 token, but the interface does not need to require this
    function getDecisionTimes(address owner, uint256 id) external view returns (uint64, uint64, uint64);
    function getDetailedVoteResult(address owner, uint256 id) external view returns (VoteResult, uint32, uint32, uint32, uint32, uint256, uint256, uint256, uint256);
    function getVoteResult(address owner, uint256 id) external view returns (VoteResult);

    function getNumberOfVotes(uint256 id) external view returns (uint256);
    function getVotes(uint256 id) external view returns (Vote[] memory);
    function getVotes(uint256 id, uint256 start, uint256 length) external view returns (Vote[] memory);

    function propose(address decisionToken) external returns (uint256, bool);
    function propose(address decisionToken, uint256 voteType) external returns (uint256, bool);
    function vote(address owner, uint256 id, VoteChoice decision) external;
    function resolveVote(uint256 id) external returns (bool);
    function withdrawVote(uint256 id) external returns (bool);
}