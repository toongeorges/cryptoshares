// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import 'contracts/IShare.sol';
import 'contracts/IExchange.sol';

enum VotingStage {
    VOTING_IN_PROGRESS, VOTING_HAS_ENDED, EXECUTION_HAS_ENDED
}

/**
Deleting an array or resetting an array to an empty array is broken in Solidity,
since the gas cost for both is O(n) with n the number of elements in the original array and n can be unbounded.

Whenever an array is used, a mechanism must be provided to reduce the size of the array, to prevent iterating over the array becoming too costly.
This mechanism however cannot rely on deleting or resetting the array, since these operations fail themselves at this point.

Iteration over an array has to happen in a paged manner

Arrays can be reduced as follows:
- we need to store an extra field for the length of the array in exchangesLength (the length property of the exchanges array is only useful to determine whether we have to push or overwrite an existing value)
- we need to store an extra field for the length of the packed array in packedLength (during packing)
- we need to store an extra field for the array index from where the array has not been packed yet in unpackedIndex

if unpackedIndex == 0, all elements of the array are  in [0, exchangesLength[

if unpackedIndex > 0, all elements of the array are in [0, packedLength[ and [unpackedIndex, exchangesLength[
*/
struct ExchangeInfo {
    uint256 unpackedIndex;
    uint256 packedLength;
    mapping(address => uint256) exchangeIndex;
    uint256 exchangesLength;
    address[] exchanges;
}

struct Vote {
    address voter;
    VoteChoice choice;
}

struct VoteParameters {
    //pack these 2 variables together
    uint64 startTime;
    VoteResult result;

    DecisionParameters decisionParameters; //store this on creation, so it cannot be changed afterwards

    mapping(address => uint256) voteIndex;
    Vote[] votes;

    uint256 inFavor;
    uint256 against;
    uint256 abstain;
    uint256 noVote;
}

struct CorporateActionData { //see the RequestCorporateAction and CorporateAction event in the IShare interface for the meaning of these fields
    ActionType decisionType;
    address exchange;
    uint256 numberOfShares;
    address currency;
    uint256 amount;
    address optionalCurrency;
    uint256 optionalAmount;
}

