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
        owner = msg.sender;
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



    function getDecisionParameters(ActionType voteType) external virtual override returns (uint64, uint64, uint32, uint32, uint32, uint32) {
        return doGetDecisionParametersReturnValues(uint16(voteType));
    }

    function getExternalProposalDecisionParameters(uint16 subType) external virtual override returns (uint64, uint64, uint32, uint32, uint32, uint32) {
        return doGetDecisionParametersReturnValues(uint16(ActionType.EXTERNAL) + subType);
    }

    function doGetDecisionParametersReturnValues(uint16 voteType) internal returns (uint64, uint64, uint32, uint32, uint32, uint32) {
        DecisionParameters storage dP = doGetDecisionParameters(voteType);
        return (dP.decisionTime, dP.executionTime, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator);
    }



    function getNumberOfProposals() external view virtual returns (uint256) {
        return proposals.length - 1;
    }

    function getDecisionParameters(uint256 id) external view virtual override returns (uint16, uint64, uint64, uint32, uint32, uint32, uint32) {
        return Voting.getDecisionParameters(getProposal(id));
    }

    function getDecisionTimes(uint256 id) external view virtual override returns (uint64, uint64, uint64) {
        return Voting.getDecisionTimes(getProposal(id));
    }

    function getNumberOfVotes(uint256 id) public view virtual override returns (uint256) {
        return Voting.getNumberOfVotes(getProposal(id));
    }

    function getDetailedVoteResult(uint256 id) external view virtual override returns (VoteResult, uint32, uint32, uint32, uint32, uint256, uint256, uint256, uint256) {
        VoteParameters storage vP = getProposal(id);
        DecisionParameters storage dP = vP.decisionParameters;
        VoteResult result = Voting.getVoteResult(vP);
        return ((result == VoteResult.EXPIRED) || (result == VoteResult.PARTIAL_VOTE_COUNT))
             ? (result, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator, 0, 0, 0, 0)
             : (result, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator, vP.inFavor, vP.against, vP.abstain, vP.noVote);
    }

    function getVoteResult(uint256 id) external view virtual override returns (VoteResult) {
        return Voting.getVoteResult(getProposal(id));
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
            
            Voting.init(proposals.push(), voteType, doGetDecisionParameters(voteType), isNoOutstandingShares);

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

    function doGetDecisionParameters(uint16 voteType) internal returns (DecisionParameters storage) {
        if (voteType == 0) {
            return doGetDefaultDecisionParameters();
        } else {
            DecisionParameters storage dP = decisionParameters[voteType];
            return (dP.quorumDenominator == 0) //check if the decisionParameters have been set
                 ? doGetDefaultDecisionParameters() //decisionParameters have not been initialized, fall back to default decisionParameters
                 : dP;
        }
    }

    function doGetDefaultDecisionParameters() internal returns (DecisionParameters storage) {
        DecisionParameters storage dP = decisionParameters[0];
        if (dP.quorumDenominator == 0) { //default decisionParameters have not been initialized, initialize with sensible values
            dP.decisionTime = 2592000; //30 days
            dP.executionTime = 604800; //7 days
            dP.quorumNumerator = 0;
            dP.quorumDenominator = 1;
            dP.majorityNumerator = 1;
            dP.majorityDenominator = 2;

            emit ChangeDecisionParameters(proposals.length, VoteResult.NON_EXISTENT, 0, 2592000, 604800, 0, 1, 1, 2);
        }
        return dP;
    }

    function isApproved(VoteResult voteResult) internal pure returns (bool) {
        return ((voteResult == VoteResult.APPROVED) || (voteResult == VoteResult.NO_OUTSTANDING_SHARES));
    }



    function vote(uint256 id, VoteChoice decision) external virtual override {
        Voting.vote(getProposal(id), decision, (balanceOf(msg.sender) > 0));
    }
}