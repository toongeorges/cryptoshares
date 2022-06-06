// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import 'contracts/IExchange.sol';

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
    NEW_OWNER, DECISION, CORPORATE
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
    uint256 numberOfVotes;
    Vote[] votes;

    uint256 inFavor;
    uint256 against;
    uint256 abstain;
    uint256 noVote;
}

struct NewOwnerActionData {
    VoteParameters voteParameters;

    address newOwner;
}

struct DecisionActionData {
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
    uint256 currencyAmount; //empty for ISSUE_SHARES and DESTROY_SHARES, the ask or bid price for a single share for RAISE_FUNDS and BUY_BACK, the amount of dividend to be distributed per share for DISTRIBUTE_DIVIDEND
    address optionalCurrency; //ERC20 token
    uint256 optionalCurrencyAmount; //only relevant in the case of an optional dividend for DISTRIBUTE_DIVIDEND, shareholders can opt for the optional dividend instead of the default dividend
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

    address public owner;
    
    uint256 public shareHolderCount;
    address[] private shareHolders; //we need to keep track of the shareholders in case of distributing a dividend

    DecisionParameters public decisionParameters;

    uint256 public newOwnerId;
    mapping(uint256 => NewOwnerActionData) private newOwnerActions;
    uint256 public decisionId;
    mapping(uint256 => DecisionActionData) private decisionActions;
    uint256 public corporateActionId;
    mapping(uint256 => CorporateActionData) private corporateActions;
    uint256 public externalProposalId;
    mapping(uint256 => VoteParameters) private externalProposals;

    modifier isOwner() {
        require(msg.sender == owner);
        _;
    }

    modifier proceedOnVoteResultUpdate(VoteParameters storage vP) {
        if (vP.result == VoteResult.PENDING) { //otherwise, the result is already known, no new processing required
            VotingStage votingStage = getVotingStage(vP);
            if ((votingStage != VotingStage.VOTING_IN_PROGRESS) || !changesRequireApproval()) { //voting has ended
                if (votingStage == VotingStage.EXECUTION_HAS_ENDED) {
                    vP.result = VoteResult.EXPIRED;
                } else if(!changesRequireApproval()) { //if for some reason all shares have been bought back
                    vP.result = VoteResult.APPROVED;
                } else {
                    (vP.inFavor, vP.against, vP.abstain, vP.noVote) = countVotes(vP);
                    vP.result = verifyVotes(vP);
                }
                _;
            } else {
                revert("voting still in progress");
            }
        }
    }

    modifier proceedOnWithdrawal(VoteParameters storage vP) {
        if (vP.result == VoteResult.PENDING) { //can only withdraw if the result is still pending
            VotingStage votingStage = getVotingStage(vP);
            if (votingStage == VotingStage.EXECUTION_HAS_ENDED) { //cannot withdraw anymore
                vP.result = VoteResult.EXPIRED;
            } else {
                vP.result = VoteResult.WITHDRAWN;
            }
            _;
        }
    }

    modifier proceedOnRequest(VoteParameters storage vP) {
        if (vP.result != VoteResult.PENDING) {
            initVoteParameters(vP);
            _;
        } else {
            revert("cannot initiate a new request while an old request is still pending");
        }
    }

