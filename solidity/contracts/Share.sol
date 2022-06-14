// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import 'contracts/IShare.sol';
import 'contracts/IScrutineer.sol';
import 'contracts/IShareInfo.sol';
import 'contracts/IExchange.sol';

struct CorporateActionData { //see the RequestCorporateAction and CorporateAction event in the IShare interface for the meaning of these fields
    CorporateActionType decisionType;
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
    IScrutineer public scrutineer;
    IShareInfo public shareInfo;

    mapping(uint256 => address) private newOwners;
    mapping(uint256 => DecisionParameters) private decisionParametersData;
    mapping(uint256 => CorporateActionData) private corporateActionsData;

    uint256 public pendingNewOwnerId;
    uint256 public pendingDecisionParametersId;
    uint256 public pendingCorporateActionId;

    modifier isOwner() {
        require(msg.sender == owner);
        _;
    }

    constructor(string memory name, string memory symbol, address scrutineerAddress, address shareInfoAddress) ERC20(name, symbol) {
        scrutineer = IScrutineer(scrutineerAddress);
        shareInfo = IShareInfo(shareInfoAddress);
        owner = msg.sender;
    }



    function decimals() public pure override returns (uint8) {
        return 0;
    }

    receive() external payable { //used to receive wei when msg.data is empty
        revert(); //as long as Ether is not ERC20 compliant
    }

    fallback() external payable { //used to receive wei when msg.data is not empty
        revert(); //as long as Ether is not ERC20 compliant
    }



    function registerShareholder(address shareholder) external override returns (uint256) {
        return shareInfo.registerShareholder(shareholder);
    }

    function packShareholders() external { //if a lot of active shareholders change, one may not want to iterate over non existing shareholders anymore when distributing a dividend
        shareInfo.packShareholders();
    }

    function packApprovedExchanges(address tokenAddress) external {
        shareInfo.packApprovedExchanges(tokenAddress);
    }



    function getProposedOwner(uint256 id) external view override returns (address) {
        return newOwners[id];
    }

    function getProposedDecisionParameters(uint256 id) external view override returns (uint64, uint64, uint32, uint32, uint32, uint32) {
        DecisionParameters storage dP = decisionParametersData[id];
        return (dP.decisionTime, dP.executionTime, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator);
    }

    function getProposedCorporateAction(uint256 id) external view override returns (CorporateActionType, uint256, address, address, uint256, address, uint256) {
        CorporateActionData storage cA = corporateActionsData[id];
        return (cA.decisionType, cA.numberOfShares, cA.exchange, cA.currency, cA.amount, cA.optionalCurrency, cA.optionalAmount);
    }



    function changeOwner(address newOwner) external override isOwner {
        if (pendingNewOwnerId == 0) {
            (uint256 id, bool noSharesOutstanding) = scrutineer.propose(address(this));

            if (noSharesOutstanding) {
                doChangeOwner(id, VoteResult.NO_OUTSTANDING_SHARES, newOwner);
            } else {
                newOwners[id] = newOwner;

                pendingNewOwnerId = id;

                emit RequestNewOwner(id, newOwner);
            }
        }
    }

    function changeOwnerOnApproval() external override {
        resolveNewOwner(false);
    }

    function withdrawChangeOwnerRequest() external override isOwner {
        resolveNewOwner(true);
    }

    function resolveNewOwner(bool withdraw) internal {
        uint256 id = pendingNewOwnerId;
        if (id != 0) {
           bool resultHasBeenUpdated = withdraw ? scrutineer.withdrawVote(id) : scrutineer.resolveVote(id);

            if (resultHasBeenUpdated) {
                VoteResult voteResult = scrutineer.getVoteResult(address(this), id);

                doChangeOwner(id, voteResult, newOwners[id]);

                pendingNewOwnerId = 0;
            }
        }
    }

    function doChangeOwner(uint256 id, VoteResult voteResult, address newOwner) internal {
        if (isApproved(voteResult)) {
            owner = newOwner;
        }

        emit NewOwner(id, newOwner, voteResult);
    }

