// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

enum VoteType {
    NO_VOTE, IN_FAVOR, AGAINST, ABSTAIN
}

enum VotingStage {
    VOTING_IN_PROGRESS, VOTING_HAS_ENDED, EXECUTION_HAS_ENDED
}

enum VoteResult {
    NON_EXISTENT, PENDING, APPROVED, REJECTED, EXPIRED, WITHDRAWN, NO_OUTSTANDING_SHARES
}

enum ActionType {
    NEW_OWNER, DECISION, CORPORATE, EXTERNAL
}

enum DecisionActionType {
    CHANGE_DECISION_TIME, CHANGE_QUORUM, CHANGE_MAJORITY, CHANGE_ALL
}

enum CorporateActionType {
    ISSUE_SHARES, DESTROY_SHARES, RAISE_FUNDS, BUY_BACK, DISTRIBUTE_DIVIDEND
}

struct DecisionParameters {
    uint64 decisionTime; //How much time in seconds shareholders have to approve a request for a corporate action
    uint64 executionTime; //How much time in seconds the owner has to execute an approved request after the decisionTime has ended
    //to approve a vote both the quorum = quorumNumerator/quorumDenominator and the required majority = majorityNumerator/majorityDenominator are calculated
    //a vote is approved if and only if the quorum and the majority are reached on the decisionTime, otherwise it is rejected
    //the majority also always needs to be greater than 1/2
    uint32 quorumNumerator;
    uint32 quorumDenominator;
    uint32 majorityNumerator;
    uint32 majorityDenominator;
}

struct Vote {
    address voter;
    VoteType choice;
}

struct VoteParameters {
    uint128 startTime;
    VoteResult result; //pack together with startTime

    DecisionParameters decisionParameters; //store this on creation, so it cannot be changed afterwards

    mapping(address => uint256) lastVote; //shareHolders can vote as much as they want, but only their last vote counts (if they still hold shares at the moment the votes are counted).
    Vote[] votes;

    uint256 inFavor;
    uint256 against;
    uint256 abstain;
    uint256 noVote;
}

struct NewOwnerData {
    VoteParameters voteParameters;

    address newOwner;
}

struct DecisionParametersData {
    VoteParameters voteParameters;

    DecisionActionType actionType;
    DecisionParameters proposedParameters;
}

struct CorporateActionData {
    VoteParameters voteParameters;

    CorporateActionType actionType;
    address exchange; //only relevant for RAISE_FUNDS and BUY_BACK, pack together with actionType
    uint256 numberOfShares; //the number of shares created or destroyed for ISSUE_SHARES or DESTROY_SHARES, the number of shares to sell or buy back for RAISE_FUNDS and BUY_BACK and the number of shares receiving dividend for DISTRIBUTE_DIVIDEND
    address currency; //ERC20 token
    uint256 amount; //empty for ISSUE_SHARES and DESTROY_SHARES, the ask or bid price for a single share for RAISE_FUNDS and BUY_BACK, the amount of dividend to be distributed per share for DISTRIBUTE_DIVIDEND
    address optionalCurrency; //ERC20 token
    uint256 optionalAmount; //only relevant in the case of an optional dividend for DISTRIBUTE_DIVIDEND, shareholders can opt for the optional dividend instead of the default dividend
}

