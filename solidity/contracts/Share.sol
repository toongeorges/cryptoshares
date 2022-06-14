// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import 'contracts/IShare.sol';
import 'contracts/IScrutineer.sol';
import 'contracts/IShareInfo.sol';
import 'contracts/IExchange.sol';

enum CorporateActionType {
    ISSUE_SHARES, DESTROY_SHARES, RAISE_FUNDS, BUY_BACK, WITHDRAW_FUNDS, DISTRIBUTE_DIVIDEND, CANCEL_ORDER
}

struct CorporateActionData {
    CorporateActionType decisionType;
    address exchange; //only relevant for RAISE_FUNDS, BUY_BACK and WITHDRAW_FUNDS, pack together with decisionType
    uint256 numberOfShares; //the number of shares created or destroyed for ISSUE_SHARES or DESTROY_SHARES, the number of shares to sell or buy back for RAISE_FUNDS and BUY_BACK and the (max) outstanding number of shares for WITHDRAW_FUNDS and DISTRIBUTE_DIVIDEND
    address currency; //ERC20 token
    uint256 amount; //empty for ISSUE_SHARES and DESTROY_SHARES, the ask or bid price for a single share for RAISE_FUNDS and BUY_BACK, the amount to withdraw for WITHDRAW_FUNDS or to distribute per share for DISTRIBUTE_DIVIDEND
    address optionalCurrency; //ERC20 token
    uint256 optionalAmount; //only relevant in the case of an optional dividend for DISTRIBUTE_DIVIDEND, shareholders can opt for the optional dividend instead of the default dividend
}

