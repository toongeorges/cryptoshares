// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import 'contracts/IShare.sol';
import 'contracts/libraries/Voting.sol';
import 'contracts/IExchange.sol';

abstract contract Proposals is IShare, ERC20 {
    address public owner;

    mapping(uint16 => DecisionParameters) internal decisionParameters;
    uint256 public pendingRequestId;
    VoteParameters[] private proposals;

    IExchange public exchange;

    modifier isOwner() {
        _isOwner(); //putting the code in a fuction reduces the size of the compiled smart contract!
        _;
    }

    function _isOwner() internal view {
        require(msg.sender == owner);
    }

    constructor() {
        proposals.push(); //make sure that the pendingRequestId for any request > 0
    }



    function getLockedUpAmount(address tokenAddress) public view virtual override returns (uint256) {
        return exchange.getLockedUpAmount(tokenAddress);
    }

    //getOutstandingShareCount() <= getMaxOutstandingShareCount(), the shares that have been locked up in an exchange do not belong to anyone yet
    function getOutstandingShareCount() public view virtual override returns (uint256) { //return the number of shares held by shareholders
        return totalSupply() - balanceOf(address(this)) - getLockedUpAmount(address(this));
    }

    function getMaxOutstandingShareCount() public view virtual override returns (uint256) {
        return totalSupply() - balanceOf(address(this));
    }



    function getDecisionParameters(ActionType voteType) external view virtual override returns (bool, uint64, uint64, uint32, uint32, uint32, uint32) {
        return doGetDecisionParametersReturnValues(uint16(voteType));
    }

    function getExternalProposalDecisionParameters(uint16 subType) external view virtual override returns (bool, uint64, uint64, uint32, uint32, uint32, uint32) {
        return doGetDecisionParametersReturnValues(uint16(ActionType.EXTERNAL) + subType);
    }

    function doGetDecisionParametersReturnValues(uint16 voteType) internal view returns (bool, uint64, uint64, uint32, uint32, uint32, uint32) {
        (bool isDefault, DecisionParameters storage dP) = doGetDecisionParameters(voteType);
        return (isDefault, dP.decisionTime, dP.executionTime, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator);
    }



    function getNumberOfProposals() external view virtual override returns (uint256) {
        return proposals.length - 1;
    }

    function getProposalDecisionParameters(uint256 id) external view virtual override returns (uint16, uint64, uint64, uint32, uint32, uint32, uint32) {
        return Voting.getDecisionParameters(getProposal(id));
    }

    function getProposalDecisionTimes(uint256 id) external view virtual override returns (uint64, uint64, uint64) {
        return Voting.getDecisionTimes(getProposal(id));
    }

    function getNumberOfVotes(uint256 id) public view virtual override returns (uint256) {
        return Voting.getNumberOfVotes(getProposal(id));
    }

    function getDetailedVoteResult(uint256 id) external view virtual override returns (VoteResult, uint256, uint256, uint256, uint256) {
        VoteParameters storage vP = getProposal(id);
        VoteResult result = Voting.getVoteResult(vP);
        return ((result == VoteResult.EXPIRED) || (result == VoteResult.PARTIAL_VOTE_COUNT))
             ? (result, 0, 0, 0, 0)
             : (result, vP.inFavor, vP.against, vP.abstain, vP.noVote);
    }

    function getVoteResult(uint256 id) external view virtual override returns (VoteResult) {
        return Voting.getVoteResult(getProposal(id));
    }

    function getVoteChoice(uint256 id) external view virtual override returns (VoteChoice) {
        return Voting.getVoteChoice(getProposal(id));
    }

    function getVoteType(uint256 id) internal view returns (uint16) {
        return proposals[id].voteType;
    }

    function getNextProposalId() internal view returns (uint256) {
        return proposals.length;
    }
    
    function getProposal(uint256 id) internal view returns (VoteParameters storage) { //reduces the size of the compiled contract when this is wrapped in a function
        return proposals[id];
    }



    function propose(uint16 voteType, function(uint256, VoteResult) internal returns (bool) execute, function(uint256) internal request) internal isOwner returns (uint256) {
        if (pendingRequestId == 0) {
            uint256 id = proposals.length;

            bool isNoOutstandingShares = (getOutstandingShareCount() == 0);
            
            (, DecisionParameters storage dP) = doGetDecisionParameters(voteType);
            Voting.init(proposals.push(), voteType, dP, isNoOutstandingShares);

            if (isNoOutstandingShares) {
                execute(id, proposals[id].result);
            } else {
                pendingRequestId = id;

                request(id);
            }

            return id;
        } else {
            revert RequestPending();
        }
    }

    function doGetDecisionParameters(uint16 voteType) internal view returns (bool, DecisionParameters storage) {
        DecisionParameters storage dP = decisionParameters[voteType];

        bool isDefault = (dP.quorumDenominator == 0);

        return (isDefault) //check if the decisionParameters have been set
             ? (isDefault, decisionParameters[0]) //decisionParameters have not been initialized, fall back to default decisionParameters
             : (isDefault, dP);
    }

    function isApproved(VoteResult voteResult) internal pure returns (bool) {
        return ((voteResult == VoteResult.APPROVED) || (voteResult == VoteResult.NO_OUTSTANDING_SHARES));
    }



    function vote(uint256 id, VoteChoice decision) external virtual override {
        Voting.vote(getProposal(id), decision, (balanceOf(msg.sender) > 0));
    }
}