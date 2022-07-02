// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

enum VoteChoice {
    NO_VOTE, IN_FAVOR, AGAINST, ABSTAIN
}

enum VoteResult {
    NON_EXISTENT, PENDING, PARTIAL_VOTE_COUNT, PARTIAL_EXECUTION, APPROVED, REJECTED, EXPIRED, WITHDRAWN, NO_OUTSTANDING_SHARES
}

enum VotingStage {
    VOTING_IN_PROGRESS, VOTING_HAS_ENDED, EXECUTION_HAS_ENDED
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

struct Vote {
    address voter;
    VoteChoice choice;
}

struct VoteParameters {
    //pack these 3 variables together
    uint64 startTime;
    uint16 voteType;
    VoteResult result;

    DecisionParameters decisionParameters; //store this on creation, so it cannot be changed afterwards

    mapping(address => uint256) voteIndex;
    mapping(address => uint256) spentVotes;
    uint256 countedVotes;
    Vote[] votes;

    uint256 inFavor;
    uint256 against;
    uint256 abstain;
    uint256 noVote;

    mapping(address => uint256) processedShares;
    uint256 processedShareholders;
}

error CannotVote();

library Voting {
    function init(VoteParameters storage vP, uint16 voteType, DecisionParameters storage dP, bool isNoOutstandingShares) internal {
        vP.startTime = uint64(block.timestamp); // 500 000 000 000 years is more than enough, save some storage space
        vP.voteType = voteType;
        vP.decisionParameters = dP; //copy by value
        vP.countedVotes = 1; //the first vote is from this address(this) with VoteChoice.NO_VOTE, ignore this vote
        vP.votes.push(Vote(address(this), VoteChoice.NO_VOTE)); //this reduces checks on index == 0 to be made in the vote method, to save gas for the vote method
        vP.result = isNoOutstandingShares ? VoteResult.NO_OUTSTANDING_SHARES : VoteResult.PENDING;
    }

    function getDecisionParameters(VoteParameters storage vP) internal view returns (uint16, uint64, uint64, uint32, uint32, uint32, uint32) {
        DecisionParameters storage dP = vP.decisionParameters;
        return (vP.voteType, dP.decisionTime, dP.executionTime, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator);
    }

    function getDecisionTimes(VoteParameters storage vP) internal view returns (uint64, uint64, uint64) {
        DecisionParameters storage dP = vP.decisionParameters;

        uint64 startTime = vP.startTime;
        uint64 decisionTime = startTime + dP.decisionTime;
        uint64 executionTime = decisionTime + dP.executionTime;

        return (startTime, decisionTime, executionTime);
    }

    function getNumberOfVotes(VoteParameters storage vP) internal view returns (uint256) {
        unchecked {
            return (vP.votes.length - 1); //the vote at index 0 is from address(this) with VoteChoice.NO_VOTE and is ignored.  The init method must have been called before this method can be called!
        }
    }

    function getVoteResult(VoteParameters storage vP) internal view returns (VoteResult) {
        VoteResult result = vP.result;
        return (result != VoteResult.PENDING) ? result
             : (getVotingStage(vP) == VotingStage.EXECUTION_HAS_ENDED) ? VoteResult.EXPIRED
             : result;
    }

    function transferVotes(VoteParameters storage vP, address from, address to, uint256 transferAmount) internal {
        mapping(address => uint256) storage spentVotes = vP.spentVotes;
        uint256 senderSpent = spentVotes[from];
        uint256 receiverSpent = spentVotes[to];
        uint256 transferredSpentVotes = (senderSpent > transferAmount) ? transferAmount : senderSpent;
        if (transferredSpentVotes > 0) {
            unchecked {
                receiverSpent += transferredSpentVotes;
                spentVotes[from] = senderSpent - transferredSpentVotes;
            }
        }
        uint256 voteIndex = vP.voteIndex[to];
        if ((voteIndex > 0) && (voteIndex < vP.countedVotes)) { //if the votes of the receiver have already been counted
            unchecked {
                uint256 transferredUnspentVotes = transferAmount - transferredSpentVotes;
                if (transferredUnspentVotes > 0) { 
                    VoteChoice choice = vP.votes[voteIndex].choice;
                    if (choice == VoteChoice.IN_FAVOR) {
                        vP.inFavor += transferredUnspentVotes;
                    } else if (choice == VoteChoice.AGAINST) {
                        vP.against += transferredUnspentVotes;
                    } else if (choice == VoteChoice.ABSTAIN) {
                        vP.abstain += transferredUnspentVotes;
                    } else { //no votes do not count towards the quorum
                        vP.noVote += transferredUnspentVotes;
                    }
                    receiverSpent += transferredUnspentVotes;
                }
            }
        }
        spentVotes[to] = receiverSpent;
    }

    function vote(VoteParameters storage vP, VoteChoice decision, bool canVote) internal {
        if (canVote && (vP.result == VoteResult.PENDING) && (getVotingStage(vP) == VotingStage.VOTING_IN_PROGRESS)) { //vP.result could be e.g. WITHDRAWN while the voting stage is still pending
            mapping(address => uint256) storage voteIndex = vP.voteIndex;
            Vote[] storage votes = vP.votes;
            uint256 index = voteIndex[msg.sender];
            uint256 numberOfVotes = votes.length;
            if (index == 0) { //if the voter has not voted before, the first voter is address(this), this vote will be ignored
                voteIndex[msg.sender] = numberOfVotes;
                votes.push(Vote(msg.sender, decision));
            } else { //shareHolders can vote as much as they want, but only their last vote counts (if they still hold shares at the moment the votes are counted).
                votes[index] = Vote(msg.sender, decision);
            }
        } else {
            revert CannotVote();
        }
    }

    function getVotingStage(VoteParameters storage voteParameters) internal view returns (VotingStage) {
        DecisionParameters storage dP = voteParameters.decisionParameters;
        uint256 votingCutOff = voteParameters.startTime + dP.decisionTime;
        return (block.timestamp <= votingCutOff) ?                    VotingStage.VOTING_IN_PROGRESS
             : (block.timestamp <= votingCutOff + dP.executionTime) ? VotingStage.VOTING_HAS_ENDED
             :                                                        VotingStage.EXECUTION_HAS_ENDED;
    }

    function withdrawVote(VoteParameters storage vP) internal returns (bool) {
        if (vP.result == VoteResult.PENDING) { //can only withdraw if the result is still pending
            VotingStage votingStage = getVotingStage(vP);
            VoteResult result = (votingStage == VotingStage.EXECUTION_HAS_ENDED)
                   ? VoteResult.EXPIRED //cannot withdraw anymore
                   : VoteResult.WITHDRAWN;

            vP.result = result;
            return true; //the vote has been withdrawn/expired
        } else {
            return false; //the vote cannot be withdrawn anymore
        }
    }

    function resolveVote(VoteParameters storage vP, bool isAlwaysApproved, bool isPartialExecution, IERC20 share, uint256 outstandingShareCount, uint256 pageSize) internal returns (bool, uint256) {
        if (isAlwaysApproved) { //if this was not a vote to make a decision, but a vote to show a preference, e.g. for choosing an optional dividend
            vP.result = getApprovedResult(isPartialExecution);

            return (true, 0);
        } else {
            uint256 remainingVotes = 0;
            VoteResult result = vP.result;
            if (result == VoteResult.PARTIAL_VOTE_COUNT) {
                (remainingVotes, result) = countAndVerifyVotes(vP, isPartialExecution, share, outstandingShareCount, pageSize);

                if (remainingVotes == 0) {
                    vP.result = result;
                }

                return (true, remainingVotes); //the result field itself has not been updated if remainingVotes > 0, but votes have been counted
            } else if (result == VoteResult.PENDING) { //the result was already known before, we do not need to take action a second time, covers also the result NON_EXISTENT
                VotingStage votingStage = getVotingStage(vP);
                if (votingStage == VotingStage.EXECUTION_HAS_ENDED) {
                    result = VoteResult.EXPIRED;
                } else {
                    if (outstandingShareCount == 0) { //if somehow all shares have been bought back, then approve
                        result = getApprovedResult(isPartialExecution);
                    } else if (votingStage == VotingStage.VOTING_IN_PROGRESS) { //do nothing, wait for voting to end
                        return (false, 0);
                    } else { //votingStage == VotingStage.VOTING_HAS_ENDED
                        (remainingVotes, result) = countAndVerifyVotes(vP, isPartialExecution, share, outstandingShareCount, pageSize);
                    }
                }

                vP.result = result;

                return (true, remainingVotes); //the vote result has been updated
            }

            return (false, 0); //the vote result has not been updated
        }
    }

    function countAndVerifyVotes(VoteParameters storage vP, bool isPartialExecution, IERC20 share, uint256 outstandingShareCount, uint256 pageSize) private returns (uint256, VoteResult) {
        uint256 remainingVotes = countVotes(vP, share, pageSize);

        if (remainingVotes == 0) {
            DecisionParameters storage dP = vP.decisionParameters;
            return (remainingVotes, verifyVotes(dP, isPartialExecution, outstandingShareCount, vP.inFavor, vP.against, vP.abstain)); //either REJECTED or PARTIAL_EXECUTION/APPROVED
        } else {
            return (remainingVotes, VoteResult.PARTIAL_VOTE_COUNT);
        }
    }
    
    function countVotes(VoteParameters storage voteParameters, IERC20 share, uint256 pageSize) private returns (uint256) {
        uint256 inFavor = voteParameters.inFavor;
        uint256 against = voteParameters.against;
        uint256 abstain = voteParameters.abstain;
        uint256 noVote = voteParameters.noVote;

        Vote[] storage votes = voteParameters.votes;
        uint256 start = voteParameters.countedVotes;
        uint256 end = start + pageSize;
        uint256 maxEnd = votes.length;
        if (end > maxEnd) {
            end = maxEnd;
        }

        mapping(address => uint256) storage spentVotes = voteParameters.spentVotes;
        for (uint256 i = start; i < end;) {
            Vote storage v = votes[i];
            address voter = v.voter;
            uint256 totalVotingPower = share.balanceOf(voter);
            unchecked {
                uint256 votingPower = totalVotingPower - spentVotes[voter]; //prevent "double spending" of votes
                if (votingPower > 0) { //do not consider votes of shareholders who sold their shares or who bought shares from others who already voted
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
                    spentVotes[voter] = totalVotingPower;
                }
                i++;
            }
        }

        voteParameters.countedVotes = end;

        voteParameters.inFavor = inFavor;
        voteParameters.against = against;
        voteParameters.abstain = abstain;
        voteParameters.noVote = noVote;

        unchecked {
            return maxEnd - end;
        }
    }

    function verifyVotes(DecisionParameters storage dP, bool isPartialExecution, uint256 outstandingShareCount, uint256 inFavor, uint256 against, uint256 abstain) private view returns (VoteResult) {
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

        return getApprovedResult(isPartialExecution);
    }

    function getApprovedResult(bool isPartialExecution) private pure returns (VoteResult) {
        return isPartialExecution ? VoteResult.PARTIAL_EXECUTION : VoteResult.APPROVED;
    }

    //presentNumerator/presentDenominator >= quorumNumerator/quorumDenominator <=> presentNumerator*quorumDenominator >= quorumNumerator*presentDenominator
    function isQuorumMet(uint32 quorumNumerator, uint32 quorumDenominator, uint256 presentNumerator, uint256 presentDenominator) private pure returns (bool) { //compare 2 fractions without causing overflow
        if (quorumNumerator == 0) { //save on gas
            return true;
        } else {
            unchecked {
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
}