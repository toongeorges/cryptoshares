// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import 'contracts/IScrutineer.sol';

enum VotingStage {
    VOTING_IN_PROGRESS, VOTING_HAS_ENDED, EXECUTION_HAS_ENDED
}

struct Vote {
    address voter;
    VoteChoice choice;
}

struct VoteParameters {
    //pack these 3 variables together
    uint64 startTime;
    address decisionToken;
    VoteResult result;

    DecisionParameters decisionParameters; //store this on creation, so it cannot be changed afterwards

    mapping(address => uint256) lastVote; //shareHolders can vote as much as they want, but only their last vote counts (if they still hold shares at the moment the votes are counted).
    Vote[] votes;

    uint256 inFavor;
    uint256 against;
    uint256 abstain;
    uint256 noVote;
}

contract Scrutineer is IScrutineer {
    mapping(address => mapping(uint256 => DecisionParameters)) decisionParameters;
    mapping(address => VoteParameters[]) proposals;



    receive() external payable { //used to receive wei when msg.data is empty
        revert("This is a free service"); //as long as Ether is not ERC20 compliant
    }

    fallback() external payable { //used to receive wei when msg.data is not empty
        revert("This is a free service"); //as long as Ether is not ERC20 compliant
    }



    function getDecisionParameters() external override returns (uint64, uint64, uint32, uint32, uint32, uint32) {
        DecisionParameters storage dP = doGetDefaultDecisionParameters();
        return (dP.decisionTime, dP.executionTime, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator);
    }

    function getDecisionParameters(uint256 voteType) external override returns (uint64, uint64, uint32, uint32, uint32, uint32) {
        DecisionParameters storage dP = doGetDecisionParameters(voteType);
        return (dP.decisionTime, dP.executionTime, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator);
    }

    function setDecisionParameters(uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) external override {
        setDecisionParameters(decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator, 0);
    }

    function setDecisionParameters(uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator, uint256 voteType) public override {
        require(quorumDenominator > 0);
        require(majorityDenominator > 0);
        require((majorityNumerator << 1) >= majorityDenominator);

        DecisionParameters storage dP = decisionParameters[msg.sender][voteType];
        dP.decisionTime = decisionTime;
        dP.executionTime = executionTime;
        dP.quorumNumerator = quorumNumerator;
        dP.quorumDenominator = quorumDenominator;
        dP.majorityNumerator = majorityNumerator;
        dP.majorityDenominator = majorityDenominator;

        emit ChangeDecisionParameters(msg.sender, voteType, decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
    }



    function getNumberOfProposals(address owner) external view override returns (uint256) {
        return proposals[owner].length;     
    }
    
    function getDecisionToken(address owner, uint256 id) external view override returns (address) {
        return proposals[owner][id].decisionToken;
    }

    function getDecisionTimes(address owner, uint256 id) external view override returns (uint64, uint64, uint64) {
        VoteParameters storage vP = proposals[owner][id];
        DecisionParameters storage dP = vP.decisionParameters;

        uint64 startTime = vP.startTime;
        uint64 decisionTime = startTime + dP.decisionTime;
        uint64 executionTime = decisionTime + dP.executionTime;

        return (startTime, decisionTime, executionTime);
    }

    function getDetailedVoteResult(address owner, uint256 id) external view override returns (VoteResult, uint32, uint32, uint32, uint32, uint256, uint256, uint256, uint256) {
        VoteParameters storage vP = proposals[owner][id];
        DecisionParameters storage dP = vP.decisionParameters;
        VoteResult result = vP.result;
        if ((result == VoteResult.PENDING) && (getVotingStage(vP) == VotingStage.EXECUTION_HAS_ENDED)) {
            return (VoteResult.EXPIRED, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator, 0, 0, 0, 0);
        } else {
            return (result, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator, vP.inFavor, vP.against, vP.abstain, vP.noVote);
        }
    }

    function getVoteResult(address owner, uint256 id) external view override returns (VoteResult) {
        VoteParameters storage vP = proposals[owner][id];
        VoteResult result = vP.result;
        if ((result == VoteResult.PENDING) && (getVotingStage(vP) == VotingStage.EXECUTION_HAS_ENDED)) {
            return VoteResult.EXPIRED;
        } else {
            return result;
        }
    }



    function propose(address decisionToken) external override returns (uint256, bool) {
        return propose(decisionToken, 0);
    }

    function propose(address decisionToken, uint256 voteType) public override returns (uint256, bool) {
        verifyERC20(decisionToken);
        DecisionParameters storage dP = doGetDecisionParameters(voteType);
        VoteParameters[] storage vPList = proposals[msg.sender];
        uint256 index = vPList.length;
        VoteParameters storage vP = vPList.push();
        vP.startTime = uint64(block.timestamp); // 500 000 000 000 years is more than enough, save some storage space
        vP.decisionToken = decisionToken;
        vP.decisionParameters = dP; //copy by value

        emit VoteOpened(msg.sender, index, decisionToken, block.timestamp + dP.decisionTime);

        if (getOutstandingShareCount(decisionToken) == 0) { //auto approve if there are no shares outstanding
            vP.result = VoteResult.NO_OUTSTANDING_SHARES; 

            emit VoteResolved(msg.sender, index, VoteResult.NO_OUTSTANDING_SHARES);

            return (index, true);
        } else {
            vP.result = VoteResult.PENDING; 

            return (index, false);
        }
    }

    function vote(address owner, uint256 id, VoteChoice decision) external override {
        VoteParameters storage vP = proposals[owner][id];
        if ((vP.result == VoteResult.PENDING) && (getVotingStage(vP) == VotingStage.VOTING_IN_PROGRESS)) { //vP.result could be e.g. WITHDRAWN while the voting stage is still in progress
            address voter = msg.sender;
            if (IERC20(vP.decisionToken).balanceOf(voter) > 0) { //The amount of shares of the voter is checked later, so it does not matter if the voter still sells all his shares before the vote resolution.  This check just prevents people with no shares from increasing the votes array.
                uint256 numberOfVotes = vP.votes.length;
                vP.lastVote[voter] = numberOfVotes;
                vP.votes.push(Vote(voter, decision));
            }
        } else {
            revert("Cannot vote anymore");
        }
    }

    function resolveVote(uint256 id) external override returns (bool) { //The owner of the vote needs to resolve it so he can take appropriate action if needed
        VoteParameters storage vP = proposals[msg.sender][id];
        VoteResult result = vP.result;
        if (result == VoteResult.PENDING) { //the result was already known before, we do not need to take action a second time, covers also the result NON_EXISTENT
            VotingStage votingStage = getVotingStage(vP);
            if (votingStage == VotingStage.EXECUTION_HAS_ENDED) {
                result = VoteResult.EXPIRED;
            } else { //the decisionToken is verified to be an ERC20 token only if the contract is already on the blockchain during the propose() call
                     //if the propose() call is made from the constructor of a smart contract, the vote is opened without verifying if the smart contract is an ERC20 token
                     //in this case, voting is not possible and calling the getOutstandingShareCount() method will revert the transaction
                     //we need to allow the vote to be resolved through letting it expire and calling the getOutstandingShareCount() method can only happen after
                uint256 outstandingShareCount = getOutstandingShareCount(vP.decisionToken);
                if (outstandingShareCount == 0) { //if somehow all shares have been bought back, then approve
                    result = VoteResult.APPROVED;
                } else if (votingStage == VotingStage.VOTING_IN_PROGRESS) { //do nothing, wait for voting to end
                    return false;
                } else { //votingStage == VotingStage.VOTING_HAS_ENDED
                    (vP.inFavor, vP.against, vP.abstain, vP.noVote) = countVotes(vP);

                    DecisionParameters storage dP = vP.decisionParameters;
                    result = verifyVotes(dP, outstandingShareCount, vP.inFavor, vP.against, vP.abstain); //either REJECTED or APPROVED
                }
            }

            vP.result = result;

            emit VoteResolved(msg.sender, id, result);

            return true; //the vote result has been updated
        }

        return false; //the vote result has not been updated
    }

    function withdrawVote(uint256 id) external override returns (bool) {
        VoteParameters storage vP = proposals[msg.sender][id];
        if (vP.result == VoteResult.PENDING) { //can only withdraw if the result is still pending
            VotingStage votingStage = getVotingStage(vP);
            VoteResult result = (votingStage == VotingStage.EXECUTION_HAS_ENDED)
                   ? VoteResult.EXPIRED //cannot withdraw anymore
                   : VoteResult.WITHDRAWN;

            vP.result = result;
            emit VoteResolved(msg.sender, id, result);
            return true; //the vote has been withdrawn/expired
        } else {
            return false; //the vote cannot be withdrawn anymore
        }
    }



    function getOutstandingShareCount(address decisionToken) internal view returns (uint256) { //return the number of shares not held by the company
        if (decisionToken.code.length == 0) { //if this is called from within the constructor of an ERC20 token, the ERC20 contract is not available on the blockchain yet and we will not be able to cast to IERC20(decisionToken)
            return 0;
        } else {
            IERC20 token = IERC20(decisionToken);
            return token.totalSupply() - token.balanceOf(decisionToken); //return the issued share count minus the treasury share count
        }
    }

    function doGetDecisionParameters(uint256 voteType) internal returns (DecisionParameters storage) {
        if (voteType == 0) {
            return doGetDefaultDecisionParameters();
        } else {
            DecisionParameters storage dP = decisionParameters[msg.sender][voteType];
            return (dP.quorumDenominator == 0)
                 ? doGetDefaultDecisionParameters() //decisionParameters have not been initialized, fall back to default decisionParameters
                 : dP;
        }
    }

    function doGetDefaultDecisionParameters() internal returns (DecisionParameters storage) {
        DecisionParameters storage dP = decisionParameters[msg.sender][0];
        if (dP.quorumDenominator == 0) { //default decisionParameters have not been initialized, initialize with sensible values
            dP.decisionTime = 2592000; //30 days
            dP.executionTime = 604800; //7 days
            dP.quorumNumerator = 0;
            dP.quorumDenominator = 1;
            dP.majorityNumerator = 1;
            dP.majorityDenominator = 2;

            emit ChangeDecisionParameters(msg.sender, 0, 2592000, 604800, 0, 1, 1, 2);
        }
        return dP;
    }

    function getVotingStage(VoteParameters storage voteParameters) internal view returns (VotingStage) {
        DecisionParameters storage dP = voteParameters.decisionParameters;
        uint256 votingCutOff = voteParameters.startTime + dP.decisionTime;
        return (block.timestamp <= votingCutOff) ?                    VotingStage.VOTING_IN_PROGRESS
             : (block.timestamp <= votingCutOff + dP.executionTime) ? VotingStage.VOTING_HAS_ENDED
             :                                                        VotingStage.EXECUTION_HAS_ENDED;
    }

    function verifyERC20(address decisionToken) internal view {
        if (decisionToken.code.length > 0) { //if this is called from within the constructor of an ERC20 token, the ERC20 contract is not available on the blockchain yet and we will not be able to cast to IERC20(decisionToken)
            IERC20(decisionToken).totalSupply();
        }
    }
    
    function resolve(VoteParameters storage vP) internal returns (VoteResult) {
        VoteResult result = vP.result;
        if (result == VoteResult.PENDING) { //the result was already known before, we do not need to take action a second time, covers also the result NON_EXISTENT
            VotingStage votingStage = getVotingStage(vP);
            if (votingStage == VotingStage.VOTING_IN_PROGRESS) {
                if (getOutstandingShareCount(vP.decisionToken) == 0) { //if somehow all shares have been bought back, then approve
                    result = VoteResult.APPROVED;
                }
            } else if (votingStage == VotingStage.EXECUTION_HAS_ENDED) {
                result = VoteResult.EXPIRED;
            } else { //votingStage == VotingStage.VOTING_HAS_ENDED
                uint256 inFavor;
                uint256 against;
                uint256 abstain;

                (inFavor, against, abstain, vP.noVote) = countVotes(vP);

                vP.inFavor = inFavor;
                vP.against = against;
                vP.abstain = abstain;

                DecisionParameters storage dP = vP.decisionParameters;
                result = verifyVotes(dP, getOutstandingShareCount(vP.decisionToken), inFavor, against, abstain); //either REJECTED or APPROVED
            }
        }

        if (result != VoteResult.PENDING) { //result has been updated
            vP.result = result;
        }
        return result;
    }

    function countVotes(VoteParameters storage voteParameters) internal view returns (uint256, uint256, uint256, uint256) {
        IERC20 token = IERC20(voteParameters.decisionToken);

        uint256 inFavor = 0;
        uint256 against = 0;
        uint256 abstain = 0;
        uint256 noVote = 0;

        mapping(address => uint256) storage lastVote = voteParameters.lastVote;
        Vote[] storage votes = voteParameters.votes;
        for (uint256 i = 0; i < votes.length; i++) {
            Vote storage v = votes[i];
            if (lastVote[v.voter] == i) { //a shareholder may vote as many times as he wants, but only consider his last vote
                uint256 votingPower = token.balanceOf(v.voter);
                if (votingPower > 0) { //do not consider votes of shareholders who sold their shares
                    VoteChoice choice = v.choice;
                    if (choice == VoteChoice.IN_FAVOR) {
                        inFavor += votingPower;
                    } else if (choice == VoteChoice.AGAINST) {
                        against += votingPower;
                    } else if (choice == VoteChoice.ABSTAIN) {
                        abstain += votingPower;
                    } else { //no votes do not count towards the quorum
                        noVote += votingPower;
                    }
                }
            }
        }

        return (inFavor, against, abstain, noVote);
    }

    function verifyVotes(DecisionParameters storage dP, uint256 outstandingShareCount, uint256 inFavor, uint256 against, uint256 abstain) internal view returns (VoteResult) {
        //first verify simple majority (the easiest calculation)
        if (against >= inFavor) {
            return VoteResult.REJECTED;
        }

        //then verify if the quorum is met
        if (!isQuorumMet(dP.quorumNumerator, dP.quorumDenominator, inFavor + against + abstain, outstandingShareCount)) {
            return VoteResult.REJECTED;
        }

        //then verify if the required majority has been reached
        if (!isQuorumMet(dP.majorityNumerator, dP.majorityDenominator, inFavor, inFavor + against)) {
            return VoteResult.REJECTED;
        }

        return VoteResult.APPROVED;
    }

    //presentNumerator/presentDenominator >= quorumNumerator/quorumDenominator <=> presentNumerator*quorumDenominator >= quorumNumerator*presentDenominator
    function isQuorumMet(uint32 quorumNumerator, uint32 quorumDenominator, uint256 presentNumerator, uint256 presentDenominator) internal pure returns (bool) { //compare 2 fractions without causing overflow
        if (quorumNumerator == 0) { //save on gas
            return true;
        } else {
            //check first high
            uint256 present = (presentNumerator >> 32)*quorumDenominator;
            uint256 quorum = (quorumNumerator >> 32)*presentDenominator;

            if (present > quorum) {
                return true;
            } else if (present < quorum) {
                return false;
            }

            //then check low
            present = uint32(presentNumerator)*quorumDenominator;
            quorum = uint32(quorumNumerator)*presentDenominator;
            return (present >= quorum);
        }
    }
}