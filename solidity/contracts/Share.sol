// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

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

enum VoteType {
    NO_VOTE, IN_FAVOR, AGAINST, ABSTAIN
}

struct Vote {
    address voter;
    VoteType choice;
}

enum VotingStage {
    VOTING_IN_PROGRESS, VOTING_HAS_ENDED, EXECUTION_HAS_ENDED
}

enum VoteResult {
    NON_EXISTENT, PENDING, APPROVED, REJECTED, EXPIRED, NO_SHARES_IN_CIRCULATION
}

struct VoteParameters {
    uint256 startTime;
    DecisionParameters decisionParameters; //store this on creation, so it cannot be changed afterwards

    mapping(address => uint256) lastVote; //shareHolders can vote as much as they want, but only their last vote counts (if they still hold shares at the moment the votes are counted).
    uint256 numberOfVotes;
    Vote[] votes;

    VoteResult result;
    uint256 noVote;
    uint256 inFavor;
    uint256 against;
    uint256 abstain;
}

enum ActionType {
    NEW_OWNER, DECISION, CORPORATE
}

struct NewOwnerActionData {
    VoteParameters voteParameters;
    address newOwner;
}

enum DecisionActionType {
    CHANGE_DECISION_TIME, CHANGE_QUORUM, CHANGE_MAJORITY
}

struct DecisionActionData {
    VoteParameters voteParameters;
    DecisionActionType decisionType;
    VoteParameters proposedParameters;
}

enum CorporateActionType {
    ISSUE_SHARES, DESTROY_SHARES, RAISE_FUNDS, BUY_BACK, DISTRIBUTE_DIVIDEND
}

struct CurrencyAmount {
    address currency; //ERC20 token
    uint256 amount;
}

struct CorporateActionData {
    VoteParameters voteParameters;
    CorporateActionType actionType;
    uint256 numberOfShares; //resulting number of shares if ISSUE_SHARES or DESTROY_SHARES approved, number of shares to sell or buy for RAISE_FUNDS and BUY_BACK and number of shares receiving dividend for DISTRIBUTE_DIVIDEND
    CurrencyAmount[] pricePerShare; //empty for ISSUE_SHARES and DESTROY_SHARES, a single value for RAISE_FUNDS and BUY_BACK, one or more values (in the case of an optional dividend) for DISTRIBUTE_DIVIDEND
}