contract Share is ERC20, IShare {
    using SafeERC20 for IERC20;

    //who manages the smart contract
    event RequestNewOwner(uint256 indexed id, address indexed newOwner);
    event NewOwner(uint256 indexed id, address indexed newOwner, VoteResult indexed voteResult);

    //actions changing how decisions are made
    event RequestDecisionParametersChange(uint256 indexed id, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator);
    event DecisionParametersChange(uint256 indexed id, VoteResult indexed voteResult, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator);

    //corporate actions
    event RequestCorporateAction(uint256 indexed id, CorporateActionType indexed decisionType, uint256 numberOfShares, address exchange, address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount);
    event CorporateAction(uint256 indexed id, CorporateActionType indexed decisionType, VoteResult indexed voteResult, uint256 numberOfShares, address exchange, address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount);

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



    function registerShareholder(address shareholder) external returns (uint256) {
        return shareInfo.registerShareholder(shareholder);
    }

    function packShareholders() external { //if a lot of active shareholders change, one may not want to iterate over non existing shareholders anymore when distributing a dividend
        shareInfo.packShareholders();
    }

    function packApprovedExchanges(address tokenAddress) external {
        shareInfo.packApprovedExchanges(tokenAddress);
    }



    function getProposedOwner(uint256 id) external view returns (address) {
        return newOwners[id];
    }

    function getProposedDecisionParameters(uint256 id) external view returns (uint64, uint64, uint32, uint32, uint32, uint32) {
        DecisionParameters storage dP = decisionParametersData[id];
        return (dP.decisionTime, dP.executionTime, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator);
    }

    function getProposedCorporateAction(uint256 id) external view returns (CorporateActionType, uint256, address, address, uint256, address, uint256) {
        CorporateActionData storage cA = corporateActionsData[id];
        return (cA.decisionType, cA.numberOfShares, cA.exchange, cA.currency, cA.amount, cA.optionalCurrency, cA.optionalAmount);
    }



    function changeOwner(address newOwner) external isOwner {
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

    function withdrawChangeOwnerRequest() external isOwner {
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

    function changeDecisionParameters(uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) external isOwner {
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

    function withdrawChangeDecisionParametersRequest() external isOwner {
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

    function issueShares(uint256 numberOfShares) external {
        doCorporateAction(CorporateActionType.ISSUE_SHARES, numberOfShares, address(0), address(0), 0, address(0), 0);
    }

    function destroyShares(uint256 numberOfShares) external {
        doCorporateAction(CorporateActionType.DESTROY_SHARES, numberOfShares, address(0), address(0), 0, address(0), 0);
    }

    function raiseFunds(uint256 numberOfShares, address exchangeAddress, address currency, uint256 price) external {
        require(shareInfo.getTreasuryShareCount(address(this)) >= numberOfShares);
        doCorporateAction(CorporateActionType.RAISE_FUNDS, numberOfShares, exchangeAddress, currency, price, address(0), 0);
    }

    function buyBack(uint256 numberOfShares, address exchangeAddress, address currency, uint256 price) external {
        uint256 totalPrice = numberOfShares*price;
        require(shareInfo.getAvailableAmount(address(this), currency) >= totalPrice);
        doCorporateAction(CorporateActionType.BUY_BACK, numberOfShares, exchangeAddress, currency, price, address(0), 0);
    }

    function withdrawFunds(address destination, address currency, uint256 amount) external {
        require(shareInfo.getAvailableAmount(address(this), currency) >= amount);
        doCorporateAction(CorporateActionType.WITHDRAW_FUNDS, shareInfo.getMaxOutstandingShareCount(address(this)), destination, currency, amount, address(0), 0);
    }

    function distributeDividend(address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount) external {
        uint256 maxOutstandingShareCount = shareInfo.getMaxOutstandingShareCount(address(this));
        uint256 totalDistribution = maxOutstandingShareCount*amount;
        require(shareInfo.getAvailableAmount(address(this), currency) >= totalDistribution);

        bool isOptional = (optionalCurrency != address(0));
        uint256 totalOptionalDistribution = 0;
        if (isOptional) {
            totalOptionalDistribution = maxOutstandingShareCount*optionalAmount;
            require(shareInfo.getAvailableAmount(address(this), optionalCurrency) >= totalOptionalDistribution);
        }

        doCorporateAction(CorporateActionType.DISTRIBUTE_DIVIDEND, maxOutstandingShareCount, address(0), currency, amount, optionalCurrency, optionalAmount);
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

    function withdrawCorporateActionRequest() external isOwner {
        resolveCorporateAction(true);
    }

    function resolveCorporateAction(bool withdraw) internal {
        uint256 id = pendingNewOwnerId;
        if (id != 0) {
           bool resultHasBeenUpdated = withdraw ? scrutineer.withdrawVote(id) : scrutineer.resolveVote(id);

            if (resultHasBeenUpdated) {
                VoteResult voteResult = scrutineer.getVoteResult(address(this), id);

                CorporateActionData storage cA = corporateActionsData[id];

                executeCorporateAction(id, voteResult, cA.decisionType, cA.numberOfShares, cA.exchange, cA.currency, cA.amount, cA.optionalCurrency, cA.optionalAmount);

                pendingNewOwnerId = 0;
            }
        }
    }

    function executeCorporateAction(uint256 id, VoteResult voteResult, CorporateActionType decisionType, uint256 numberOfShares, address exchangeAddress, address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount) internal {
        if (isApproved(voteResult)) {
            if (decisionType == CorporateActionType.ISSUE_SHARES) {
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
            } else if (decisionType == CorporateActionType.WITHDRAW_FUNDS) {
                IERC20(currency).safeTransfer(exchangeAddress, amount); //we have to transfer, we cannot work with safeIncreaseAllowance, because unlike an exchange, which we can choose, we have no control over how the currency will be spent
            } else if (decisionType == CorporateActionType.DISTRIBUTE_DIVIDEND) {
                address[] memory shareholders = shareInfo.getShareholders();
                for (uint256 i = 0; i < shareholders.length; i++) {
                    address shareholder = shareholders[i];
                    uint256 shareholderStake = balanceOf(shareholder);
                    IERC20(currency).safeTransfer(shareholder, shareholderStake*amount);
                }
                //TODO how to deal with optional dividend, how do we know the vote?  //TODO also handle the case of VoteResult.NO_OUTSTANDING_SHARES
            }
        }

        emit CorporateAction(id, decisionType, voteResult, numberOfShares, exchangeAddress, currency, amount, optionalCurrency, optionalAmount);
    }

    function isApproved(VoteResult voteResult) internal pure returns (bool) {
        return ((voteResult == VoteResult.APPROVED) || (voteResult == VoteResult.NO_OUTSTANDING_SHARES));
    }

/*
    function distributeDividend(uint256 numberOfShares, address currency, uint256 amount) external isOwner {

    }

    function distributeOptionalDividend(uint256 numberOfShares, address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount) external isOwner {

    }
*/
    //TODO initiate corporate actions
    //TODO approve corporate actions
    //TODO withdraw corporate actions

    //TODO figure out how to implement the optional dividend (voters have to choose an option) --> through a second vote with scrutineer, the share smart contract must be able to get the voters?
    //TODO allow cancelling order on an exchange!
}