    constructor(string memory name, string memory symbol, uint256 numberOfShares) ERC20(name, symbol) {
        owner = msg.sender;
        _mint(address(this), numberOfShares);

        //set sensible default values
        setDecisionTime(decisionParameters, 2592000, 604800); //30 and 7 days
        setQuorum(decisionParameters, 0, 1);
        setMajority(decisionParameters, 1, 2);

        emit NewOwner(newOwnerId, owner, VoteResult.NO_OUTSTANDING_SHARES);
        newOwnerId++;
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

    function getOutstandingShareCount() public view returns (uint256) { //return the number of shares not held by the company
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

        if (packedIndex == 0) { //changes do not require approval anymore, resolve all pending votes
            NewOwnerActionData storage newOwnerActionData = newOwnerActions[newOwnerId];
            doChangeOwnerOnApproval(newOwnerId, newOwnerActionData, newOwnerActionData.voteParameters);

            DecisionActionData storage decisionActionData = decisionActions[decisionId];
            doChangeDecisionParametersOnApproval(decisionId, decisionActionData, decisionActionData.voteParameters);

            //TODO resolve corporate action vote
            //TODO resolve multiple! external proposal votes
        }
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
        return newOwnerActions[id].newOwner;
    }

    function getProposedDecisionParameters(uint256 id) external view returns (DecisionParameters memory) {
        return decisionActions[id].proposedParameters;
    }

    function getProposedCorporateAction(uint256 id) external view returns (CorporateActionType, address, uint256, address, uint256, address, uint256) {
        CorporateActionData storage actionData = corporateActions[id];
        return (actionData.actionType, actionData.exchange, actionData.numberOfShares, actionData.currency, actionData.currencyAmount, actionData.optionalCurrency, actionData.optionalCurrencyAmount);
    }

    function vote(ActionType actionType, uint256 id, VoteType decision) external {
        VoteParameters storage vP = getVoteParameters(actionType, id);
        if ((vP.result == VoteResult.PENDING) && (getVotingStage(vP) == VotingStage.VOTING_IN_PROGRESS)) { //vP.result could be e.g. WITHDRAWN while the voting stage is still in progress
            address voter = msg.sender;
            if (balanceOf(voter) > 0) { //The amount of shares of the voter is checked later, so it does not matter if the voter still sells all his shares before the vote resolution.  This check just prevents people with no shares from increasing the votes array.
                vP.lastVote[voter] = vP.numberOfVotes;
                vP.votes[vP.numberOfVotes] = Vote(voter, decision);
                vP.numberOfVotes++;
            }
        } else {
            revert("Cannot vote anymore");
        }
    }



    function changeOwner(address newOwner) external isOwner {
        if (!changesRequireApproval()) {
            owner = newOwner;

            emit NewOwner(newOwnerId, owner, VoteResult.NO_OUTSTANDING_SHARES);
            newOwnerId++;
        } else {
            doRequestChangeOwner(newOwnerActions[newOwnerId], newOwner);
        }
    }

    function doRequestChangeOwner(NewOwnerActionData storage actionData, address newOwner) internal proceedOnRequest(actionData.voteParameters) {
        actionData.newOwner = newOwner;

        emit RequestNewOwner(newOwnerId, owner);
    }

    function changeOwnerOnApproval(uint256 id) external {
        NewOwnerActionData storage actionData = newOwnerActions[id];
        doChangeOwnerOnApproval(id, actionData, actionData.voteParameters);
    }

    function doChangeOwnerOnApproval(uint256 id, NewOwnerActionData storage actionData, VoteParameters storage vP) internal proceedOnVoteResultUpdate(vP) {
        if (vP.result == VoteResult.APPROVED) {
            owner = actionData.newOwner;
        }

        emit NewOwner(id, actionData.newOwner, vP.result);
        newOwnerId++;
    }

    function withdrawChangeOwnerRequest(uint256 id) external isOwner {
        NewOwnerActionData storage actionData = newOwnerActions[id];
        doWithdrawChangeOwnerRequest(id, actionData, actionData.voteParameters);
    }

    function doWithdrawChangeOwnerRequest(uint256 id, NewOwnerActionData storage actionData, VoteParameters storage vP) internal proceedOnWithdrawal(vP) {
        emit NewOwner(id, actionData.newOwner, vP.result);
    }

    function changeDecisionTime(uint64 decisionTime, uint64 executionTime) external isOwner {
        doChangeDecisionParameters(DecisionActionType.CHANGE_DECISION_TIME, decisionTime, executionTime, decisionParameters.quorumNumerator, decisionParameters.quorumDenominator, decisionParameters.majorityNumerator, decisionParameters.majorityDenominator);
    }

    function changeQuorum(uint32 quorumNumerator, uint32 quorumDenominator) external isOwner {
        doChangeDecisionParameters(DecisionActionType.CHANGE_QUORUM, decisionParameters.decisionTime, decisionParameters.executionTime, quorumNumerator, quorumDenominator, decisionParameters.majorityNumerator, decisionParameters.majorityDenominator);
    }

    function changeMajority(uint32 majorityNumerator, uint32 majorityDenominator) external isOwner {
        doChangeDecisionParameters(DecisionActionType.CHANGE_MAJORITY, decisionParameters.decisionTime, decisionParameters.executionTime, decisionParameters.quorumNumerator, decisionParameters.quorumDenominator, majorityNumerator, majorityDenominator);
    }

    function changeDecisionParameters(uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) external isOwner {
        doChangeDecisionParameters(DecisionActionType.CHANGE_ALL, decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
    }

    function doChangeDecisionParameters(DecisionActionType actionType, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) internal {
        if (!changesRequireApproval()) {
            setDecisionTime(decisionParameters, decisionTime, executionTime);
            setQuorum(decisionParameters, quorumNumerator, quorumDenominator);
            setMajority(decisionParameters, majorityNumerator, majorityDenominator);

            emit DecisionParameterChange(decisionId, actionType, VoteResult.NO_OUTSTANDING_SHARES);
            decisionId++;
        } else {
            doRequestChangeDecisionParameters(decisionActions[decisionId], actionType, decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
        }
    }

    function doRequestChangeDecisionParameters(DecisionActionData storage actionData, DecisionActionType actionType, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) internal proceedOnRequest(actionData.voteParameters) {
        actionData.actionType = actionType;
        DecisionParameters storage proposedParameters = actionData.proposedParameters;
        setDecisionTime(proposedParameters, decisionTime, executionTime);
        setQuorum(proposedParameters, quorumNumerator, quorumDenominator);
        setMajority(proposedParameters, majorityNumerator, majorityDenominator);

        emit RequestDecisionParameterChange(decisionId, actionType);
    }

    function changeDecisionParametersOnApproval(uint256 id) external {
        DecisionActionData storage actionData = decisionActions[id];
        doChangeDecisionParametersOnApproval(id, actionData, actionData.voteParameters);
    }

    function doChangeDecisionParametersOnApproval(uint256 id, DecisionActionData storage actionData, VoteParameters storage vP) internal proceedOnVoteResultUpdate(vP) {
        if (vP.result == VoteResult.APPROVED) {
            DecisionParameters storage pP = actionData.proposedParameters;
            setDecisionTime(decisionParameters, pP.decisionTime, pP.executionTime);
            setQuorum(decisionParameters, pP.quorumNumerator, pP.quorumDenominator);
            setMajority(decisionParameters, pP.majorityNumerator, pP.majorityDenominator);
        }

        emit DecisionParameterChange(id, actionData.actionType, vP.result);
        decisionId++;
    }

    function withdrawChangeDecisionParametersRequest(uint256 id) external isOwner {
        DecisionActionData storage actionData = decisionActions[id];
        doWithdrawChangeDecisionParametersRequest(id, actionData, actionData.voteParameters);
    }

    function doWithdrawChangeDecisionParametersRequest(uint256 id, DecisionActionData storage actionData, VoteParameters storage vP) internal proceedOnWithdrawal(vP) {
        emit DecisionParameterChange(id, actionData.actionType, vP.result);
    }

    function issueShares(uint256 numberOfShares) external isOwner {
        if (!changesRequireApproval()) {
            _mint(address(this), numberOfShares);

            emit CorporateAction(corporateActionId, CorporateActionType.ISSUE_SHARES, VoteResult.NO_OUTSTANDING_SHARES);
            corporateActionId++;
        } else {
            doRequestCorporateAction(corporateActions[corporateActionId], CorporateActionType.ISSUE_SHARES, numberOfShares, address(0), address(0), 0, address(0), 0);
        }
    }

    function destroyShares(uint256 numberOfShares) external isOwner {
        if (!changesRequireApproval()) {
            _burn(address(this), numberOfShares); //already checks if this address has enough ERC20 tokens

            emit CorporateAction(corporateActionId, CorporateActionType.DESTROY_SHARES, VoteResult.NO_OUTSTANDING_SHARES);
            corporateActionId++;
            revert("Cannot initiate a new corporate action while an old corporate action is still pending");
        } else {
            require(balanceOf(address(this)) >= numberOfShares, "Cannot destroy more shares than the number of treasury shares");
            doRequestCorporateAction(corporateActions[corporateActionId], CorporateActionType.DESTROY_SHARES, numberOfShares, address(0), address(0), 0, address(0), 0);
        }
    }

    function doRequestCorporateAction(CorporateActionData storage actionData, CorporateActionType actionType, uint256 numberOfShares, address exchange, address currency, uint256 currencyAmount, address optionalCurrency, uint256 optionalCurrencyAmount) internal proceedOnRequest(actionData.voteParameters) {
        actionData.actionType = actionType;
        actionData.numberOfShares = numberOfShares;
        if (exchange != address(0)) { //only store the exchange address if this is relevant
            actionData.exchange = exchange;
        }
        if (currency != address(0)) { //only store pricePerShare info if this is relevant
            actionData.currency = currency;
            actionData.currencyAmount = currencyAmount;
        }
        if (optionalCurrency != address(0)) { //only store optionalDividend info if this is relevant
            actionData.optionalCurrency = optionalCurrency;
            actionData.optionalCurrencyAmount = optionalCurrencyAmount;
        }
    }

/*
    function raiseFunds(uint256 numberOfShares, address exchange, address currency, uint256 amount) external isOwner {
        if (!changesRequireApproval()) {
            increaseAllowance(exchange, numberOfShares);
            //TODO we have to lock up these shares, because ERC20 does not do this!
            //TODO we also need a way of getting unsold shares back in case of a cancel, which needs another approval

            emit CorporateAction(corporateActionId, CorporateActionType.RAISE_FUNDS, VoteResult.NO_OUTSTANDING_SHARES);
            corporateActionId++;
            revert("Cannot initiate a new corporate action while an old corporate action is still pending");
        } else {
            require(balanceOf(address(this)) >= numberOfShares, "Cannot destroy more shares than the number of treasury shares");
            doRequestCorporateAction(corporateActions[corporateActionId], CorporateActionType.RAISE_FUNDS, numberOfShares, exchange, currency, amount, address(0), 0);
        }
    }

    function buyBackShares(uint256 numberOfShares, address currency, uint256 amount, address exchange) external isOwner {

    }

    function distributeDividend(uint256 numberOfShares, address currency, uint256 amount) external isOwner {

    }

    function distributeOptionalDividend(uint256 numberOfShares, address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount) external isOwner {

    }
*/
    //TODO initiate corporate actions
    //TODO approve corporate actions
    //TODO withdraw corporate actions

    //TODO initiate external proposals (in parallel)
    //TODO approve external proposals
    //TODO withdraw external proposals

    //TODO think about how a company can withdraw funds acquired e.g. through raising funds, may need approval as well!


    function setDecisionTime(DecisionParameters storage dP, uint64 decisionTime, uint64 executionTime) internal {
        dP.decisionTime = decisionTime;
        dP.executionTime = executionTime;
    }

    function setQuorum(DecisionParameters storage dP, uint32 quorumNumerator, uint32 quorumDenominator) internal {
        require(quorumDenominator > 0);
        dP.quorumNumerator = quorumNumerator;
        dP.quorumDenominator = quorumDenominator;
    }

    function setMajority(DecisionParameters storage dP, uint32 majorityNumerator, uint32 majorityDenominator) internal {
        require(majorityDenominator > 0);
        require((majorityNumerator << 1) >= majorityDenominator);
        dP.majorityNumerator = majorityNumerator;
        dP.majorityDenominator = majorityDenominator;
    }

    function getVoteParameters(ActionType actionType, uint256 id) internal view returns (VoteParameters storage) {
        if (actionType == ActionType.CORPORATE) {
            return corporateActions[id].voteParameters;
        } else if (actionType == ActionType.DECISION) {
            return decisionActions[id].voteParameters;
        } else if (actionType == ActionType.NEW_OWNER) {
            return newOwnerActions[id].voteParameters;
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

    function countVotes(VoteParameters storage voteParameters) internal view returns (uint256, uint256, uint256, uint256) {
        uint256 inFavor = 0;
        uint256 against = 0;
        uint256 abstain = 0;
        uint256 noVote = 0;

        mapping(address => uint256) storage lastVote = voteParameters.lastVote;
        Vote[] storage votes = voteParameters.votes;
        for (uint256 i = 0; i < voteParameters.numberOfVotes; i++) {
            Vote storage v = votes[i];
            if (lastVote[v.voter] == i) { //a shareholder may vote as many times as he wants, but only consider his last vote
                uint256 votingPower = balanceOf(v.voter);
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

    function verifyVotes(VoteParameters storage vP) internal view returns (VoteResult) {
        //first verify simple majority (the easiest calculation)
        if (vP.against >= vP.inFavor) {
            return VoteResult.REJECTED;
        }

        //then verify if the quorum is met
        if (!isQuorumMet(vP.decisionParameters.quorumNumerator, vP.decisionParameters.quorumDenominator, vP.inFavor + vP.against + vP.abstain, getOutstandingShareCount())) {
            return VoteResult.REJECTED;
        }

        //then verify if the required majority has been reached
        if (!isQuorumMet(vP.decisionParameters.quorumNumerator, vP.decisionParameters.quorumDenominator, vP.inFavor, vP.inFavor + vP.against)) {
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