    function changeDecisionParameters(uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) external override isOwner {
        if (pendingDecisionParametersId == 0) {
            (uint256 id, bool noSharesOutstanding) = scrutineer.propose(address(this));

            if (noSharesOutstanding) {
                doSetDecisionParameters(id, VoteResult.NO_OUTSTANDING_SHARES, decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
            } else {
                DecisionParameters storage dP = decisionParametersData[id];
                dP.decisionTime = decisionTime;
                dP.executionTime = executionTime;
                dP.quorumNumerator = quorumNumerator;
                dP.quorumDenominator = quorumDenominator;
                dP.majorityNumerator = majorityNumerator;
                dP.majorityDenominator = majorityDenominator;

                pendingDecisionParametersId = id;

                emit RequestDecisionParametersChange(id, decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
            }
        }
    }

    function changeDecisionParametersOnApproval() external override {
        resolveDecisionParametersChange(false);
    }

    function withdrawChangeDecisionParametersRequest() external override isOwner {
        resolveDecisionParametersChange(true);
    }

    function resolveDecisionParametersChange(bool withdraw) internal {
        uint256 id = pendingDecisionParametersId;
        if (id != 0) {
            bool resultHasBeenUpdated = withdraw ? scrutineer.withdrawVote(id) : scrutineer.resolveVote(id);

            if (resultHasBeenUpdated) {
                VoteResult voteResult = scrutineer.getVoteResult(address(this), id);

                DecisionParameters storage dP = decisionParametersData[id];
                doSetDecisionParameters(id, voteResult, dP.decisionTime, dP.executionTime, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator);

                pendingDecisionParametersId = 0;
            }
        }
    }

    function doSetDecisionParameters(uint256 id, VoteResult voteResult, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) internal {
        if (isApproved(voteResult)) {
            scrutineer.setDecisionParameters(decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
        }

        emit DecisionParametersChange(id, voteResult, decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
    }

    function issueShares(uint256 numberOfShares) external override {
        doCorporateAction(CorporateActionType.ISSUE_SHARES, numberOfShares, address(0), address(0), 0, address(0), 0);
    }

    function destroyShares(uint256 numberOfShares) external override {
        doCorporateAction(CorporateActionType.DESTROY_SHARES, numberOfShares, address(0), address(0), 0, address(0), 0);
    }

    function raiseFunds(uint256 numberOfShares, address exchangeAddress, address currency, uint256 price) external override {
        require(shareInfo.getTreasuryShareCount(address(this)) >= numberOfShares);
        doCorporateAction(CorporateActionType.RAISE_FUNDS, numberOfShares, exchangeAddress, currency, price, address(0), 0);
    }

    function buyBack(uint256 numberOfShares, address exchangeAddress, address currency, uint256 price) external override {
        require(shareInfo.getAvailableAmount(address(this), currency) >= numberOfShares*price);
        doCorporateAction(CorporateActionType.BUY_BACK, numberOfShares, exchangeAddress, currency, price, address(0), 0);
    }

    function cancelOrder(address exchangeAddress, uint256 orderId) external override {
        doCorporateAction(CorporateActionType.CANCEL_ORDER, shareInfo.getMaxOutstandingShareCount(address(this)), exchangeAddress, address(0), orderId, address(0), 0);
    }

    function distributeDividend(address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount) external override {
        uint256 maxOutstandingShareCount = shareInfo.getMaxOutstandingShareCount(address(this));
        require(shareInfo.getAvailableAmount(address(this), currency) >= maxOutstandingShareCount*amount);

        if (optionalCurrency != address(0)) {
            require(shareInfo.getAvailableAmount(address(this), optionalCurrency) >= maxOutstandingShareCount*optionalAmount);
        }

        doCorporateAction(CorporateActionType.DISTRIBUTE_DIVIDEND, maxOutstandingShareCount, address(0), currency, amount, optionalCurrency, optionalAmount);
    }

    function withdrawFunds(address destination, address currency, uint256 amount) external override {
        require(shareInfo.getAvailableAmount(address(this), currency) >= amount);
        doCorporateAction(CorporateActionType.WITHDRAW_FUNDS, shareInfo.getMaxOutstandingShareCount(address(this)), destination, currency, amount, address(0), 0);
    }

    function doCorporateAction(CorporateActionType decisionType, uint256 numberOfShares, address exchangeAddress, address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount) internal isOwner {
        if (pendingCorporateActionId == 0) {
            (uint256 id, bool noSharesOutstanding) = scrutineer.propose(address(this));

            if (noSharesOutstanding) {
                executeCorporateAction(id, VoteResult.NO_OUTSTANDING_SHARES, decisionType, numberOfShares, exchangeAddress, currency, amount, optionalCurrency, optionalAmount);
            } else {
                doRequestCorporateAction(id, decisionType, numberOfShares, exchangeAddress, currency, amount, optionalCurrency, optionalAmount);
            }
        }
    }

    function doRequestCorporateAction(uint256 id, CorporateActionType decisionType, uint256 numberOfShares, address exchange, address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount) internal {
        CorporateActionData storage corporateAction = corporateActionsData[id];
        corporateAction.decisionType = decisionType;
        corporateAction.numberOfShares = numberOfShares;
        corporateAction.exchange = exchange;
        corporateAction.currency = currency;
        corporateAction.amount = amount;
        corporateAction.optionalCurrency = optionalCurrency;
        corporateAction.optionalAmount = optionalAmount;

        pendingCorporateActionId = id;

        emit RequestCorporateAction(id, decisionType, numberOfShares, exchange, currency, amount, optionalCurrency, optionalAmount);
    }


    function corporateActionOnApproval() external override {
        resolveCorporateAction(false);
    }

    function withdrawCorporateActionRequest() external override isOwner {
        resolveCorporateAction(true);
    }

    function resolveCorporateAction(bool withdraw) internal {
        uint256 id = pendingCorporateActionId;
        if (id != 0) {
           bool resultHasBeenUpdated = withdraw ? scrutineer.withdrawVote(id) : scrutineer.resolveVote(id);

            if (resultHasBeenUpdated) {
                VoteResult voteResult = scrutineer.getVoteResult(address(this), id);

                CorporateActionData storage cA = corporateActionsData[id];
                CorporateActionType decisionType = cA.decisionType;
                address currency = cA.currency;
                uint256 amount = cA.amount;
                address optionalCurrency = cA.optionalCurrency;
                uint256 optionalAmount = cA.optionalAmount;

                executeCorporateAction(id, voteResult, decisionType, cA.numberOfShares, cA.exchange, currency, amount, optionalCurrency, optionalAmount);

                pendingCorporateActionId = 0;

                if ((optionalCurrency != address(0)) && isApproved(voteResult)) { //(optionalCurrency != address(0)) implies that (decisionType == CorporateActionType.DISTRIBUTE_DIVIDEND)
                    doCorporateAction(CorporateActionType.DISTRIBUTE_OPTIONAL_DIVIDEND, shareInfo.getMaxOutstandingShareCount(address(this)), address(0), currency, amount, optionalCurrency, optionalAmount);
                }
            }
        }
    }

    function executeCorporateAction(uint256 id, VoteResult voteResult, CorporateActionType decisionType, uint256 numberOfShares, address exchangeAddress, address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount) internal {
        if (isApproved(voteResult)) {
            if (decisionType == CorporateActionType.DISTRIBUTE_DIVIDEND) { //should be the most common action
                if (optionalCurrency == address(0)) {
                    address[] memory shareholders = shareInfo.getShareholders();
                    for (uint256 i = 0; i < shareholders.length; i++) {
                        address shareholder = shareholders[i];
                        IERC20(currency).safeTransfer(shareholder, balanceOf(shareholder)*amount);
                    }
                } //else a DISTRIBUTE_OPTIONAL_DIVIDEND corporate action will be triggered in the resolveCorporateAction() method
            } else if (decisionType == CorporateActionType.ISSUE_SHARES) {
                _mint(address(this), numberOfShares);
            } else if (decisionType == CorporateActionType.DESTROY_SHARES) {
                _burn(address(this), numberOfShares);
            } else if (decisionType == CorporateActionType.RAISE_FUNDS) {
                shareInfo.registerApprovedExchange(address(this), exchangeAddress);
                increaseAllowance(exchangeAddress, numberOfShares); //only send to safe exchanges, the number of shares are removed from treasury
                IExchange exchange = IExchange(exchangeAddress);
                exchange.ask(address(this), numberOfShares, currency, amount);
            } else if (decisionType == CorporateActionType.BUY_BACK) {
                shareInfo.registerApprovedExchange(currency, exchangeAddress);
                IERC20(currency).safeIncreaseAllowance(exchangeAddress, numberOfShares*amount); //only send to safe exchanges, the total price is locked up
                IExchange exchange = IExchange(exchangeAddress);
                exchange.bid(address(this), numberOfShares, currency, amount);
            } else if (decisionType == CorporateActionType.CANCEL_ORDER) {
                IExchange exchange = IExchange(exchangeAddress);
                exchange.cancel(amount);
            } else if (decisionType == CorporateActionType.WITHDRAW_FUNDS) {
                IERC20(currency).safeTransfer(exchangeAddress, amount); //we have to transfer, we cannot work with safeIncreaseAllowance, because unlike an exchange, which we can choose, we have no control over how the currency will be spent
            } else { //decisionType == CorporateActionType.DISTRIBUTE_OPTIONAL_DIVIDEND, should be a safe default action
                address[] memory shareholders = shareInfo.getShareholders();
                Vote[] memory votes = scrutineer.getVotes(pendingNewOwnerId);
                //work around there being no memory mapping in Solidity
                IERC20 optionalERC20 = IERC20(optionalCurrency);
                for (uint256 i = 0; i < votes.length; i++) {
                    Vote memory v = votes[i];
                    if (v.choice == VoteChoice.IN_FAVOR) {
                        address shareholder = v.voter;
                        optionalERC20.safeIncreaseAllowance(shareholder, balanceOf(shareholder)*optionalAmount);
                    }
                }
                for (uint256 i = 0; i < shareholders.length; i++) {
                    address shareholder = shareholders[i];
                    uint256 optionalAllowance = optionalERC20.allowance(address(this), shareholder);
                    if (optionalAllowance > 0) {
                        optionalERC20.safeDecreaseAllowance(shareholder, optionalAllowance);
                        optionalERC20.safeTransfer(shareholder, optionalAllowance);
                    } else {
                        IERC20(currency).safeTransfer(shareholder, balanceOf(shareholder)*amount);
                    }
                }
            }
        }

        emit CorporateAction(id, decisionType, voteResult, numberOfShares, exchangeAddress, currency, amount, optionalCurrency, optionalAmount);
    }

    function isApproved(VoteResult voteResult) internal pure returns (bool) {
        return ((voteResult == VoteResult.APPROVED) || (voteResult == VoteResult.NO_OUTSTANDING_SHARES));
    }
}