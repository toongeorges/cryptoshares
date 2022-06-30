// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import 'contracts/IExchange.sol';
import 'contracts/IShare.sol';
import 'contracts/libraries/PackableAddresses.sol';
import 'contracts/libraries/Voting.sol';

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

    PackInfo private _shareholders;
    mapping(address => PackInfo) private exchanges;

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
            PackableAddresses.register(_shareholders, to);

            uint256 id = pendingRequestId;
            if (id != 0) { //if there is a request pending
                VoteParameters storage vP = getProposal(id);
                VoteResult result = vP.result;
                if (result == VoteResult.PARTIAL_VOTE_COUNT) {
                    Voting.transferVotes(vP, from, to, transferAmount);
                } else if (result == VoteResult.PARTIAL_EXECUTION) {
                    singlePartialExecution(from, to, transferAmount, vP, id);
                }
            }
        }
    }

    function singlePartialExecution(address from, address to, uint256 transferAmount, VoteParameters storage vP, uint256 id) private {
        mapping(address => uint256) storage processed = vP.processedShares;
        uint256 totalProcessed = processed[from];
        uint256 transferredProcessed = (totalProcessed > transferAmount) ? transferAmount : totalProcessed;
        if (totalProcessed > 0) {
            unchecked {
                processed[to] += transferredProcessed;
                processed[from] = totalProcessed - transferredProcessed;
            }
        }
        uint256 index = _shareholders.index[to];
        if (index < vP.processedShareholders) { //if the shareholder has already been processed
            unchecked {
                uint256 transferredUnprocessed = transferAmount - transferredProcessed;
                if (transferredUnprocessed > 0) {
                    doSinglePartialExecution(to, transferredUnprocessed, vP, id, processed);
                }
            }
        }
    }

    function doSinglePartialExecution(address to, uint256 transferredUnprocessed, VoteParameters storage vP, uint256 id, mapping(address => uint256) storage processed) private {
        CorporateActionData storage cA = corporateActionsData[id];

        ActionType decisionType = ActionType(vP.voteType);
        if (decisionType == ActionType.DISTRIBUTE_DIVIDEND) {
            unchecked { processed[to] += transferredUnprocessed; }

            safeTransfer(IERC20(cA.currency), to, transferredUnprocessed*cA.amount);
        } else if (decisionType == ActionType.DISTRIBUTE_OPTIONAL_DIVIDEND) {
            unchecked { processed[to] += transferredUnprocessed; }

            uint256 vIndex = vP.voteIndex[to];
            if ((vIndex > 0) && (vP.votes[vIndex].choice == VoteChoice.IN_FAVOR)) { //the shareholder chose for the optional dividend
                safeTransfer(IERC20(cA.optionalCurrency), to, transferredUnprocessed*cA.optionalAmount); //distribute the optional dividend
            } else {
                safeTransfer(IERC20(cA.currency), to, transferredUnprocessed*cA.amount); //distribute the normal dividend
            }
        } else { //(decisionType == ActionType.REVERSE_SPLIT)
            uint256 reverseSplitRatio = cA.optionalAmount; //or reverse split ratio in the case of a reverse split
            uint256 remainingShares = transferredUnprocessed/reverseSplitRatio;
            unchecked {
                processed[to] += remainingShares;

                //shares have been transferred to the "to" address before the _burn method is called
                //reduce transferredUnprocessed from transferredUnprocessed -> transferredUnprocessed/optionalAmount == transferredUnprocessed - (transferredUnprocessed - transferredUnprocessed/optionalAmount)
                _burn(to, transferredUnprocessed - remainingShares);
            }

            //pay out fractional shares
            uint256 fraction = transferredUnprocessed%reverseSplitRatio;
            if (fraction > 0) {
                safeTransfer(IERC20(cA.currency), to, fraction*cA.amount);
            }
        }
    }



    function getLockedUpAmount(address tokenAddress) public view virtual override returns (uint256) {
        PackInfo storage info = exchanges[tokenAddress];
        address[] storage exchangeAddresses = info.addresses;

        uint256 lockedUpAmount = 0;
        uint256 unpackedIndex = info.unpackedIndex;
        if (unpackedIndex == 0) {
            for (uint256 i = 1; i < info.length;) {
                lockedUpAmount += getLockedUpAmount(exchangeAddresses[i], tokenAddress);
                unchecked { i++; }
            }
        } else {
            for (uint256 i = 1; i < info.packedLength;) {
                lockedUpAmount += getLockedUpAmount(exchangeAddresses[i], tokenAddress);
                unchecked { i++; }
            }
            for (uint256 i = unpackedIndex; i < info.length;) {
                lockedUpAmount += getLockedUpAmount(exchangeAddresses[i], tokenAddress);
                unchecked { i++; }
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
        return PackableAddresses.getCount(exchanges[tokenAddress]);
    }

    function getExchangePackSize(address tokenAddress) external view virtual override returns (uint256) {
        return PackableAddresses.getPackSize(exchanges[tokenAddress]);
    }

    function packExchanges(address tokenAddress, uint256 amountToPack) external virtual override {
        PackableAddresses.pack(exchanges[tokenAddress], amountToPack, tokenAddress, isExchangePredicate);
    }

    function isExchangePredicate(address tokenAddress, address exchange) internal view returns (bool) {
        return (getLockedUpAmount(exchange, tokenAddress) > 0);
    }

    function getShareholderCount() public view virtual override returns (uint256) {
        return PackableAddresses.getCount(_shareholders);
    }

    function getShareholderNumber(address shareholder) external view virtual override returns (uint256) {
        return _shareholders.index[shareholder];
    }

    function getShareholderPackSize() external view virtual override returns (uint256) {
        return PackableAddresses.getPackSize(_shareholders);
    }

    function packShareholders(uint256 amountToPack) external virtual override {
        PackableAddresses.pack(_shareholders, amountToPack, address(0), isShareholder);
    }

    function isShareholder(address, address shareholder) internal view returns (bool) {
        return balanceOf(shareholder) > 0;
    }



    function getNumberOfProposals() external view virtual override returns (uint256) {
        return proposals.length;
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

    function ask(address exchangeAddress, address asset, uint256 assetAmount, address currency, uint256 currencyAmount, uint256 maxOrders) external returns (uint256) {
        verifyAvailable(asset, assetAmount);

        return initiateCorporateAction(ActionType.ASK, maxOrders, exchangeAddress, asset, assetAmount, currency, currencyAmount);
    }

    function bid(address exchangeAddress, address asset, uint256 assetAmount, address currency, uint256 currencyAmount, uint256 maxOrders) external returns (uint256) {
        verifyAvailable(currency, currencyAmount);

        return initiateCorporateAction(ActionType.BID, maxOrders, exchangeAddress, asset, assetAmount, currency, currencyAmount);
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
                uint256 maxEnd = _shareholders.length;
                if (end > maxEnd) {
                    end = maxEnd;
                }

                IERC20 erc20 = IERC20(currencyAddress);

                doFinish(vP, decisionType, start, end, erc20, amountPerShare, optionalCurrencyAddress, optionalAmount);

                vP.processedShareholders = end;

                unchecked{
                    uint shareholdersLeft = maxEnd - end;

                    if (shareholdersLeft == 0) {
                        vP.result = VoteResult.APPROVED;

                        emit CorporateAction(id, VoteResult.APPROVED, decisionType, cA.numberOfShares, address(0), currencyAddress, amountPerShare, optionalCurrencyAddress, optionalAmount);

                        pendingRequestId = 0;
                    }

                    return shareholdersLeft;
                }
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

        address[] storage shareholders = _shareholders.addresses;
        if (decisionType == ActionType.DISTRIBUTE_DIVIDEND) {
            for (uint256 i = start; i < end;) {
                address shareholder = shareholders[i];
                uint256 totalShares = balanceOf(shareholder);
                uint256 unprocessedShares;
                unchecked { unprocessedShares = totalShares - processedShares[shareholder]; }
                if (unprocessedShares > 0) {
                    processedShares[shareholder] = totalShares;
                    safeTransfer(erc20, shareholder, unprocessedShares*amountPerShare);
                }
                unchecked { i++; }
            }
        } else if (decisionType == ActionType.DISTRIBUTE_OPTIONAL_DIVIDEND) {
            IERC20 optionalERC20 = IERC20(optionalCurrencyAddress);

            mapping(address => uint256) storage voteIndex = vP.voteIndex;
            Vote[] storage votes = vP.votes;
            for (uint256 i = start; i < end;) {
                address shareholder = shareholders[i];
                uint256 totalShares = balanceOf(shareholder);
                uint256 unprocessedShares;
                unchecked { unprocessedShares = totalShares - processedShares[shareholder]; }
                if (unprocessedShares > 0) {
                    processedShares[shareholder] = totalShares;
                    uint256 vIndex = voteIndex[shareholder];
                    if ((vIndex > 0) && (votes[vIndex].choice == VoteChoice.IN_FAVOR)) { //the shareholder chose for the optional dividend
                        safeTransfer(optionalERC20, shareholder, unprocessedShares*optionalAmount); //distribute the optional dividend
                    } else {
                        safeTransfer(erc20, shareholder, unprocessedShares*amountPerShare); //distribute the normal dividend
                    }
                }
                unchecked { i++; }
            }
        } else { //(decisionType == ActionType.REVERSE_SPLIT)
            for (uint256 i = start; i < end;) {
                address shareholder = shareholders[i];
                uint256 totalShares = balanceOf(shareholder);
                uint256 processed = processedShares[shareholder];
                uint256 unprocessedShares;
                unchecked { unprocessedShares = totalShares - processed; }
                if (unprocessedShares > 0) {
                    uint256 remainingShares = unprocessedShares/optionalAmount;
                    unchecked {
                        processedShares[shareholder] = processed + remainingShares;

                        //reduce the stake of the shareholder from stake -> stake/optionalAmount == stake - (stake - stake/optionalAmount)
                        _burn(shareholder, unprocessedShares - remainingShares);
                    }

                    //pay out fractional shares
                    uint256 fraction = unprocessedShares%optionalAmount;
                    if (fraction > 0) {
                        safeTransfer(erc20, shareholder, fraction*amountPerShare);
                    }
                }
                unchecked { i++; }
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
 
    function doCorporateAction(uint256 id, VoteResult voteResult, ActionType decisionType, uint256 numberOfShares, address exchangeAddress, address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount) internal returns (bool) {
        bool isFullyExecuted = true;
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
                        PackableAddresses.register(exchanges[address(this)], exchangeAddress);
                        exchange.ask(address(this), numberOfShares, currency, numberOfShares*amount, optionalAmount);
                    } else  { //decisionType == ActionType.BUY_BACK
                        IERC20(currency).safeIncreaseAllowance(exchangeAddress, numberOfShares*amount); //only send to safe exchanges, the total price is locked up
                        PackableAddresses.register(exchanges[currency], exchangeAddress);
                        exchange.bid(currency, numberOfShares*amount, address(this), numberOfShares, optionalAmount);
                    }
                } else {
                    if (decisionType == ActionType.ASK) {
                        IERC20(currency).safeIncreaseAllowance(exchangeAddress, amount); //only send to safe exchanges, the total price is locked up
                        PackableAddresses.register(exchanges[currency], exchangeAddress);
                        exchange.ask(currency, amount, optionalCurrency, optionalAmount, numberOfShares);
                    } else  { //decisionType == ActionType.BID
                        IERC20(optionalCurrency).safeIncreaseAllowance(exchangeAddress, optionalAmount); //only send to safe exchanges, the total price is locked up
                        PackableAddresses.register(exchanges[optionalCurrency], exchangeAddress);
                        exchange.bid(currency, amount, optionalCurrency, optionalAmount, numberOfShares);
                    }
                }
            } else if ((decisionType == ActionType.DISTRIBUTE_DIVIDEND) && (optionalCurrency != address(0))) { //we need to trigger ActionType.DISTRIBUTE_OPTIONAL_DIVIDEND, which requires another vote to either approve or reject the optional dividend
                pendingRequestId = 0; //otherwise we cannot start the optional dividend corporate action

                initiateCorporateAction(ActionType.DISTRIBUTE_OPTIONAL_DIVIDEND, 0, address(0), currency, amount, optionalCurrency, optionalAmount);
                isFullyExecuted = false;
            } else {
                voteResult = VoteResult.PARTIAL_EXECUTION;
                getProposal(id).result = voteResult;
                isFullyExecuted = false;
            }
        }
        
        emit CorporateAction(id, voteResult, decisionType, numberOfShares, exchangeAddress, currency, amount, optionalCurrency, optionalAmount);

        return isFullyExecuted;
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
            VoteParameters storage vP = getProposal(id);

            uint16 decisionType = vP.voteType;
            bool isPartialExecution = (
                (decisionType == uint16(ActionType.REVERSE_SPLIT))
                || ((decisionType == uint16(ActionType.DISTRIBUTE_DIVIDEND)) && (corporateActionsData[id].optionalCurrency == address(0)))
                || (decisionType == uint16(ActionType.DISTRIBUTE_OPTIONAL_DIVIDEND))
            );

            (bool isUpdated, uint256 remainingVotes) = Voting.resolveVote(vP, (decisionType == uint16(ActionType.DISTRIBUTE_OPTIONAL_DIVIDEND)), isPartialExecution, IERC20(this), getOutstandingShareCount(), pageSize);

            if (remainingVotes > 0) {
                return remainingVotes;
            } else if (isUpdated) {
                doResolve(id, vP.voteType, vP.result);

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
            VoteParameters storage vP = getProposal(id);
            if (Voting.withdrawVote(vP)) {
                doResolve(id, vP.voteType, vP.result);
            } else {
                revert RequestNotResolved();
            }
        } else {
            revert NoRequestPending();
        }
    }

    function doResolve(uint256 id, uint16 voteTypeInt, VoteResult voteResult) internal {
        bool isFullyExecuted = true;
        if (voteTypeInt >= uint16(ActionType.EXTERNAL)) {
            doExternalProposal(id);
        } else {
            ActionType voteType = ActionType(voteTypeInt);
            if (voteType > ActionType.CHANGE_DECISION_PARAMETERS) { //this is a corporate action
                CorporateActionData storage cA = corporateActionsData[id];
                isFullyExecuted = doCorporateAction(id, voteResult, ActionType(getProposal(id).voteType), cA.numberOfShares, cA.exchange, cA.currency, cA.amount, cA.optionalCurrency, cA.optionalAmount);
            } else if (voteType == ActionType.CHANGE_DECISION_PARAMETERS) {
                DecisionParameters storage dP = decisionParametersData[id];
                doSetDecisionParameters(id, decisionParametersVoteType[id], dP.decisionTime, dP.executionTime, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator);
            } else if (voteType == ActionType.CHANGE_OWNER) {
                doChangeOwner(id, newOwners[id]);
            } else { //cannot resolve ActionType.DEFAULT, which is not an action
                revert RequestNotResolved();
            }
        }

        if (isFullyExecuted) {
            pendingRequestId = 0;
        }
    }



    function vote(uint256 id, VoteChoice decision) external virtual override {
        Voting.vote(getProposal(id), decision, (balanceOf(msg.sender) > 0));
    }

    function propose(uint16 voteType) internal returns (uint256, bool) {
        uint256 index = proposals.length;
        return (index, Voting.init(proposals.push(), voteType, doGetDecisionParameters(voteType), getOutstandingShareCount()));
    }
}