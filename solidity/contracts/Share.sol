// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import 'contracts/IExchange.sol';
import 'contracts/IShare.sol';

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

struct CorporateActionData { //see the RequestCorporateAction and CorporateAction event in the IShare interface for the meaning of these fields
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
    mapping(uint16 => DecisionParameters) private decisionParameters;
    VoteParameters[] private proposals;

    mapping(uint256 => address) private newOwners;
    mapping(uint256 => uint16) private decisionParametersVoteType;
    mapping(uint256 => DecisionParameters) private decisionParametersData;
    mapping(uint256 => CorporateActionData) private corporateActionsData;

    uint256 public pendingRequestId;

    modifier isOwner() {
        _isOwner(); //putting the code in a fuction reduces the size of the compiled smart contract!
        _;
    }

    function _isOwner() internal view {
        require(msg.sender == owner);
    }

    modifier verifyNoRequestPending() {
        if (pendingRequestId == 0) {
            _;
        } else {
            revert RequestPending();
        }
    }

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        owner = msg.sender;
        shareholders.push(address(this)); //to make later operations on shareholders less costly
        shareholdersLength++;
        proposals.push(); //make sure that the pendingRequestId for any request > 0
    }



    function decimals() public pure virtual override returns (uint8) {
        return 0;
    }

    receive() external payable { //used to receive wei when msg.data is empty
        revert DoNotAcceptEtherPayments();
    }

    fallback() external payable { //used to receive wei when msg.data is not empty
        revert DoNotAcceptEtherPayments();
    }



    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        bool success = super.transfer(to, amount); //has to happen before the registerTransfer method, because shares of the receiver may be burnt in case a reverse split if going on

        registerTransfer(msg.sender, to, amount);

        return success; //should be always true, the base implementation reverts if something goes wrong, however returning the boolean literal "true" increases the size of the compiled contract
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        bool success = super.transferFrom(from, to, amount); //has to happen before the registerTransfer method, because shares of the receiver may be burnt in case a reverse split if going on

        registerTransfer(from, to, amount);

        return success; //should be always true, the base implementation reverts if something goes wrong, however returning the boolean literal "true" increases the size of the compiled contract
    }

    function registerTransfer(address from, address to, uint256 transferAmount) internal {
        if (transferAmount > 0) { //the ERC20 base class seems not to care if amount == 0, though no registration should happen then
            registerShareholder(to);

            uint256 id = pendingRequestId;
            if (id != 0) { //if there is a request pending
                VoteParameters storage vP = getProposal(id);
                VoteResult result = vP.result;
                if (result == VoteResult.PARTIAL_VOTE_COUNT) {
                    updateSingleVote(from, to, transferAmount, vP);
                } else if (result == VoteResult.PARTIAL_EXECUTION) {
                    singlePartialExecution(from, to, transferAmount, vP, id);
                }
            }
        }
    }

    function updateSingleVote(address from, address to, uint256 transferAmount, VoteParameters storage vP) private {
        mapping(address => uint256) storage spentVotes = vP.spentVotes;
        uint256 senderSpent = spentVotes[from];
        uint256 receiverSpent = spentVotes[to];
        uint256 transferredSpentVotes = (senderSpent > transferAmount) ? transferAmount : senderSpent;
        if (transferredSpentVotes > 0) {
            receiverSpent += transferredSpentVotes;
            spentVotes[from] = senderSpent - transferredSpentVotes;
        }
        uint256 voteIndex = vP.voteIndex[to];
        if ((voteIndex > 0) && (voteIndex < vP.countedVotes)) { //if the votes of the receiver have already been counted
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
        spentVotes[to] = receiverSpent;
    }

    function singlePartialExecution(address from, address to, uint256 transferAmount, VoteParameters storage vP, uint256 id) private {
        mapping(address => uint256) storage processed = vP.processedShares;
        uint256 totalProcessed = processed[from];
        uint256 transferredProcessed = (totalProcessed > transferAmount) ? transferAmount : totalProcessed;
        if (totalProcessed > 0) {
            processed[to] += transferredProcessed;
            processed[from] = totalProcessed - transferredProcessed;
        }
        uint256 index = shareholderIndex[to];
        if (index < vP.processedShareholders) { //if the shareholder has already been processed
            uint256 transferredUnprocessed = transferAmount - transferredProcessed;
            if (transferredUnprocessed > 0) {
                doSinglePartialExecution(to, transferredUnprocessed, vP, id, processed);
            }
        }
    }

    function doSinglePartialExecution(address to, uint256 transferredUnprocessed, VoteParameters storage vP, uint256 id, mapping(address => uint256) storage processed) private {
        CorporateActionData storage cA = corporateActionsData[id];

        ActionType decisionType = ActionType(vP.voteType);
        if (decisionType == ActionType.DISTRIBUTE_DIVIDEND) {
            processed[to] += transferredUnprocessed;

            safeTransfer(IERC20(cA.currency), to, transferredUnprocessed*cA.amount);
        } else if (decisionType == ActionType.DISTRIBUTE_OPTIONAL_DIVIDEND) {
            uint256 vIndex = vP.voteIndex[to];
            if ((vIndex > 0) && (vP.votes[vIndex].choice == VoteChoice.IN_FAVOR)) { //the shareholder chose for the optional dividend
                safeTransfer(IERC20(cA.optionalCurrency), to, transferredUnprocessed*cA.optionalAmount); //distribute the optional dividend
            } else {
                safeTransfer(IERC20(cA.currency), to, transferredUnprocessed*cA.amount); //distribute the normal dividend
            }
        } else { //(decisionType == ActionType.REVERSE_SPLIT)
            uint256 reverseSplitRatio = cA.optionalAmount; //or reverse split ratio in the case of a reverse split
            uint256 remainingShares = transferredUnprocessed/reverseSplitRatio;
            processed[to] += remainingShares;

            //shares have been transferred to the "to" address before the _burn method is called
            //reduce transferredUnprocessed from transferredUnprocessed -> transferredUnprocessed/optionalAmount == transferredUnprocessed - (transferredUnprocessed - transferredUnprocessed/optionalAmount)
            _burn(to, transferredUnprocessed - remainingShares);

            //pay out fractional shares
            uint256 fraction = transferredUnprocessed%reverseSplitRatio;
            if (fraction > 0) {
                safeTransfer(IERC20(cA.currency), to, fraction*cA.amount);
            }
        }
    }



    function getLockedUpAmount(address tokenAddress) public view virtual override returns (uint256) {
        ExchangeInfo storage info = exchangeInfo[tokenAddress];
        address[] storage exchanges = info.exchanges;

        uint256 lockedUpAmount = 0;
        uint256 unpackedIndex = info.unpackedIndex;
        if (unpackedIndex == 0) {
            for (uint256 i = 0; i < info.exchangesLength; i++) {
                lockedUpAmount += getLockedUpAmount(exchanges[i], tokenAddress);
            }
        } else {
            for (uint256 i = 0; i < info.packedLength; i++) {
                lockedUpAmount += getLockedUpAmount(exchanges[i], tokenAddress);
            }
            for (uint256 i = unpackedIndex; i < info.exchangesLength; i++) {
                lockedUpAmount += getLockedUpAmount(exchanges[i], tokenAddress);
            }
        }
        return lockedUpAmount;
    }

    function getLockedUpAmount(address exchangeAddress, address tokenAddress) internal view returns (uint256) {
        return IExchange(exchangeAddress).getLockedUpAmount(tokenAddress);
    }

    function getAvailableAmount(address tokenAddress) public view virtual override returns (uint256) {
        return IERC20(tokenAddress).balanceOf(address(this)) - getLockedUpAmount(tokenAddress);
    }

    function getTreasuryShareCount() public view virtual override returns (uint256) { //return the number of shares held by the company
        return balanceOf(address(this)) - getLockedUpAmount(address(this));
    }

    function getOutstandingShareCount() public view virtual override returns (uint256) { //return the number of shares not held by the company
        return totalSupply() - balanceOf(address(this));
    }

    //getMaxOutstandingShareCount() >= getOutstandingShareCount(), we are also counting the shares that have been locked up in exchanges and may be sold
    function getMaxOutstandingShareCount() public view virtual override returns (uint256) {
        return totalSupply() - getTreasuryShareCount();
    }



    function getExchangeCount(address tokenAddress) external view virtual override returns (uint256) {
        return exchangeInfo[tokenAddress].exchangesLength;        
    }

    function getExchangePackSize(address tokenAddress) external view virtual override returns (uint256) {
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

    function packExchanges(address tokenAddress, uint256 amountToPack) external virtual override {
        require(amountToPack > 0);

        ExchangeInfo storage info = exchangeInfo[tokenAddress];

        uint256 start = info.unpackedIndex;
        uint256 end = start + amountToPack;
        uint256 maxEnd = info.exchangesLength;
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
        for (uint256 i = start; i < end; i++) {
            address exchange = exchanges[i];
            if (getLockedUpAmount(exchange, tokenAddress) > 0) { //only register if the exchange still has locked up tokens
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

    function getShareholderCount() public view virtual override returns (uint256) {
        return shareholdersLength - 1; //the first address is taken by this contract, which is not a shareholder
    }

    function getShareholderNumber(address shareholder) external view virtual override returns (uint256) {
        return shareholderIndex[shareholder];
    }

    function registerShareholder(address shareholder) internal {
        uint256 index = shareholderIndex[shareholder];
        if (index == 0) { //the shareholder has not been registered yet (the address at index 0 is this contract)
            index = shareholdersLength;
            shareholderIndex[shareholder] = index;
            if (index < shareholders.length) {
                shareholders[index] = shareholder;
            } else {
                shareholders.push(shareholder);
            }
            shareholdersLength++;
        }
    }

    function getShareholderPackSize() external view virtual override returns (uint256) {
        return (unpackedShareholderIndex == 0) ? getShareholderCount() : (shareholdersLength - unpackedShareholderIndex);
    }

    function packShareholders(uint256 amountToPack) external virtual override {
        require(amountToPack > 0);

        uint256 start = unpackedShareholderIndex;

        uint256 packedIndex;
        if (start == 0) { //start a new packing
            start = 1; //keep address(this) as the first entry in the shareholders array (to simplify later calculations)
            packedIndex = 1;
        } else {
            packedIndex = packedShareholdersLength;
        }

        uint256 end = start + amountToPack;
        uint256 maxEnd = shareholdersLength;
        if (end > maxEnd) {
            end = maxEnd;
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



    function getNumberOfProposals() external view virtual override returns (uint256) {
        return proposals.length;
    }

    function getDecisionParameters(uint256 id) external view virtual override returns (uint16, uint64, uint64, uint32, uint32, uint32, uint32) {
        VoteParameters storage vP = getProposal(id);
        DecisionParameters storage dP = vP.decisionParameters;
        return (vP.voteType, dP.decisionTime, dP.executionTime, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator);
    }

    function getDecisionTimes(uint256 id) external view virtual override returns (uint64, uint64, uint64) {
        VoteParameters storage vP = getProposal(id);
        DecisionParameters storage dP = vP.decisionParameters;

        uint64 startTime = vP.startTime;
        uint64 decisionTime = startTime + dP.decisionTime;
        uint64 executionTime = decisionTime + dP.executionTime;

        return (startTime, decisionTime, executionTime);
    }

    function getNumberOfVotes(uint256 id) public view virtual override returns (uint256) {
        return (getProposal(id).votes.length - 1); //the vote at index 0 is from address(this) with VoteChoice.NO_VOTE and is ignored
    }

    function getDetailedVoteResult(uint256 id) external view virtual override returns (VoteResult, uint32, uint32, uint32, uint32, uint256, uint256, uint256, uint256) {
        VoteParameters storage vP = getProposal(id);
        DecisionParameters storage dP = vP.decisionParameters;
        VoteResult result = vP.result;
        return isExpired(result, vP)                     ? (VoteResult.EXPIRED, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator, 0, 0, 0, 0) :
               (result == VoteResult.PARTIAL_VOTE_COUNT) ? (VoteResult.PARTIAL_VOTE_COUNT, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator, 0, 0, 0, 0) :
                                                           (result, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator, vP.inFavor, vP.against, vP.abstain, vP.noVote);
    }

    function getVoteResult(uint256 id) external view virtual override returns (VoteResult) {
        VoteParameters storage vP = getProposal(id);
        VoteResult result = vP.result;
        return isExpired(result, vP) ? VoteResult.EXPIRED : result;
    }

    function isExpired(VoteResult result, VoteParameters storage vP) internal view returns (bool) {
        return (result == VoteResult.PENDING) && (getVotingStage(vP) == VotingStage.EXECUTION_HAS_ENDED);
    }

    function getProposal(uint256 id) internal view returns (VoteParameters storage) { //reduces the size of the compiled contract when this is wrapped in a function
        return proposals[id];
    }



    function getProposedOwner(uint256 id) external view virtual override returns (address) {
        return newOwners[id];
    }

    function getProposedDecisionParameters(uint256 id) external view virtual override returns (uint16, uint64, uint64, uint32, uint32, uint32, uint32) {
        DecisionParameters storage dP = decisionParametersData[id];
        return (decisionParametersVoteType[id], dP.decisionTime, dP.executionTime, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator);
    }

    function getProposedCorporateAction(uint256 id) external view virtual override returns (ActionType, uint256, address, address, uint256, address, uint256) {
        CorporateActionData storage cA = corporateActionsData[id];
        return (ActionType(getProposal(id).voteType), cA.numberOfShares, cA.exchange, cA.currency, cA.amount, cA.optionalCurrency, cA.optionalAmount);
    }



    function makeExternalProposal() external virtual override returns (uint256) {
        return makeExternalProposal(0);
    }

    function makeExternalProposal(uint16 subType) public virtual override isOwner verifyNoRequestPending returns (uint256) {
        (uint256 id, bool noSharesOutstanding) = propose(uint16(ActionType.EXTERNAL) + subType);

        if (noSharesOutstanding) {
            doExternalProposal(id);
        } else {
            pendingRequestId = id;

            emit RequestExternalProposal(id);
        }

        return id;
    }

    function doExternalProposal(uint256 id) internal {
        emit ExternalProposal(id, getProposal(id).result);
    }



    function changeOwner(address newOwner) external virtual override isOwner verifyNoRequestPending returns (uint256) {
        (uint256 id, bool noSharesOutstanding) = propose(uint16(ActionType.CHANGE_OWNER));

        newOwners[id] = newOwner;

        if (noSharesOutstanding) {
            doChangeOwner(id, newOwner);
        } else {
            pendingRequestId = id;

            emit RequestChangeOwner(id, newOwner);
        }

        return id;
    }

    function doChangeOwner(uint256 id, address newOwner) internal {
        VoteResult voteResult = getProposal(id).result;

        if (isApproved(voteResult)) {
            owner = newOwner;
        }

        emit ChangeOwner(id, voteResult, newOwner);
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

    function changeDecisionParameters(ActionType voteType, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) external virtual override returns (uint256) {
        return doChangeDecisionParameters(uint16(voteType), decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
    }

    function changeExternalProposalDecisionParameters(uint16 subType, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) external virtual override returns (uint256) {
        return doChangeDecisionParameters(uint16(ActionType.EXTERNAL) + subType, decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
    }

    function doChangeDecisionParameters(uint16 voteType, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) internal isOwner verifyNoRequestPending returns (uint256) {
        require(quorumDenominator > 0);
        require(majorityDenominator > 0);
        require((majorityNumerator << 1) >= majorityDenominator);

        (uint256 id, bool noSharesOutstanding) = propose(uint16(ActionType.CHANGE_DECISION_PARAMETERS));

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
            pendingRequestId = id;

            emit RequestChangeDecisionParameters(id, voteType, decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
        }

        return id;
    }

    function doSetDecisionParameters(uint256 id, uint16 voteType, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) internal {
        VoteResult voteResult = getProposal(id).result;

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



    function issueShares(uint256 numberOfShares) external virtual override returns (uint256) {
        return initiateCorporateAction(ActionType.ISSUE_SHARES, numberOfShares, address(0), address(0), 0, address(0), 0);
    }

    function destroyShares(uint256 numberOfShares) external virtual override returns (uint256) {
        require(getTreasuryShareCount() >= numberOfShares);

        return initiateCorporateAction(ActionType.DESTROY_SHARES, numberOfShares, address(0), address(0), 0, address(0), 0);
    }

    function withdrawFunds(address destination, address currency, uint256 amount) external virtual override returns (uint256) {
        verifyAvailable(currency, amount);

        return initiateCorporateAction(ActionType.WITHDRAW_FUNDS, 0, destination, currency, amount, address(0), 0);
    }

    function cancelOrder(address exchangeAddress, uint256 orderId) external virtual override returns (uint256) {
        return initiateCorporateAction(ActionType.CANCEL_ORDER, 0, exchangeAddress, address(0), orderId, address(0), 0);
    }

    function raiseFunds(address exchangeAddress, uint256 numberOfShares, address currency, uint256 price, uint256 maxOrders) external virtual override returns (uint256) {
        require(getTreasuryShareCount() >= numberOfShares);

        return initiateCorporateAction(ActionType.RAISE_FUNDS, numberOfShares, exchangeAddress, currency, price, address(0), maxOrders);
    }

    function buyBack(address exchangeAddress, uint256 numberOfShares, address currency, uint256 price, uint256 maxOrders) external virtual override returns (uint256) {
        verifyAvailable(currency, numberOfShares*price);

        return initiateCorporateAction(ActionType.BUY_BACK, numberOfShares, exchangeAddress, currency, price, address(0), maxOrders);
    }

    function ask(address exchangeAddress, address offer, uint256 offerRatio, address request, uint256 requestRatio, uint256 amountOfSwaps) external returns (uint256) {
        verifyAvailable(offer, offerRatio*amountOfSwaps);

        return initiateCorporateAction(ActionType.ASK, amountOfSwaps, exchangeAddress, offer, offerRatio, request, requestRatio);
    }

    function bid(address exchangeAddress, address offer, uint256 offerRatio, address request, uint256 requestRatio, uint256 amountOfSwaps) external returns (uint256) {
        verifyAvailable(offer, offerRatio*amountOfSwaps);

        return initiateCorporateAction(ActionType.BID, amountOfSwaps, exchangeAddress, offer, offerRatio, request, requestRatio);
    }



    function startReverseSplit(uint256 reverseSplitToOne, address currency, uint256 amount) external virtual override returns (uint256) {
        require(getLockedUpAmount(address(this)) == 0); //do not start a reverse split if some exchanges may still be selling shares, cancel these orders first
        verifyAvailable(currency, getOutstandingShareCount()*amount); //possible worst case if everyone owns 1 share, this is not a restriction, we can always distribute a dummy token that has a higher supply than this share and have a bid order for this dummy token on an exchange

        return initiateCorporateAction(ActionType.REVERSE_SPLIT, 0, address(0), currency, amount, address(0), reverseSplitToOne);
    }

    function startDistributeDividend(address currency, uint256 amount) external virtual override returns (uint256) {
        uint256 maxOutstandingShareCount = getMaxOutstandingShareCount();
        verifyAvailable(currency, maxOutstandingShareCount*amount);

        return initiateCorporateAction(ActionType.DISTRIBUTE_DIVIDEND, maxOutstandingShareCount, address(0), currency, amount, address(0), 0);
    }
 
    function startDistributeOptionalDividend(address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount) external virtual override returns (uint256) {
        require(optionalCurrency != address(0));
        uint256 maxOutstandingShareCount = getMaxOutstandingShareCount();
        verifyAvailable(currency, maxOutstandingShareCount*amount);
        verifyAvailable(optionalCurrency, maxOutstandingShareCount*optionalAmount);

        return initiateCorporateAction(ActionType.DISTRIBUTE_DIVIDEND, maxOutstandingShareCount, address(0), currency, amount, optionalCurrency, optionalAmount);
    }

    function finish() external virtual override {
        finish(getShareholderCount());
    }

    function finish(uint256 pageSize) public virtual override returns (uint256) {
        uint256 id = pendingRequestId;
        if (id != 0) {
            VoteParameters storage vP = getProposal(id);
            if (vP.result == VoteResult.PARTIAL_EXECUTION) {
                ActionType decisionType = ActionType(vP.voteType);

                CorporateActionData memory cA = corporateActionsData[id];
                address currencyAddress = cA.currency;
                uint256 amountPerShare = cA.amount;
                address optionalCurrencyAddress = cA.optionalCurrency;
                uint256 optionalAmount = cA.optionalAmount; //or reverse split ratio in the case of a reverse split

                uint256 start = vP.processedShareholders;
                if (start == 0) {
                    start = 1; //the first entry in shareholders is address(this), which should not receive a dividend

                    if (decisionType == ActionType.REVERSE_SPLIT) { //it should however still undergo a reverse split
                        uint256 stake = balanceOf(address(this));
                        //reduce the treasury shares from stake -> stake/reverseSplitRatio == stake - (stake - stake/reverseSplitRatio)
                        _burn(address(this), stake - (stake/optionalAmount));
                    }
                }

                uint256 end = start + pageSize;
                uint256 maxEnd = shareholdersLength;
                if (end > maxEnd) {
                    end = maxEnd;
                }

                IERC20 erc20 = IERC20(currencyAddress);

                doFinish(vP, decisionType, start, end, erc20, amountPerShare, optionalCurrencyAddress, optionalAmount);

                vP.processedShareholders = end;

                uint shareholdersLeft = maxEnd - end;

                if (shareholdersLeft == 0) {
                    vP.result = VoteResult.APPROVED;

                    emit CorporateAction(id, VoteResult.APPROVED, decisionType, cA.numberOfShares, address(0), currencyAddress, amountPerShare, optionalCurrencyAddress, optionalAmount);

                    pendingRequestId = 0;
                }

                return shareholdersLeft;
            } else {
                revert CannotFinish();
            }
        } else {
            revert NoRequestPending();
        }
    }

    //because if inline in finish function: CompilerError: Stack too deep, try removing local variables.
    function doFinish(VoteParameters storage vP, ActionType decisionType, uint256 start, uint256 end, IERC20 erc20, uint256 amountPerShare, address optionalCurrencyAddress, uint256 optionalAmount) private {
        mapping(address => uint256) storage processedShares = vP.processedShares;

        if (decisionType == ActionType.DISTRIBUTE_DIVIDEND) {
            for (uint256 i = start; i < end; i++) {
                address shareholder = shareholders[i];
                uint256 totalShares = balanceOf(shareholder);
                uint256 unprocessedShares = totalShares - processedShares[shareholder];
                if (unprocessedShares > 0) {
                    processedShares[shareholder] = totalShares;
                    safeTransfer(erc20, shareholder, unprocessedShares*amountPerShare);
                }
            }
        } else if (decisionType == ActionType.DISTRIBUTE_OPTIONAL_DIVIDEND) {
            IERC20 optionalERC20 = IERC20(optionalCurrencyAddress);

            mapping(address => uint256) storage voteIndex = vP.voteIndex;
            Vote[] storage votes = vP.votes;
            for (uint256 i = start; i < end; i++) {
                address shareholder = shareholders[i];
                uint256 totalShares = balanceOf(shareholder);
                uint256 unprocessedShares = totalShares - processedShares[shareholder];
                if (unprocessedShares > 0) {
                    processedShares[shareholder] = totalShares;
                    uint256 vIndex = voteIndex[shareholder];
                    if ((vIndex > 0) && (votes[vIndex].choice == VoteChoice.IN_FAVOR)) { //the shareholder chose for the optional dividend
                        safeTransfer(optionalERC20, shareholder, unprocessedShares*optionalAmount); //distribute the optional dividend
                    } else {
                        safeTransfer(erc20, shareholder, unprocessedShares*amountPerShare); //distribute the normal dividend
                    }
                }
            }
        } else { //(decisionType == ActionType.REVERSE_SPLIT)
            for (uint256 i = start; i < end; i++) {
                address shareholder = shareholders[i];
                uint256 totalShares = balanceOf(shareholder);
                uint256 processed = processedShares[shareholder];
                uint256 unprocessedShares = totalShares - processed;
                if (unprocessedShares > 0) {
                    uint256 remainingShares = unprocessedShares/optionalAmount;
                    processedShares[shareholder] = processed + remainingShares;

                    //reduce the stake of the shareholder from stake -> stake/optionalAmount == stake - (stake - stake/optionalAmount)
                    _burn(shareholder, unprocessedShares - remainingShares);

                    //pay out fractional shares
                    uint256 fraction = unprocessedShares%optionalAmount;
                    if (fraction > 0) {
                        safeTransfer(erc20, shareholder, fraction*amountPerShare);
                    }
                }
            }
        }
    }



    function initiateCorporateAction(ActionType decisionType, uint256 numberOfShares, address exchangeAddress, address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount) internal isOwner verifyNoRequestPending returns (uint256) {
        (uint256 id, bool noSharesOutstanding) = propose(uint16(decisionType));

        CorporateActionData storage corporateAction = corporateActionsData[id];
        corporateAction.numberOfShares = (numberOfShares != 0) ? numberOfShares : getMaxOutstandingShareCount();
        corporateAction.exchange = exchangeAddress;
        corporateAction.currency = currency;
        corporateAction.amount = amount;
        corporateAction.optionalCurrency = optionalCurrency;
        corporateAction.optionalAmount = optionalAmount;

        if (noSharesOutstanding) {
            doCorporateAction(id, VoteResult.NO_OUTSTANDING_SHARES, decisionType, numberOfShares, exchangeAddress, currency, amount, optionalCurrency, optionalAmount);
        } else {
            pendingRequestId = id;

            emit RequestCorporateAction(id, decisionType, numberOfShares, exchangeAddress, currency, amount, optionalCurrency, optionalAmount);
        }

        return id;
    }
 
    function doCorporateAction(uint256 id, VoteResult voteResult, ActionType decisionType, uint256 numberOfShares, address exchangeAddress, address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount) internal {
        if (isApproved(voteResult)) {
            if (decisionType < ActionType.RAISE_FUNDS) {
                if (decisionType < ActionType.WITHDRAW_FUNDS) {
                    if (decisionType == ActionType.ISSUE_SHARES) {
                        _mint(address(this), numberOfShares);
                    } else { //decisionType == ActionType.DESTROY_SHARES
                        _burn(address(this), numberOfShares);
                    }
                } else {
                    if (decisionType == ActionType.WITHDRAW_FUNDS) {
                        safeTransfer(IERC20(currency), exchangeAddress, amount); //we have to transfer, we cannot work with safeIncreaseAllowance, because unlike an exchange, which we can choose, we have no control over how the currency will be spent
                    } else { //decisionType == ActionType.CANCEL_ORDER
                        IExchange(exchangeAddress).cancel(amount); //the amount field is used to store the order id since it is of the same type
                    }
                }
            } else if (decisionType < ActionType.REVERSE_SPLIT) {
                IExchange exchange = IExchange(exchangeAddress);
                if (decisionType < ActionType.ASK) {
                    if (decisionType == ActionType.RAISE_FUNDS) {
                        increaseAllowance(exchangeAddress, numberOfShares); //only send to safe exchanges, the number of shares are removed from treasury
                        registerExchange(exchangeAddress, address(this));
                        exchange.ask(address(this), numberOfShares, currency, numberOfShares*amount, optionalAmount);
                    } else  { //decisionType == ActionType.BUY_BACK
                        IERC20(currency).safeIncreaseAllowance(exchangeAddress, numberOfShares*amount); //only send to safe exchanges, the total price is locked up
                        registerExchange(exchangeAddress, currency);
                        exchange.bid(currency, numberOfShares*amount, address(this), numberOfShares, optionalAmount);
                    }
                } else {
                    if (decisionType == ActionType.ASK) {
                        IERC20(currency).safeIncreaseAllowance(exchangeAddress, numberOfShares*amount); //only send to safe exchanges, the total price is locked up
                        registerExchange(exchangeAddress, currency);
                        exchange.ask(currency, amount, optionalCurrency, optionalAmount, numberOfShares);
                    } else  { //decisionType == ActionType.BID
                        IERC20(currency).safeIncreaseAllowance(exchangeAddress, numberOfShares*amount); //only send to safe exchanges, the total price is locked up
                        registerExchange(exchangeAddress, currency);
                        exchange.bid(currency, amount, optionalCurrency, optionalAmount, numberOfShares);
                    }
                }
            } else {
                revert CannotExecuteAtOnce();
            }
        }

        emit CorporateAction(id, voteResult, decisionType, numberOfShares, exchangeAddress, currency, amount, optionalCurrency, optionalAmount);
    }



    function isApproved(VoteResult voteResult) internal pure returns (bool) {
        return ((voteResult == VoteResult.APPROVED) || (voteResult == VoteResult.NO_OUTSTANDING_SHARES));
    }

    function verifyAvailable(address currency, uint256 amount) internal view {
        require(getAvailableAmount(currency) >= amount);
    }

    function safeTransfer(IERC20 token, address destination, uint256 amount) internal { //reduces the size of the compiled smart contract if this is wrapped in a function
        token.safeTransfer(destination, amount);
    }



    //preferably resolve the vote at once, so voters can not trade shares during the resolution
    function resolveVote() public virtual override {
        resolveVote(getNumberOfVotes(pendingRequestId));
    }

    //if a vote has to be resolved in multiple times, because a gas limit prevents doing it at once, only allow the owner to do so
    function resolveVote(uint256 pageSize) public virtual override returns (uint256) {
        uint256 id = pendingRequestId;
        if (id != 0) {
            (bool isUpdated, uint256 remainingVotes) = resolveVote(id, pageSize);

            if (remainingVotes > 0) {
                return remainingVotes;
            } else if (isUpdated) {
                doResolve(id);

                return remainingVotes;
            } else {
                revert RequestNotResolved();
            }
        } else {
            revert NoRequestPending();
        }
    }

    function withdrawVote() external virtual override isOwner {
        uint256 id = pendingRequestId;
        if (id != 0) {
            if (withdrawVote(id)) {
                doResolve(id);
            } else {
                revert RequestNotResolved();
            }
        } else {
            revert NoRequestPending();
        }
    }

    function doResolve(uint256 id) internal {
        uint16 voteTypeInt = getProposal(id).voteType;
        if (voteTypeInt >= uint16(ActionType.EXTERNAL)) {
            doExternalProposal(id);
        } else {
            ActionType voteType = ActionType(voteTypeInt);
            if (voteType > ActionType.CHANGE_DECISION_PARAMETERS) { //this is a corporate action
                VoteResult voteResult = getProposal(id).result;

                CorporateActionData storage cA = corporateActionsData[id];
                address currency = cA.currency;
                uint256 amount = cA.amount;
                address optionalCurrency = cA.optionalCurrency;
                uint256 optionalAmount = cA.optionalAmount;

                //special cases, these need to be executed partially, because we have to iterate over all shareholders and this may not be possible in a single transaction
                if ((voteType >= ActionType.REVERSE_SPLIT) && isApproved(voteResult)) { // && (voteType <= ActionType.DISTRIBUTE_OPTIONAL_DIVIDEND) is already implied
                    if ((voteType == ActionType.DISTRIBUTE_DIVIDEND) && (optionalCurrency != address(0))) { //we need to trigger ActionType.DISTRIBUTE_OPTIONAL_DIVIDEND, which requires another vote to either approve or reject the optional dividend
                        pendingRequestId = 0; //otherwise we cannot start the optional dividend corporate action

                        initiateCorporateAction(ActionType.DISTRIBUTE_OPTIONAL_DIVIDEND, 0, address(0), currency, amount, optionalCurrency, optionalAmount);
                    } else { //do not set pendingRequestId = 0, instead set the result to VoteResult.PARTIAL_EXECUTION
                        getProposal(id).result = VoteResult.PARTIAL_EXECUTION;
                    }

                    return; //do not let the pendingRequestId be set to 0 again, since these corporate actions are not finished yet, we still need to iterate over the shareholders
                } else {
                    doCorporateAction(id, voteResult, ActionType(getProposal(id).voteType), cA.numberOfShares, cA.exchange, currency, amount, optionalCurrency, optionalAmount);
                }
            } else if (voteType == ActionType.CHANGE_DECISION_PARAMETERS) {
                DecisionParameters storage dP = decisionParametersData[id];
                doSetDecisionParameters(id, decisionParametersVoteType[id], dP.decisionTime, dP.executionTime, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator);
            } else if (voteType == ActionType.CHANGE_OWNER) {
                doChangeOwner(id, newOwners[id]);
            } else { //cannot resolve ActionType.DEFAULT, which is not an action
                revert RequestNotResolved();
            }
        }

        pendingRequestId = 0;
    }



    function vote(uint256 id, VoteChoice decision) external virtual override {
        VoteParameters storage vP = getProposal(id);
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

    function propose(uint16 voteType) internal returns (uint256, bool) {
        DecisionParameters storage dP = doGetDecisionParameters(voteType);
        uint256 index = proposals.length;
        VoteParameters storage vP = proposals.push();
        vP.startTime = uint64(block.timestamp); // 500 000 000 000 years is more than enough, save some storage space
        vP.voteType = voteType;
        vP.decisionParameters = dP; //copy by value
        vP.countedVotes = 1; //the first vote is from this address(this) with VoteChoice.NO_VOTE, ignore this vote
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
        VoteParameters storage vP = getProposal(id);
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

    function resolveVote(uint256 id, uint256 pageSize) internal returns (bool, uint256) {
        VoteParameters storage vP = getProposal(id);
        uint256 remainingVotes = 0;
        VoteResult result = vP.result;
        if (result == VoteResult.PARTIAL_VOTE_COUNT) {
            (remainingVotes, result) = countAndVerifyVotes(vP, pageSize);

            if (remainingVotes == 0) {
                vP.result = result;
            }

            return (true, remainingVotes); //the result field itself has not been updated if remainingVotes > 0, but votes have been counted
        } else if (result == VoteResult.PENDING) { //the result was already known before, we do not need to take action a second time, covers also the result NON_EXISTENT
            VotingStage votingStage = getVotingStage(vP);
            if (votingStage == VotingStage.EXECUTION_HAS_ENDED) {
                result = VoteResult.EXPIRED;
            } else {
                if (getOutstandingShareCount() == 0) { //if somehow all shares have been bought back, then approve
                    result = VoteResult.APPROVED;
                } else if (votingStage == VotingStage.VOTING_IN_PROGRESS) { //do nothing, wait for voting to end
                    return (false, 0);
                } else if (ActionType(vP.voteType) == ActionType.DISTRIBUTE_OPTIONAL_DIVIDEND) {
                    //this was approved for ActionType.DISTRIBUTE_DIVIDEND, nothing to approve anymore,
                    //a vote only serves to see which option the shareholder prefers
                    result = VoteResult.APPROVED;
                } else { //votingStage == VotingStage.VOTING_HAS_ENDED
                    (remainingVotes, result) = countAndVerifyVotes(vP, pageSize);
                }
            }

            vP.result = result;

            return (true, remainingVotes); //the vote result has been updated
        }

        return (false, 0); //the vote result has not been updated
    }



    function getVotingStage(VoteParameters storage voteParameters) internal view returns (VotingStage) {
        DecisionParameters storage dP = voteParameters.decisionParameters;
        uint256 votingCutOff = voteParameters.startTime + dP.decisionTime;
        return (block.timestamp <= votingCutOff) ?                    VotingStage.VOTING_IN_PROGRESS
             : (block.timestamp <= votingCutOff + dP.executionTime) ? VotingStage.VOTING_HAS_ENDED
             :                                                        VotingStage.EXECUTION_HAS_ENDED;
    }

    function countAndVerifyVotes(VoteParameters storage vP, uint256 pageSize) internal returns (uint256, VoteResult) {
        uint256 remainingVotes = countVotes(vP, pageSize);

        if (remainingVotes == 0) {
            DecisionParameters storage dP = vP.decisionParameters;
            return (remainingVotes, verifyVotes(dP, vP.inFavor, vP.against, vP.abstain)); //either REJECTED or APPROVED
        } else {
            return (remainingVotes, VoteResult.PARTIAL_VOTE_COUNT);
        }
    }
    
    function countVotes(VoteParameters storage voteParameters, uint256 pageSize) internal returns (uint256) {
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
        for (uint256 i = start; i < end; i++) {
            Vote storage v = votes[i];
            address voter = v.voter;
            uint256 totalVotingPower = balanceOf(voter);
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
        }

        voteParameters.countedVotes = end;

        voteParameters.inFavor = inFavor;
        voteParameters.against = against;
        voteParameters.abstain = abstain;
        voteParameters.noVote = noVote;

        return maxEnd - end;
    }

    function verifyVotes(DecisionParameters storage dP, uint256 inFavor, uint256 against, uint256 abstain) internal view returns (VoteResult) {
        //first verify simple majority (the easiest calculation)
        if (against >= inFavor) {
            return VoteResult.REJECTED;
        }

        //then verify if the quorum is met
        if (!isQuorumMet(dP.quorumNumerator, dP.quorumDenominator, inFavor + against + abstain, getOutstandingShareCount())) {
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