contract Scrutineer {
    event RequestNewOwner(uint256 indexed id, address indexed newOwner);
    event RequestDecisionParametersChange(uint256 indexed id, DecisionActionType indexed actionType);
    event RequestCorporateAction(uint256 indexed id, CorporateActionType indexed actionType);

    mapping(uint256 => NewOwnerData) private newOwnerData;
    mapping(uint256 => DecisionParametersData) private decisionParametersData;
    mapping(uint256 => CorporateActionData) private corporateActionData;
    mapping(uint256 => VoteParameters) private externalProposalData;

    address public owner;

    DecisionParameters public decisionParameters;

    modifier isOwner() {
        require(msg.sender == owner);
        _;
    }

    modifier proceedOnRequest(VoteParameters storage vP) {
        if (vP.result != VoteResult.PENDING) {
            initVoteParameters(vP);
            _;
        } else {
            revert("cannot initiate a new request while an old request is still pending");
        }
    }

    constructor() {
        owner = msg.sender;

        //set sensible default values
        doSetDecisionParameters(decisionParameters, 2592000, 604800, 0, 1, 1, 2); //30 and 7 days
    }

    receive() external payable { //used to receive wei when msg.data is empty
        revert("This is a free service");
    }

    fallback() external payable { //used to receive wei when msg.data is not empty
        revert("This is a free service");
    }



    function getFinalDecisionTime(ActionType actionType, uint256 id) external view returns (uint256) {
        VoteParameters storage vP = getVoteParameters(actionType, id);
        DecisionParameters storage dP = vP.decisionParameters;
        return vP.startTime + dP.decisionTime;
    }

    function getFinalExecutionTime(ActionType actionType, uint256 id) external view returns (uint256) {
        VoteParameters storage vP = getVoteParameters(actionType, id);
        DecisionParameters storage dP = vP.decisionParameters;
        return vP.startTime + dP.decisionTime + dP.executionTime;
    }

    function getVoteResult(ActionType actionType, uint256 id) external view returns (VoteResult, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256) {
        VoteParameters storage vP = getVoteParameters(actionType, id);
        DecisionParameters storage dP = vP.decisionParameters;
        VoteResult result = vP.result;
        if ((result == VoteResult.PENDING) && (getVotingStage(vP) == VotingStage.EXECUTION_HAS_ENDED)) {
            return (VoteResult.EXPIRED, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator, 0, 0, 0, 0);
        } else {
            return (result, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator, vP.inFavor, vP.against, vP.abstain, vP.noVote);
        }
    }

    function getProposedOwner(uint256 id) external view returns (address) {
        return newOwnerData[id].newOwner;
    }

    function getProposedDecisionParameters(uint256 id) external view returns (DecisionParameters memory) {
        return decisionParametersData[id].proposedParameters;
    }

    function getProposedCorporateAction(uint256 id) external view returns (CorporateActionType, address, uint256, address, uint256, address, uint256) {
        CorporateActionData storage actionData = corporateActionData[id];
        return (actionData.actionType, actionData.exchange, actionData.numberOfShares, actionData.currency, actionData.amount, actionData.optionalCurrency, actionData.optionalAmount);
    }



    function vote(ActionType actionType, uint256 id, VoteType decision) external {
        VoteParameters storage vP = getVoteParameters(actionType, id);
        if ((vP.result == VoteResult.PENDING) && (getVotingStage(vP) == VotingStage.VOTING_IN_PROGRESS)) { //vP.result could be e.g. WITHDRAWN while the voting stage is still in progress
            address voter = msg.sender;
            if (IERC20(owner).balanceOf(voter) > 0) { //The amount of shares of the voter is checked later, so it does not matter if the voter still sells all his shares before the vote resolution.  This check just prevents people with no shares from increasing the votes array.
                uint256 numberOfVotes = vP.votes.length;
                vP.lastVote[voter] = numberOfVotes;
                vP.votes[numberOfVotes] = Vote(voter, decision);
            }
        } else {
            revert("Cannot vote anymore");
        }
    }

    function setDecisionTime(uint64 decisionTime, uint64 executionTime) external isOwner {
        doSetDecisionParameters(decisionParameters, decisionTime, executionTime, decisionParameters.quorumNumerator, decisionParameters.quorumDenominator, decisionParameters.majorityNumerator, decisionParameters.majorityDenominator);
    }

    function setQuorum(uint32 quorumNumerator, uint32 quorumDenominator) external isOwner {
        doSetDecisionParameters(decisionParameters, decisionParameters.decisionTime, decisionParameters.executionTime, quorumNumerator, quorumDenominator, decisionParameters.majorityNumerator, decisionParameters.majorityDenominator);
    }

    function setMajority(uint32 majorityNumerator, uint32 majorityDenominator) external isOwner {
        doSetDecisionParameters(decisionParameters, decisionParameters.decisionTime, decisionParameters.executionTime, decisionParameters.quorumNumerator, decisionParameters.quorumDenominator, majorityNumerator, majorityDenominator);
    }

    function setDecisionParameters(uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) external isOwner {
        doSetDecisionParameters(decisionParameters, decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
    }



    function requestChangeOwner(uint256 newOwnerId, address newOwner) external isOwner {
        doRequestChangeOwner(newOwnerId, newOwnerData[newOwnerId], newOwner);
    }

    function doRequestChangeOwner(uint256 newOwnerId, NewOwnerData storage data, address newOwner) internal proceedOnRequest(data.voteParameters) {
        data.newOwner = newOwner;

        emit RequestNewOwner(newOwnerId, owner);
    }

    function getNewOwnerResults(uint256 id, bool changesRequireApproval, uint256 outstandingShareCount) external isOwner returns (bool, VoteResult, address) {
        NewOwnerData storage data = newOwnerData[id];

        bool isEmitEvent;
        VoteResult result;

        (isEmitEvent, result) = isCountVotes(data.voteParameters, changesRequireApproval, outstandingShareCount);

        return (isEmitEvent, result, data.newOwner);
    }

    function withdrawChangeOwner(uint256 id) external isOwner returns (bool, VoteResult, address) {
        NewOwnerData storage data = newOwnerData[id];

        bool isWithdrawn;
        VoteResult result;

        (isWithdrawn, result) = withdraw(data.voteParameters);

        return (isWithdrawn, result, data.newOwner);
    }

    function requestChangeDecisionParameters(uint256 decisionParametersId, DecisionActionType actionType, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) external isOwner {
        doRequestChangeDecisionParameters(decisionParametersId, decisionParametersData[decisionParametersId], actionType, decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
    }

    function doRequestChangeDecisionParameters(uint256 decisionParametersId, DecisionParametersData storage data, DecisionActionType actionType, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) internal proceedOnRequest(data.voteParameters) {
        data.actionType = actionType;
        DecisionParameters storage proposedParameters = data.proposedParameters;
        doSetDecisionParameters(proposedParameters, decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);

        emit RequestDecisionParametersChange(decisionParametersId, actionType);
    }

    function getDecisionParametersResults(uint256 id, bool changesRequireApproval, uint256 outstandingShareCount) external isOwner returns (bool, VoteResult, DecisionActionType, uint64, uint64, uint32, uint32, uint32, uint32) {
        DecisionParametersData storage data = decisionParametersData[id];
        DecisionParameters storage pP = data.proposedParameters;

        bool isEmitEvent;
        VoteResult result;

        (isEmitEvent, result) = isCountVotes(data.voteParameters, changesRequireApproval, outstandingShareCount);

        return (isEmitEvent, result, data.actionType, pP.decisionTime, pP.executionTime, pP.quorumNumerator, pP.quorumDenominator, pP.majorityNumerator, pP.majorityDenominator);
    }

    function withdrawChangeDecisionParameters(uint256 id) external isOwner returns (bool, VoteResult, DecisionActionType) {
        DecisionParametersData storage data = decisionParametersData[id];

        bool isWithdrawn;
        VoteResult result;

        (isWithdrawn, result) = withdraw(data.voteParameters);

        return (isWithdrawn, result, data.actionType);
    }

    function requestCorporateAction(uint256 corporateActionId, CorporateActionType actionType, uint256 numberOfShares, address exchange, address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount) external isOwner {
        doRequestCorporateAction(corporateActionId, corporateActionData[corporateActionId], actionType, numberOfShares, exchange, currency, amount, optionalCurrency, optionalAmount);
    }

    function doRequestCorporateAction(uint256 corporateActionId, CorporateActionData storage data, CorporateActionType actionType, uint256 numberOfShares, address exchange, address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount) internal proceedOnRequest(data.voteParameters) {
        data.actionType = actionType;
        data.numberOfShares = numberOfShares;
        if (exchange != address(0)) { //only store the exchange address if this is relevant
            data.exchange = exchange;
        }
        if (currency != address(0)) { //only store currency info if this is relevant
            data.currency = currency;
            data.amount = amount;
        }
        if (optionalCurrency != address(0)) { //only store optionalCurrency info if this is relevant
            data.optionalCurrency = optionalCurrency;
            data.optionalAmount = optionalAmount;
        }

        emit RequestCorporateAction(corporateActionId, actionType);
    }



    function doSetDecisionParameters(DecisionParameters storage dP, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) internal {
        require(quorumDenominator > 0);
        require(majorityDenominator > 0);
        require((majorityNumerator << 1) >= majorityDenominator);

        dP.decisionTime = decisionTime;
        dP.executionTime = executionTime;

        dP.quorumNumerator = quorumNumerator;
        dP.quorumDenominator = quorumDenominator;

        dP.majorityNumerator = majorityNumerator;
        dP.majorityDenominator = majorityDenominator;
    }

    function getVoteParameters(ActionType actionType, uint256 id) internal view returns (VoteParameters storage) {
        if (actionType == ActionType.CORPORATE) {
            return corporateActionData[id].voteParameters;
        } else if (actionType == ActionType.DECISION) {
            return decisionParametersData[id].voteParameters;
        } else if (actionType == ActionType.NEW_OWNER) {
            return newOwnerData[id].voteParameters;
        } else if (actionType == ActionType.EXTERNAL) {
            return externalProposalData[id];
        } else {
            revert("unknown actionType");
        }
    }

    function initVoteParameters(VoteParameters storage voteParameters) internal {
        voteParameters.startTime = uint128(block.timestamp); // 10 000 000 000 000 000 000 000 000 000 000 years is more than enough, save some storage space
        voteParameters.result = VoteResult.PENDING;
        voteParameters.decisionParameters = decisionParameters; //copy by value
    }

    function getVotingStage(VoteParameters storage voteParameters) internal view returns (VotingStage) {
        uint256 votingCutOff = voteParameters.startTime + voteParameters.decisionParameters.decisionTime;
        return (block.timestamp <= votingCutOff) ?                                                   VotingStage.VOTING_IN_PROGRESS
             : (block.timestamp <= votingCutOff + voteParameters.decisionParameters.executionTime) ? VotingStage.VOTING_HAS_ENDED
             :                                                                                       VotingStage.EXECUTION_HAS_ENDED;
    }

    function isCountVotes(VoteParameters storage vP, bool changesRequireApproval, uint256 outstandingShareCount) internal returns (bool, VoteResult) {
        VoteResult result = vP.result;
        if (result == VoteResult.PENDING) {
            VotingStage votingStage = getVotingStage(vP);
            if (votingStage == VotingStage.VOTING_IN_PROGRESS) {
                if (!changesRequireApproval) { //if somehow all shares have been bought back, then approve
                    result = VoteResult.APPROVED;
                }
            } else if (votingStage == VotingStage.EXECUTION_HAS_ENDED) {
                result = VoteResult.EXPIRED;
            } else { //votingStage == VotingStage.VOTING_HAS_ENDED
                uint256 inFavor;
                uint256 against;
                uint256 abstain;
                uint256 noVote;

                (inFavor, against, abstain, noVote) = countVotes(vP);

                vP.inFavor = inFavor;
                vP.against = against;
                vP.abstain = abstain;
                vP.noVote = noVote;

                result = verifyVotes(vP, outstandingShareCount, inFavor, against, abstain); //either REJECTED or APPROVED
            }
            if (result != VoteResult.PENDING) { //if the votes have been counted
                vP.result = result;
                return (true, result);
            } else {
                return (false, result); //voting is still going on
            }
        } else { //the result was already known before, we do not need to take action a second time, covers also the result NON_EXISTENT
            return (false, result);
        }
    }

    function countVotes(VoteParameters storage voteParameters) internal view returns (uint256, uint256, uint256, uint256) {
        uint256 inFavor = 0;
        uint256 against = 0;
        uint256 abstain = 0;
        uint256 noVote = 0;

        IERC20 share = IERC20(owner);
        mapping(address => uint256) storage lastVote = voteParameters.lastVote;
        Vote[] storage votes = voteParameters.votes;
        for (uint256 i = 0; i < votes.length; i++) {
            Vote storage v = votes[i];
            if (lastVote[v.voter] == i) { //a shareholder may vote as many times as he wants, but only consider his last vote
                uint256 votingPower = share.balanceOf(v.voter);
                if (votingPower > 0) { //do not consider votes of shareholders who sold their shares
                    VoteType choice = v.choice;
                    if (choice == VoteType.IN_FAVOR) {
                        inFavor += votingPower;
                    } else if (choice == VoteType.AGAINST) {
                        against += votingPower;
                    } else if (choice == VoteType.ABSTAIN) {
                        abstain += votingPower;
                    } else { //no votes do not count towards the quorum
                        noVote += votingPower;
                    }
                }
            }
        }

        return (inFavor, against, abstain, noVote);
    }

    function verifyVotes(VoteParameters storage vP, uint256 outstandingShareCount, uint256 inFavor, uint256 against, uint256 abstain) internal view returns (VoteResult) {
        //first verify simple majority (the easiest calculation)
        if (against >= inFavor) {
            return VoteResult.REJECTED;
        }

        //then verify if the quorum is met
        if (!isQuorumMet(vP.decisionParameters.quorumNumerator, vP.decisionParameters.quorumDenominator, inFavor + against + abstain, outstandingShareCount)) {
            return VoteResult.REJECTED;
        }

        //then verify if the required majority has been reached
        if (!isQuorumMet(vP.decisionParameters.majorityNumerator, vP.decisionParameters.majorityDenominator, inFavor, inFavor + against)) {
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

    function withdraw(VoteParameters storage vP) internal returns (bool, VoteResult) {
        VoteResult result = vP.result;
        if (result == VoteResult.PENDING) { //can only withdraw if the result is still pending
            VotingStage votingStage = getVotingStage(vP);
            result = (votingStage == VotingStage.EXECUTION_HAS_ENDED)
                   ? VoteResult.EXPIRED //cannot withdraw anymore
                   : VoteResult.WITHDRAWN;
            vP.result = result;

            return (true, result);
        } else {
            return (false, result);
        }
    }
}