contract Share is ERC20 {
    //who manages the smart contract
    event RequestNewOwner(uint256 indexed id, address indexed newOwner);
    event NewOwner(uint256 indexed id, address indexed newOwner, VoteResult indexed voteResult);

    //actions changing how decisions are made
    event RequestDecisionParameterChange(uint256 indexed id, DecisionActionType indexed actionType);
    event DecisionParameterChange(uint256 indexed id, DecisionActionType indexed actionType, VoteResult indexed voteResult);

    //corporate actions
    event RequestCorporateAction(uint256 indexed id, CorporateActionType indexed actionType);
    event CorporateAction(uint256 indexed id, CorporateActionType indexed actionType, VoteResult indexed voteResult);

    uint256 actionId;
    mapping(uint256 => NewOwnerActionData) newOwnerActions;
    mapping(uint256 => DecisionActionData) decisionActions;
    mapping(uint256 => CorporateActionData) corporateActions;
    
    address public owner;

    DecisionParameters public decisionParameters;

    uint256 public shareHolderCount;
    address[] private shareHolders; //we need to keep track of the shareholders in case of distributing a dividend

    modifier isOwner() {
        require(msg.sender == owner);
        _;
    }

    constructor(string memory name, string memory symbol, uint256 numberOfShares) ERC20(name, symbol) {
        require(numberOfShares > 0);
        owner = msg.sender;
        _mint(address(this), numberOfShares);
        //set sensible default values
        decisionParameters.decisionTime = 2592000; //30 days
        decisionParameters.executionTime = 604800; //7 days
        decisionParameters.quorumNumerator = 0;
        decisionParameters.quorumDenominator = 1;
        decisionParameters.majorityNumerator = 1;
        decisionParameters.majorityDenominator = 2;
        emit NewOwner(actionId, owner, VoteResult.NO_SHARES_IN_CIRCULATION);
        actionId++;
    }

    function decimals() public pure override returns (uint8) {
        return 0;
    }

    receive() external payable { //used to receive wei when msg.data is empty
        revert("Payments need to happen through wrapped Ether"); //as long as Ether is not ERC20 compliant
    }

    fallback() external payable { //used to receive wei when msg.data is not empty
        revert("Payments need to happen through wrapped Ether"); //as long as Ether is not ERC20 compliant
    }

    function getFloat() public view returns (uint256) { //return the number of shares not held by the company
        return totalSupply() - balanceOf(address(this));
    }

    function changesRequireApproval() public view returns (bool) {
        return shareHolderCount > 0;
    }

    function packShareHolders() external isOwner { //if a lot of active shareholders change, one may not want to iterate over non existing shareholders anymore when distributing a dividend
        uint256 packedIndex = 0;
        address[] memory packed;

        for (uint256 i = 0; i < shareHolderCount; i++) {
            address shareHolder = shareHolders[i];
            if (balanceOf(shareHolder) > 0) {
                packed[packedIndex] = shareHolder;
                packedIndex++;
            }
        }

        shareHolderCount = packedIndex;
        shareHolders = packed;
    }

    function changeOwner(address newOwner) external isOwner {
        if (!changesRequireApproval()) {
            owner = newOwner;
            emit NewOwner(actionId, owner, VoteResult.NO_SHARES_IN_CIRCULATION);
            actionId++;
        } else {
            NewOwnerActionData storage actionData = newOwnerActions[actionId];
            initVoteParameters(actionData.voteParameters);
            actionData.newOwner = newOwner;

            emit RequestNewOwner(actionId, owner);
            actionId++;
        }
    }

    function changeOwnerOnApproval(uint256 id) external {
        NewOwnerActionData storage actionData = newOwnerActions[id];

        VoteParameters storage vP = actionData.voteParameters;
        if (vP.result == VoteResult.PENDING) { //otherwise, the result is already known, no new processing required
            VotingStage votingStage = getVotingStage(vP);
            if (votingStage != VotingStage.VOTING_IN_PROGRESS) { //voting has ended
                updateVotingResult(vP, votingStage);

                if (vP.result == VoteResult.APPROVED) {
                    owner = actionData.newOwner;
                }
                emit NewOwner(id, actionData.newOwner, vP.result);
            }
        }
    }

    function updateVotingResult(VoteParameters storage vP, VotingStage votingStage) private {
        if (votingStage == VotingStage.EXECUTION_HAS_ENDED) {
            vP.result = VoteResult.EXPIRED;
        } else {
            (vP.inFavor, vP.against, vP.abstain, vP.noVote) = countVotes(vP);
            vP.result = verifyVotes(vP);
        }
    }

    function getVoteResult(ActionType actionType, uint256 id) external view returns (VoteResult, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256) {
        VoteParameters storage vP;
        if (actionType == ActionType.CORPORATE) {
            vP = corporateActions[id].voteParameters;
        } else if (actionType == ActionType.DECISION) {
            vP = decisionActions[id].voteParameters;
        } else if (actionType == ActionType.NEW_OWNER) {
            vP = decisionActions[id].voteParameters;
        } else {
            return (VoteResult.NON_EXISTENT, 0, 0, 0, 0, 0, 0, 0, 0);
        }
        DecisionParameters storage dP = vP.decisionParameters;
        VoteResult result = vP.result;
        if ((result == VoteResult.PENDING) && (getVotingStage(vP) == VotingStage.EXECUTION_HAS_ENDED)) {
            return (VoteResult.EXPIRED, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator, 0, 0, 0, 0);
        } else {
            return (result, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator, vP.noVote, vP.inFavor, vP.against, vP.abstain);
        }
    }

    function initVoteParameters(VoteParameters storage voteParameters) private {
        voteParameters.startTime = block.timestamp;
        voteParameters.decisionParameters = decisionParameters;
    }

    function getVotingStage(VoteParameters storage voteParameters) private view returns (VotingStage) {
        uint256 votingCutOff = voteParameters.startTime + voteParameters.decisionParameters.decisionTime;
        if (block.timestamp <= votingCutOff) {
            return VotingStage.VOTING_IN_PROGRESS;
        }

        uint256 lastExecutionTime = votingCutOff + voteParameters.decisionParameters.executionTime;

        return (block.timestamp <= lastExecutionTime) ? VotingStage.VOTING_HAS_ENDED : VotingStage.EXECUTION_HAS_ENDED;
    }

    function countVotes(VoteParameters storage voteParameters) private view returns (uint256, uint256, uint256, uint256) {
        uint256 inFavor = 0;
        uint256 against = 0;
        uint256 abstain = 0;
        uint256 noVote = 0;

        mapping(address => uint256) storage lastVote = voteParameters.lastVote;
        Vote[] storage votes = voteParameters.votes;
        for (uint256 i = 0; i < voteParameters.numberOfVotes; i++) {
            Vote storage vote = votes[i];
            if (lastVote[vote.voter] == i) { //a shareholder may vote as many times as he wants, but only consider his last vote
                uint256 votingPower = balanceOf(vote.voter);
                if (votingPower > 0) { //do not consider votes of shareholders who sold their shares
                    VoteType choice = vote.choice;
                    if (choice == VoteType.IN_FAVOR) {
                        inFavor += votingPower;
                    } else if (choice == VoteType.AGAINST) {
                        against += votingPower;
                    } else if (choice == VoteType.ABSTAIN) {
                        abstain += votingPower;
                    } else if (choice == VoteType.NO_VOTE) { //no votes do not count towards the quorum
                        noVote += votingPower;
                    }
                }
            }
        }

        return (inFavor, against, abstain, noVote);
    }

    function verifyVotes(VoteParameters storage vP) private view returns (VoteResult) {
        //first verify simple majority (the easiest calculation)
        if (vP.against >= vP.inFavor) {
            return VoteResult.REJECTED;
        }

        //then verify if the quorum is met
        if (!isQuorumMet(vP.decisionParameters.quorumNumerator, vP.decisionParameters.quorumDenominator, vP.inFavor + vP.against + vP.abstain, getFloat())) {
            return VoteResult.REJECTED;
        }

        //then verify if the required majority has been reached
        if (!isQuorumMet(vP.decisionParameters.quorumNumerator, vP.decisionParameters.quorumDenominator, vP.inFavor, vP.inFavor + vP.against)) {
            return VoteResult.REJECTED;
        }

        return VoteResult.APPROVED;
    }

    //presentNumerator/presentDenominator >= quorumNumerator/quorumDenominator <=> presentNumerator*quorumDenominator >= quorumNumerator*presentDenominator
    function isQuorumMet(uint32 quorumNumerator, uint32 quorumDenominator, uint256 presentNumerator, uint256 presentDenominator) private pure returns (bool) { //compare 2 fractions without causing overflow
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
            present = (presentNumerator & 0xFFFFFFFF)*quorumDenominator;
            quorum = (quorumNumerator & 0xFFFFFFFF)*presentDenominator;
            return (present >= quorum);
        }
    }

/*

    function issueShares(uint256 numberOfShares) external isOwner {
        require(numberOfShares > 0);
        _mint(address(this), numberOfShares); //issued amount is stored in Transfer event from address 0
    }

    function burnShares(uint256 numberOfShares) external isOwner {
        require(numberOfShares > 0);
        _burn(address(this), numberOfShares); //burned amount is stored in Transfer event to address 0
    }

    function getTokenBalance(address tokenAddress) external view returns (uint256) {
        IERC20 token = IERC20(tokenAddress);
        return token.balanceOf(address(this));
    }
*/
}