contract Share is ERC20, IShare {
    using SafeERC20 for IERC20;

    address public owner;

    mapping(address => ExchangeInfo) private exchangeInfo;

    /**
    In order to save gas costs while iterating over shareholders, they can be packed (old shareholders that are no shareholders anymore are removed)
    Packing is in progress if and only if unpackedShareholderIndex > 0

    if unpackedShareholderIndex == 0, we find all shareholders for the indices [1, shareholdersLength[
    
    if unpackedShareholderIndex > 0, we find all shareholders for the indices [1, packedShareholdersLength[ and [unpackedShareholderIndex, shareholdersLength[
     */
    uint256 private unpackedShareholderIndex; //up to where the packing went, 0 if no packing in progress
    uint256 private packedShareholdersLength; //up to where the packing went, 0 if no packing in progress
    mapping(address => uint256) private shareholderIndex;
    uint256 private shareholdersLength; //after packing, the (invalid) contents at a location from this index onwards are ignored
    address[] private shareholders; //we need to keep track of the shareholders in case of distributing a dividend

    //proposals
    mapping(ActionType => DecisionParameters) private decisionParameters;
    VoteParameters[] private proposals;

    mapping(uint256 => bool) private externalProposals;
    mapping(uint256 => address) private newOwners;
    mapping(uint256 => ActionType) private decisionParametersVoteType;
    mapping(uint256 => DecisionParameters) private decisionParametersData;
    mapping(uint256 => CorporateActionData) private corporateActionsData;

    uint256 public pendingNewOwnerId;
    uint256 public pendingDecisionParametersId;
    uint256 public pendingCorporateActionId;

    modifier isOwner() {
        _isOwner(); //putting the code in a fuction reduces the size of the compiled smart contract!
        _;
    }

    function _isOwner() internal view {
        require(msg.sender == owner);
    }

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        owner = msg.sender;
        shareholders.push(address(this)); //to make later operations on shareholders less costly
        shareholdersLength++;
    }



    function decimals() public pure override returns (uint8) {
        return 0;
    }

    receive() external payable { //used to receive wei when msg.data is empty
        revert DoNotAcceptEtherPayments();
    }

    fallback() external payable { //used to receive wei when msg.data is not empty
        revert DoNotAcceptEtherPayments();
    }



    function getLockedUpAmount(address tokenAddress) public view override returns (uint256) {
        ExchangeInfo storage info = exchangeInfo[tokenAddress];
        address[] storage exchanges = info.exchanges;
        IERC20 token = IERC20(tokenAddress);

        uint256 lockedUpAmount = 0;
        uint256 unpackedIndex = info.unpackedIndex;
        if (unpackedIndex == 0) {
            for (uint256 i = 0; i < info.exchangesLength; i++) {
                lockedUpAmount += token.allowance(address(this), exchanges[i]);
            }
        } else {
            for (uint256 i = 0; i < info.packedLength; i++) {
                lockedUpAmount += token.allowance(address(this), exchanges[i]);
            }
            for (uint256 i = unpackedIndex; i < info.exchangesLength; i++) {
                lockedUpAmount += token.allowance(address(this), exchanges[i]);
            }
        }
        return lockedUpAmount;
    }

    function getAvailableAmount(address tokenAddress) public view override returns (uint256) {
        return IERC20(tokenAddress).balanceOf(address(this)) - getLockedUpAmount(tokenAddress);
    }

    function getTreasuryShareCount() public view override returns (uint256) { //return the number of shares held by the company
        return balanceOf(address(this)) - getLockedUpAmount(address(this));
    }

    function getOutstandingShareCount() public view override returns (uint256) { //return the number of shares not held by the company
        return totalSupply() - balanceOf(address(this));
    }

    //getMaxOutstandingShareCount() >= getOutstandingShareCount(), we are also counting the shares that have been locked up in exchanges and may be sold
    function getMaxOutstandingShareCount() public view override returns (uint256) {
        return totalSupply() - getTreasuryShareCount();
    }



    function getExchangeCount(address tokenAddress) external view returns (uint256) {
        return exchangeInfo[tokenAddress].exchangesLength;        
    }

    function getExchangePackSize(address tokenAddress) external view returns (uint256) {
        ExchangeInfo storage info = exchangeInfo[tokenAddress];
        return info.exchangesLength - info.unpackedIndex;
    }

    function registerExchange(address tokenAddress, address exchange) internal {
        ExchangeInfo storage info = exchangeInfo[tokenAddress];
        mapping(address => uint256) storage exchangeIndex = info.exchangeIndex;
        uint256 index = exchangeIndex[exchange];
        if (index == 0) { //the exchange has not been registered yet OR was the first registered exchange
            address[] storage exchanges = info.exchanges;
            if ((exchanges.length == 0) || (exchanges[0] != exchange)) { //the exchange has not been registered yet
                if (IERC20(tokenAddress).allowance(address(this), exchange) > 0) {
                    index = info.exchangesLength;
                    exchangeIndex[exchange] = index;
                    if (index < exchanges.length) {
                        exchanges[index] = exchange;
                    } else {
                        exchanges.push(exchange);
                    }
                    info.exchangesLength++;
                }
            }
        }
    }

    function packExchanges(address tokenAddress, uint256 amountToPack) external override {
        require(amountToPack > 0);

        ExchangeInfo storage info = exchangeInfo[tokenAddress];

        uint256 start = info.unpackedIndex;
        uint256 end = start + amountToPack;
        uint maxEnd = info.exchangesLength;
        if (end > maxEnd) {
            end = maxEnd;
        }

        uint256 packedIndex;
        if (start == 0) { //start a new packing
            packedIndex = 0;
        } else {
            packedIndex = info.packedLength;
        }

        mapping(address => uint256) storage exchangeIndex = info.exchangeIndex;
        address[] storage exchanges = info.exchanges;
        IERC20 token = IERC20(tokenAddress);
        for (uint256 i = start; i < end; i++) {
            address exchange = exchanges[i];
            if (token.allowance(address(this), exchange) > 0) { //only register if the exchange still has locked up tokens
                exchangeIndex[exchange] = packedIndex;
                exchanges[packedIndex] = exchange;
                packedIndex++;
            } else {
                exchangeIndex[exchange] = 0;
            }
        }
        info.packedLength = packedIndex;

        if (end == maxEnd) {
            info.unpackedIndex = 0;
            info.exchangesLength = packedIndex;
        } else {
            info.unpackedIndex = end;
        }
    }

    function getShareholderCount() public view override returns (uint256) {
        return shareholdersLength - 1; //the first address is taken by this contract, which is not a shareholder
    }

    function registerShareholder(address shareholder) external override returns (uint256) {
        uint256 index = shareholderIndex[shareholder];
        if (index == 0) { //the shareholder has not been registered yet (the address at index 0 is this contract)
            if (balanceOf(shareholder) > 0) { //only register if the address is an actual shareholder
                index = shareholdersLength;
                shareholderIndex[shareholder] = index;
                if (index < shareholders.length) {
                    shareholders[index] = shareholder;
                } else {
                    shareholders.push(shareholder);
                }
                shareholdersLength++;
                return index;
            }
        }
        return index;
    }

    function getShareholderPackSize() external view returns (uint256) {
        return (unpackedShareholderIndex == 0) ? getShareholderCount() : (shareholdersLength - unpackedShareholderIndex);
    }

    function packShareholders(uint256 amountToPack) external override {
        require(amountToPack > 0);

        uint256 start = unpackedShareholderIndex;
        uint256 end = start + amountToPack;
        uint maxEnd = shareholdersLength;
        if (end > maxEnd) {
            end = maxEnd;
        }

        uint256 packedIndex;
        if (start == 0) { //start a new packing
            start = 1;
            packedIndex = 1;
        } else {
            packedIndex = packedShareholdersLength;
        }

        for (uint256 i = start; i < end; i++) {
            address shareholder = shareholders[i];
            if (balanceOf(shareholder) > 0) { //only register if the address is an actual shareholder
                shareholderIndex[shareholder] = packedIndex;
                shareholders[packedIndex] = shareholder;
                packedIndex++;
            } else {
                shareholderIndex[shareholder] = 0;
            }
        }
        packedShareholdersLength = packedIndex;

        if (end == maxEnd) {
            unpackedShareholderIndex = 0;
            shareholdersLength = packedIndex;
        } else {
            unpackedShareholderIndex = end;
        }
    }



    function getNumberOfProposals() external view override returns (uint256) {
        return proposals.length;
    }

    function getDecisionParameters(uint256 id) external view override returns (uint64, uint64, uint32, uint32, uint32, uint32) {
        DecisionParameters storage dP = proposals[id].decisionParameters;
        return (dP.decisionTime, dP.executionTime, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator);
    }

    function getDecisionTimes(uint256 id) external view override returns (uint64, uint64, uint64) {
        VoteParameters storage vP = proposals[id];
        DecisionParameters storage dP = vP.decisionParameters;

        uint64 startTime = vP.startTime;
        uint64 decisionTime = startTime + dP.decisionTime;
        uint64 executionTime = decisionTime + dP.executionTime;

        return (startTime, decisionTime, executionTime);
    }

    function getDetailedVoteResult(uint256 id) external view override returns (VoteResult, uint32, uint32, uint32, uint32, uint256, uint256, uint256, uint256) {
        VoteParameters storage vP = proposals[id];
        DecisionParameters storage dP = vP.decisionParameters;
        VoteResult result = vP.result;
        return isExpired(result, vP)
             ? (VoteResult.EXPIRED, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator, 0, 0, 0, 0)
             : (result, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator, vP.inFavor, vP.against, vP.abstain, vP.noVote);
    }

    function getVoteResult(uint256 id) public view override returns (VoteResult) {
        VoteParameters storage vP = proposals[id];
        VoteResult result = vP.result;
        return isExpired(result, vP) ? VoteResult.EXPIRED : result;
    }

    function isExpired(VoteResult result, VoteParameters storage vP) internal view returns (bool) {
        return (result == VoteResult.PENDING) && (getVotingStage(vP) == VotingStage.EXECUTION_HAS_ENDED);
    }



    function isExternalProposal(uint256 id) external view override returns (bool) {
        return externalProposals[id];
    }

    function getProposedOwner(uint256 id) external view override returns (address) {
        return newOwners[id];
    }

    function getProposedDecisionParameters(uint256 id) external view override returns (ActionType, uint64, uint64, uint32, uint32, uint32, uint32) {
        DecisionParameters storage dP = decisionParametersData[id];
        return (decisionParametersVoteType[id], dP.decisionTime, dP.executionTime, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator);
    }

    function getProposedCorporateAction(uint256 id) external view override returns (ActionType, uint256, address, address, uint256, address, uint256) {
        CorporateActionData storage cA = corporateActionsData[id];
        return (cA.decisionType, cA.numberOfShares, cA.exchange, cA.currency, cA.amount, cA.optionalCurrency, cA.optionalAmount);
    }



    function makeExternalProposal() external override isOwner returns (uint256) {
        (uint256 id, bool noSharesOutstanding) = propose(ActionType.EXTERNAL);

        externalProposals[id] = true;

        if (noSharesOutstanding) {
            doMakeExternalProposal(id);
        } else {
            emit RequestExternalProposal(id);
        }

        return id;
    }

    function resolveExternalProposal(uint256 id) external override {
        resolveExternalProposal(id, false);
    }

    function withdrawExternalProposal(uint256 id) external override isOwner {
        resolveExternalProposal(id, true);
    }

    function resolveExternalProposal(uint256 id, bool withdraw) internal {
        if (externalProposals[id]) {
            if (resultHasBeenUpdated(id, withdraw)) {
                doMakeExternalProposal(id);
            } else {
                revert RequestNotResolved();
            }
        } else {
            revert NoExternalProposal();
        }
    }

    function doMakeExternalProposal(uint256 id) internal {
        emit ExternalProposal(id, getVoteResult(id));
    }



    function changeOwner(address newOwner) external override isOwner {
        if (pendingNewOwnerId == 0) {
            (uint256 id, bool noSharesOutstanding) = propose(ActionType.CHANGE_OWNER);

            newOwners[id] = newOwner;

            if (noSharesOutstanding) {
                doChangeOwner(id, newOwner);
            } else {
                pendingNewOwnerId = id;

                emit RequestChangeOwner(id, newOwner);
            }
        } else {
            revert RequestPending();
        }
    }

    function resolveChangeOwnerVote() public override {
        resolveChangeOwner(false);
    }

    function withdrawChangeOwnerVote() external override isOwner {
        resolveChangeOwner(true);
    }

    function resolveChangeOwner(bool withdraw) internal {
        uint256 id = pendingNewOwnerId;
        if (id != 0) {
            if (resultHasBeenUpdated(id, withdraw)) {
                doChangeOwner(id, newOwners[id]);

                pendingNewOwnerId = 0;
            } else {
                revert RequestNotResolved();
            }
        } else {
            revert NoRequestPending();
        }
    }

    function doChangeOwner(uint256 id, address newOwner) internal {
        VoteResult voteResult = getVoteResult(id);

        if (isApproved(voteResult)) {
            owner = newOwner;
        }

        emit ChangeOwner(id, voteResult, newOwner);
    }



    function getDecisionParameters(ActionType voteType) external override returns (uint64, uint64, uint32, uint32, uint32, uint32) {
        DecisionParameters storage dP = doGetDecisionParameters(voteType);
        return (dP.decisionTime, dP.executionTime, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator);
    }

    function doGetDecisionParameters(ActionType voteType) internal returns (DecisionParameters storage) {
        if (voteType == ActionType.DEFAULT) {
            return doGetDefaultDecisionParameters();
        } else {
            DecisionParameters storage dP = decisionParameters[voteType];
            return (dP.quorumDenominator == 0) //check if the decisionParameters have been set
                 ? doGetDefaultDecisionParameters() //decisionParameters have not been initialized, fall back to default decisionParameters
                 : dP;
        }
    }

    function doGetDefaultDecisionParameters() internal returns (DecisionParameters storage) {
        DecisionParameters storage dP = decisionParameters[ActionType.DEFAULT];
        if (dP.quorumDenominator == 0) { //default decisionParameters have not been initialized, initialize with sensible values
            dP.decisionTime = 2592000; //30 days
            dP.executionTime = 604800; //7 days
            dP.quorumNumerator = 0;
            dP.quorumDenominator = 1;
            dP.majorityNumerator = 1;
            dP.majorityDenominator = 2;

            emit ChangeDecisionParameters(proposals.length, VoteResult.NON_EXISTENT, ActionType.DEFAULT, 2592000, 604800, 0, 1, 1, 2);
        }
        return dP;
    }

    function changeDecisionParameters(ActionType voteType, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) external override isOwner {
        if (pendingDecisionParametersId == 0) {
            require(quorumDenominator > 0);
            require(majorityDenominator > 0);
            require((majorityNumerator << 1) >= majorityDenominator);

            (uint256 id, bool noSharesOutstanding) = propose(ActionType.CHANGE_DECISION_PARAMETERS);

            decisionParametersVoteType[id] = voteType;

            DecisionParameters storage dP = decisionParametersData[id];
            dP.decisionTime = decisionTime;
            dP.executionTime = executionTime;
            dP.quorumNumerator = quorumNumerator;
            dP.quorumDenominator = quorumDenominator;
            dP.majorityNumerator = majorityNumerator;
            dP.majorityDenominator = majorityDenominator;

            if (noSharesOutstanding) {
                doSetDecisionParameters(id, voteType, decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
            } else {
                pendingDecisionParametersId = id;

                emit RequestChangeDecisionParameters(id, voteType, decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
            }
        } else {
            revert RequestPending();
        }
    }

    function resolveChangeDecisionParametersVote() public override {
        resolveChangeDecisionParameters(false);
    }

    function withdrawChangeDecisionParametersVote() external override isOwner {
        resolveChangeDecisionParameters(true);
    }

    function resolveChangeDecisionParameters(bool withdraw) internal {
        uint256 id = pendingDecisionParametersId;
        if (id != 0) {
            if (resultHasBeenUpdated(id, withdraw)) {
                DecisionParameters storage dP = decisionParametersData[id];
                doSetDecisionParameters(id, decisionParametersVoteType[id], dP.decisionTime, dP.executionTime, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator);

                pendingDecisionParametersId = 0;
            } else {
                revert RequestNotResolved();
            }
        } else {
            revert NoRequestPending();
        }
    }

    function doSetDecisionParameters(uint256 id, ActionType voteType, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) internal {
        VoteResult voteResult = getVoteResult(id);

        if (isApproved(voteResult)) {
            DecisionParameters storage dP = decisionParameters[voteType];
            dP.decisionTime = decisionTime;
            dP.executionTime = executionTime;
            dP.quorumNumerator = quorumNumerator;
            dP.quorumDenominator = quorumDenominator;
            dP.majorityNumerator = majorityNumerator;
            dP.majorityDenominator = majorityDenominator;
        }

        emit ChangeDecisionParameters(id, voteResult, voteType, decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
    }



    function isApproved(VoteResult voteResult) internal pure returns (bool) {
        return ((voteResult == VoteResult.APPROVED) || (voteResult == VoteResult.NO_OUTSTANDING_SHARES));
    }

    function resultHasBeenUpdated(uint256 id, bool withdraw) internal returns (bool) {
        return withdraw ? withdrawVote(id) : resolveVote(id); //return true if a result is pending (id != 0) and if the vote has been withdrawn or resolved
    }



    function vote(uint256 id, VoteChoice decision) external override {
        VoteParameters storage vP = proposals[id];
        if ((vP.result == VoteResult.PENDING) && (getVotingStage(vP) == VotingStage.VOTING_IN_PROGRESS) && (balanceOf(msg.sender) > 0)) { //vP.result could be e.g. WITHDRAWN while the voting stage is still in progress
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

    function propose(ActionType voteType) internal returns (uint256, bool) {
        DecisionParameters storage dP = doGetDecisionParameters(voteType);
        uint256 index = proposals.length;
        VoteParameters storage vP = proposals.push();
        vP.startTime = uint64(block.timestamp); // 500 000 000 000 years is more than enough, save some storage space
        vP.decisionParameters = dP; //copy by value
        vP.votes.push(Vote(address(this), VoteChoice.NO_VOTE)); //this reduces checks on index == 0 to be made in the vote method, to save gas for the vote method

        if (getOutstandingShareCount() == 0) { //auto approve if there are no shares outstanding
            vP.result = VoteResult.NO_OUTSTANDING_SHARES; 

            return (index, true);
        } else {
            vP.result = VoteResult.PENDING; 

            return (index, false);
        }
    }

    function withdrawVote(uint256 id) internal returns (bool) {
        VoteParameters storage vP = proposals[id];
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

    function resolveVote(uint256 id) internal returns (bool) { //The owner of the vote needs to resolve it so he can take appropriate action if needed
        VoteParameters storage vP = proposals[id];
        VoteResult result = vP.result;
        if (result == VoteResult.PENDING) { //the result was already known before, we do not need to take action a second time, covers also the result NON_EXISTENT
            VotingStage votingStage = getVotingStage(vP);
            if (votingStage == VotingStage.EXECUTION_HAS_ENDED) {
                result = VoteResult.EXPIRED;
            } else {
                uint256 outstandingShareCount = getOutstandingShareCount();
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

            return true; //the vote result has been updated
        }

        return false; //the vote result has not been updated
    }



    function getVotingStage(VoteParameters storage voteParameters) internal view returns (VotingStage) {
        DecisionParameters storage dP = voteParameters.decisionParameters;
        uint256 votingCutOff = voteParameters.startTime + dP.decisionTime;
        return (block.timestamp <= votingCutOff) ?                    VotingStage.VOTING_IN_PROGRESS
             : (block.timestamp <= votingCutOff + dP.executionTime) ? VotingStage.VOTING_HAS_ENDED
             :                                                        VotingStage.EXECUTION_HAS_ENDED;
    }

    function countVotes(VoteParameters storage voteParameters) internal view returns (uint256, uint256, uint256, uint256) {
        uint256 inFavor = 0;
        uint256 against = 0;
        uint256 abstain = 0;
        uint256 noVote = 0;

        Vote[] storage votes = voteParameters.votes;
        for (uint256 i = 1; i < votes.length; i++) { //the first vote is from this address(this) with VoteChoice.NO_VOTE, ignore this vote
            Vote storage v = votes[i];
            uint256 votingPower = balanceOf(v.voter);
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