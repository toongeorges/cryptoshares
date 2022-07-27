// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import 'contracts/base/Packable.sol';

abstract contract CorporateActions is Packable {
    using SafeERC20 for IERC20;

    mapping(uint256 => CorporateActionData) private corporateActionsData;



    function transferCorporateActionExecution(address from, address to, uint256 transferAmount, VoteParameters storage vP, uint256 id) internal {
        mapping(address => uint256) storage processed = vP.processedShares;
        uint256 totalProcessed = processed[from];
        uint256 transferredProcessed = (totalProcessed > transferAmount) ? transferAmount : totalProcessed;
        if (totalProcessed > 0) {
            unchecked {
                processed[to] += transferredProcessed;
                processed[from] = totalProcessed - transferredProcessed;
            }
        }
        uint256 index = shareholders.index[to];
        if (index < vP.processedShareholders) { //if the shareholder has already been processed
            unchecked {
                uint256 transferredUnprocessed = transferAmount - transferredProcessed;
                if (transferredUnprocessed > 0) {
                    CorporateActionData storage cA = corporateActionsData[id];
                    ActionType decisionType = ActionType(vP.voteType);
                    if (decisionType == ActionType.DISTRIBUTE_DIVIDEND) {
                        transferDistributeDividend(cA, to, transferredUnprocessed, processed);
                    } else if (decisionType == ActionType.DISTRIBUTE_OPTIONAL_DIVIDEND) {
                        transferDistributeOptionalDividend(vP, cA, to, transferredUnprocessed, processed);
                    } else { //(decisionType == ActionType.REVERSE_SPLIT)
                        transferReverseSplit(cA, to, transferredUnprocessed, processed);
                    }
                }
            }
        }
    }

    function transferDistributeDividend(CorporateActionData storage cA, address to, uint256 transferredUnprocessed, mapping(address => uint256) storage processed) private {
        unchecked { processed[to] += transferredUnprocessed; }

        safeTransfer(IERC20(cA.currency), to, transferredUnprocessed*cA.amount);
    }

    function transferDistributeOptionalDividend(VoteParameters storage vP, CorporateActionData storage cA, address to, uint256 transferredUnprocessed, mapping(address => uint256) storage processed) private {
        unchecked { processed[to] += transferredUnprocessed; }

        uint256 vIndex = vP.voteIndex[to];
        if ((vIndex > 0) && (vP.votes[vIndex].choice == VoteChoice.IN_FAVOR)) { //the shareholder chose for the optional dividend
            safeTransfer(IERC20(cA.optionalCurrency), to, transferredUnprocessed*cA.optionalAmount); //distribute the optional dividend
        } else {
            safeTransfer(IERC20(cA.currency), to, transferredUnprocessed*cA.amount); //distribute the normal dividend
        }
    }

    function transferReverseSplit(CorporateActionData storage cA, address to, uint256 transferredUnprocessed, mapping(address => uint256) storage processed) private {
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



    function getProposedCorporateAction(uint256 id) external view virtual override returns (ActionType, uint256, address, uint256, address, uint256) {
        CorporateActionData storage cA = corporateActionsData[id];
        return (ActionType(getVoteType(id)), cA.numberOfShares, cA.currency, cA.amount, cA.optionalCurrency, cA.optionalAmount);
    }

    function issueShares(uint256 numberOfShares) external virtual override returns (uint256) {
        return initiateCorporateAction(ActionType.ISSUE_SHARES, numberOfShares, address(0), 0, address(0), 0);
    }

    function destroyShares(uint256 numberOfShares) external virtual override returns (uint256) {
        require(balanceOf(address(this)) >= numberOfShares);

        return initiateCorporateAction(ActionType.DESTROY_SHARES, numberOfShares, address(0), 0, address(0), 0);
    }

    function withdrawFunds(address destination, address currency, uint256 amount) external virtual override returns (uint256) {
        verifyAvailable(currency, amount);

        return initiateCorporateAction(ActionType.WITHDRAW_FUNDS, 0, currency, amount, destination, 0);
    }

    function changeExchange(address newExchangeAddress) external virtual override returns (uint256) {
        require(getTradedTokenCount() == 0); //only allow changing exchange if there are no locked up tokens, cancel orders first if needed

        return initiateCorporateAction(ActionType.CHANGE_EXCHANGE, 0, address(exchange), 0, newExchangeAddress, 0);
    }

    function ask(address asset, uint256 assetAmount, address currency, uint256 price, uint256 maxOrders) external virtual override returns (uint256) {
        verifyAvailable(asset, assetAmount);

        return initiateCorporateAction(ActionType.ASK, maxOrders, asset, assetAmount, currency, price);
    }

    function bid(address asset, uint256 assetAmount, address currency, uint256 price, uint256 maxOrders) external virtual override returns (uint256) {
        verifyAvailable(currency, assetAmount*price);

        return initiateCorporateAction(ActionType.BID, maxOrders, asset, assetAmount, currency, price);
    }

    function cancelOrder(uint256 orderId) external virtual override returns (uint256) {
        return initiateCorporateAction(ActionType.CANCEL_ORDER, 0, address(0), orderId, address(0), 0);
    }



    function startReverseSplit(uint256 reverseSplitToOne, address currency, uint256 amount) external virtual override returns (uint256) {
        require(getLockedUpAmount(address(this)) == 0); //do not start a reverse split if some exchanges may still be selling shares, cancel these orders first
        verifyAvailable(currency, getMaxOutstandingShareCount()*amount); //possible worst case if everyone owns 1 share, this is not a restriction, we can always distribute a dummy token that has a higher supply than this share and have a bid order for this dummy token on an exchange

        return initiateCorporateAction(ActionType.REVERSE_SPLIT, 0, currency, amount, address(0), reverseSplitToOne);
    }

    function startDistributeDividend(address currency, uint256 amount) external virtual override returns (uint256) {
        uint256 maxOutstandingShareCount = getMaxOutstandingShareCount();
        verifyAvailable(currency, maxOutstandingShareCount*amount);

        return initiateCorporateAction(ActionType.DISTRIBUTE_DIVIDEND, maxOutstandingShareCount, currency, amount, address(0), 0);
    }
 
    function startDistributeOptionalDividend(address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount) external virtual override returns (uint256) {
        require(optionalCurrency != address(0));
        uint256 maxOutstandingShareCount = getMaxOutstandingShareCount();
        verifyAvailable(currency, maxOutstandingShareCount*amount);
        verifyAvailable(optionalCurrency, maxOutstandingShareCount*optionalAmount);

        return initiateCorporateAction(ActionType.DISTRIBUTE_DIVIDEND, maxOutstandingShareCount, currency, amount, optionalCurrency, optionalAmount);
    }

    function initiateCorporateAction(ActionType decisionType, uint256 numberOfShares, address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount) internal returns (uint256) {
        CorporateActionData storage corporateAction = corporateActionsData[getNextProposalId()]; //lambdas are planned, but not supported yet by Solidity, so initialization has to happen outside the propose method
        corporateAction.numberOfShares = (numberOfShares != 0) ? numberOfShares : getMaxOutstandingShareCount();
        corporateAction.currency = currency;
        corporateAction.amount = amount;
        corporateAction.optionalCurrency = optionalCurrency;
        corporateAction.optionalAmount = optionalAmount;

        return propose(uint16(decisionType), executeCorporateAction, requestCorporateAction);
    }
 
    function executeCorporateAction(uint256 id, VoteResult voteResult) internal returns (bool) {
        ActionType decisionType = ActionType(getVoteType(id));

        CorporateActionData storage cA = corporateActionsData[id];
        uint256 numberOfShares = cA.numberOfShares;
        address currency = cA.currency;
        uint256 amount = cA.amount;
        address optionalCurrency = cA.optionalCurrency;
        uint256 optionalAmount = cA.optionalAmount;

        bool isFullyExecuted = true;
        if (isApproved(voteResult)) {
            if (decisionType < ActionType.ASK) {
                if (decisionType < ActionType.WITHDRAW_FUNDS) {
                    if (decisionType == ActionType.ISSUE_SHARES) {
                        _issueShares(numberOfShares);
                    } else { //decisionType == ActionType.DESTROY_SHARES
                        _destroyShares(numberOfShares);
                    }
                } else {
                    if (decisionType == ActionType.WITHDRAW_FUNDS) {
                        _withdrawFunds(optionalCurrency, currency, amount);
                    } else { //decisionType == ActionType.CHANGE_EXCHANGE
                        _changeExchange(optionalCurrency);
                    }
                }
            } else if (decisionType < ActionType.REVERSE_SPLIT) {
                if (decisionType == ActionType.ASK) {
                    _ask(currency, amount, optionalCurrency, optionalAmount, numberOfShares);
                } else  { //decisionType == ActionType.BID
                    _bid(currency, amount, optionalCurrency, optionalAmount, numberOfShares);
                }
            } else if (decisionType == ActionType.CANCEL_ORDER) {
                _cancelOrder(amount); //the amount field is used to store the order id since it is of the same type
            } else if ((decisionType == ActionType.DISTRIBUTE_DIVIDEND) && (optionalCurrency != address(0))) { //we need to trigger ActionType.DISTRIBUTE_OPTIONAL_DIVIDEND, which requires another vote to either approve or reject the optional dividend
                pendingRequestId = 0; //otherwise we cannot start the optional dividend corporate action

                initiateCorporateAction(ActionType.DISTRIBUTE_OPTIONAL_DIVIDEND, 0, currency, amount, optionalCurrency, optionalAmount);
                isFullyExecuted = false;
            } else {
                voteResult = VoteResult.PARTIAL_EXECUTION;
                getProposal(id).result = voteResult;
                isFullyExecuted = false;
            }
        }
        
        emit CorporateAction(id, voteResult, decisionType, numberOfShares, currency, amount, optionalCurrency, optionalAmount);

        return isFullyExecuted;
    }

    function requestCorporateAction(uint256 id) internal {
        CorporateActionData storage cA = corporateActionsData[id];
        emit RequestCorporateAction(id, ActionType(getVoteType(id)), cA.numberOfShares, cA.currency, cA.amount, cA.optionalCurrency, cA.optionalAmount);
    }

    function _issueShares(uint256 numberOfShares) private {
        _mint(address(this), numberOfShares);
    }

    function _destroyShares(uint256 numberOfShares) private {
        _burn(address(this), numberOfShares);
    }

    function _withdrawFunds(address destination, address currency, uint256 amount) private {
        safeTransfer(IERC20(currency), destination, amount); //we have to transfer, we cannot work with safeIncreaseAllowance, because unlike an exchange, which we can choose, we have no control over how the currency will be spent
    }

    function _changeExchange(address newExchangeAddress) private {
        exchange = IExchange(newExchangeAddress);        
    }

    function _ask(address asset, uint256 assetAmount, address currency, uint256 price, uint256 maxOrders) private {
        IERC20(asset).safeIncreaseAllowance(address(exchange), assetAmount); //only send to safe exchanges, the total price is locked up
        registerTradedToken(asset);
        exchange.ask(asset, assetAmount, currency, price, maxOrders);
    }

    function _bid(address asset, uint256 assetAmount, address currency, uint256 price, uint256 maxOrders) private {
        IERC20(currency).safeIncreaseAllowance(address(exchange), assetAmount*price); //only send to safe exchanges, the total price is locked up
        registerTradedToken(currency);
        exchange.bid(asset, assetAmount, currency, price, maxOrders);
    }

    function _cancelOrder(uint256 orderId) private {
        exchange.cancel(orderId);
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
                uint256 maxEnd = shareholders.length;
                if (end > maxEnd) {
                    end = maxEnd;
                }

                IERC20 erc20 = IERC20(currencyAddress);

                if (decisionType == ActionType.DISTRIBUTE_DIVIDEND) {
                    finishDistributeDividend(vP.processedShares, shareholders.addresses, start, end, erc20, amountPerShare);
                } else if (decisionType == ActionType.DISTRIBUTE_OPTIONAL_DIVIDEND) {
                    finishDistributeOptionalDividend(vP, vP.processedShares, shareholders.addresses, start, end, erc20, amountPerShare, optionalCurrencyAddress, optionalAmount);
                } else { //(decisionType == ActionType.REVERSE_SPLIT)
                    finishReverseSplit(vP.processedShares, shareholders.addresses, start, end, erc20, amountPerShare, optionalAmount);
                }

                vP.processedShareholders = end;

                unchecked{
                    uint shareholdersLeft = maxEnd - end;

                    if (shareholdersLeft == 0) {
                        vP.result = VoteResult.APPROVED;

                        emit CorporateAction(id, VoteResult.APPROVED, decisionType, cA.numberOfShares, currencyAddress, amountPerShare, optionalCurrencyAddress, optionalAmount);

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

    function finishDistributeDividend(mapping(address => uint256) storage processedShares, mapping(uint256 => address) storage _shareholders, uint256 start, uint256 end, IERC20 erc20, uint256 amountPerShare) private {
        for (uint256 i = start; i < end;) {
            address shareholder = _shareholders[i];
            uint256 totalShares = balanceOf(shareholder);
            uint256 unprocessedShares;
            unchecked { unprocessedShares = totalShares - processedShares[shareholder]; }
            if (unprocessedShares > 0) {
                processedShares[shareholder] = totalShares;
                safeTransfer(erc20, shareholder, unprocessedShares*amountPerShare);
            }
            unchecked { i++; }
        }
    }

    function finishDistributeOptionalDividend(VoteParameters storage vP, mapping(address => uint256) storage processedShares, mapping(uint256 => address) storage _shareholders, uint256 start, uint256 end, IERC20 erc20, uint256 amountPerShare, address optionalCurrencyAddress, uint256 optionalAmount) private {
        IERC20 optionalERC20 = IERC20(optionalCurrencyAddress);

        mapping(address => uint256) storage voteIndex = vP.voteIndex;
        Vote[] storage votes = vP.votes;
        for (uint256 i = start; i < end;) {
            address shareholder = _shareholders[i];
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
    }

    function finishReverseSplit(mapping(address => uint256) storage processedShares, mapping(uint256 => address) storage _shareholders, uint256 start, uint256 end, IERC20 erc20, uint256 amountPerShare, uint256 reverseSplitRatio) private {
        for (uint256 i = start; i < end;) {
            address shareholder = _shareholders[i];
            uint256 totalShares = balanceOf(shareholder);
            uint256 processed = processedShares[shareholder];
            uint256 unprocessedShares;
            unchecked { unprocessedShares = totalShares - processed; }
            if (unprocessedShares > 0) {
                uint256 remainingShares = unprocessedShares/reverseSplitRatio;
                unchecked {
                    processedShares[shareholder] = processed + remainingShares;

                    //reduce the stake of the shareholder from stake -> stake/reverseSplitRatio == stake - (stake - stake/reverseSplitRatio)
                    _burn(shareholder, unprocessedShares - remainingShares);
                }

                //pay out fractional shares
                uint256 fraction = unprocessedShares%reverseSplitRatio;
                if (fraction > 0) {
                    safeTransfer(erc20, shareholder, fraction*amountPerShare);
                }
            }
            unchecked { i++; }
        }
    }



    function verifyAvailable(address currency, uint256 amount) internal view {
        require(IERC20(currency).balanceOf(address(this)) >= amount);
    }

    function safeTransfer(IERC20 token, address destination, uint256 amount) internal { //reduces the size of the compiled smart contract if this is wrapped in a function
        token.safeTransfer(destination, amount);
    }

    function isAlwaysApprovedCorporateAction(uint16 decisionType) internal pure returns (bool) {
        return (decisionType == uint16(ActionType.DISTRIBUTE_OPTIONAL_DIVIDEND));
    }

    function isPartialExecutionCorporateAction(uint16 decisionType, uint256 id) internal view returns (bool) {
        return (
            (decisionType == uint16(ActionType.REVERSE_SPLIT))
         || ((decisionType == uint16(ActionType.DISTRIBUTE_DIVIDEND)) && (corporateActionsData[id].optionalCurrency == address(0)))
         || (decisionType == uint16(ActionType.DISTRIBUTE_OPTIONAL_DIVIDEND))
        );
    }
}