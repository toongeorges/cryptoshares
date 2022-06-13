// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import 'contracts/IShare.sol';
import 'contracts/IScrutineer.sol';
import 'contracts/IShareInfo.sol';
import 'contracts/IExchange.sol';

enum DecisionParametersType {
    CHANGE_DECISION_TIME, CHANGE_QUORUM, CHANGE_MAJORITY, CHANGE_ALL
}

struct DecisionParametersData { //this is the same struct as the Scrutineer's DecisionParameters struct, with one extra field: decisionType
    DecisionParametersType decisionType;
    uint64 decisionTime; //How much time in seconds shareholders have to approve a request
    uint64 executionTime; //How much time in seconds the owner has to execute an approved request after the decisionTime has ended
    uint32 quorumNumerator;
    uint32 quorumDenominator;
    uint32 majorityNumerator;
    uint32 majorityDenominator;
}

enum CorporateActionType {
    ISSUE_SHARES, DESTROY_SHARES, RAISE_FUNDS, BUY_BACK, DISTRIBUTE_DIVIDEND
}

struct CorporateActionData {
    CorporateActionType decisionType;
    address exchange; //only relevant for RAISE_FUNDS and BUY_BACK, pack together with decisionType
    uint256 numberOfShares; //the number of shares created or destroyed for ISSUE_SHARES or DESTROY_SHARES, the number of shares to sell or buy back for RAISE_FUNDS and BUY_BACK and the number of shares receiving dividend for DISTRIBUTE_DIVIDEND
    address currency; //ERC20 token
    uint256 amount; //empty for ISSUE_SHARES and DESTROY_SHARES, the ask or bid price for a single share for RAISE_FUNDS and BUY_BACK, the amount of dividend to be distributed per share for DISTRIBUTE_DIVIDEND
    address optionalCurrency; //ERC20 token
    uint256 optionalAmount; //only relevant in the case of an optional dividend for DISTRIBUTE_DIVIDEND, shareholders can opt for the optional dividend instead of the default dividend
}

contract Share is ERC20, IShare {
    using SafeERC20 for IERC20;

    //who manages the smart contract
    event RequestNewOwner(uint256 indexed id, address indexed newOwner);
    event NewOwner(uint256 indexed id, address indexed newOwner, VoteResult indexed voteResult);

    //actions changing how decisions are made
    event RequestDecisionParameters(uint256 indexed id, DecisionParametersType indexed decisionType, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator);
    event DecisionParameters(uint256 indexed id, DecisionParametersType indexed decisionType, VoteResult indexed voteResult, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator);

    //corporate actions
    event RequestCorporateAction(uint256 indexed id, CorporateActionType indexed decisionType, uint256 numberOfShares, address exchange, address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount);
    event CorporateAction(uint256 indexed id, CorporateActionType indexed decisionType, VoteResult indexed voteResult, uint256 numberOfShares, address exchange, address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount);

    //external proposals, context needs to be provided
    event RequestExternalProposal(uint256 indexed id);
    event ExternalProposal(uint256 indexed id, VoteResult indexed voteResult);

    address public owner;
    IScrutineer public scrutineer;
    IShareInfo public shareInfo;

    mapping(uint256 => address) private newOwners;
    mapping(uint256 => DecisionParametersData) private decisionParametersData;
    mapping(uint256 => CorporateActionData) private corporateActionsData;

    uint256 public pendingNewOwnerId;
    uint256 public pendingDecisionParametersId;
    uint256 public pendingCorporateActionId;
    uint256 public pendingExternalProposalCount; //TODO

    modifier isOwner() {
        require(msg.sender == owner);
        _;
    }

    constructor(string memory name, string memory symbol, uint256 numberOfShares, address scrutineerAddress, address shareInfoAddress) ERC20(name, symbol) {
        scrutineer = IScrutineer(scrutineerAddress);
        shareInfo = IShareInfo(shareInfoAddress);

        //set sensible default values
        scrutineer.setDecisionParameters(2592000, 604800, 0, 1, 1, 2); //2592000s = 30 days, 604800s = 7 days

        doChangeOwner(msg.sender);
        issueShares(numberOfShares);
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



    function registerShareholder(address shareholder) external returns (uint256) {
        return shareInfo.registerShareholder(shareholder);
    }

    function packShareholders() external isOwner { //if a lot of active shareholders change, one may not want to iterate over non existing shareholders anymore when distributing a dividend
        shareInfo.packShareholders();
    }

    function packApprovedExchanges(address tokenAddress) external isOwner {
        shareInfo.packApprovedExchanges(tokenAddress);
    }



    function getProposedOwner(uint256 id) external view returns (address) {
        return newOwners[id];
    }

    function getProposedDecisionParameters(uint256 id) external view returns (DecisionParametersType, uint64, uint64, uint32, uint32, uint32, uint32) {
        DecisionParametersData storage dP = decisionParametersData[id];
        return (dP.decisionType, dP.decisionTime, dP.executionTime, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator);
    }

    function getProposedCorporateAction(uint256 id) external view returns (CorporateActionType, uint256, address, address, uint256, address, uint256) {
        CorporateActionData storage cA = corporateActionsData[id];
        return (cA.decisionType, cA.numberOfShares, cA.exchange, cA.currency, cA.amount, cA.optionalCurrency, cA.optionalAmount);
    }



    function changeOwner(address newOwner) external isOwner {
        doChangeOwner(newOwner);
    }

    function doChangeOwner(address newOwner) internal { //does not have the isOwner modifier
        if (pendingNewOwnerId == 0) {
            (uint256 id, bool noSharesOutstanding) = scrutineer.propose(address(this));

            if (noSharesOutstanding) {
                owner = newOwner;

                emit NewOwner(id, newOwner, VoteResult.NO_OUTSTANDING_SHARES);
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

                address newOwner = newOwners[id];

                if (!withdraw && (voteResult == VoteResult.APPROVED)) {
                    owner = newOwner;
                }

                pendingNewOwnerId = 0;

                emit NewOwner(id, newOwner, voteResult);
            }
        }
    }

    function changeDecisionTime(uint64 decisionTime, uint64 executionTime) external isOwner {
        (,, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) = scrutineer.getDecisionParameters();

        doChangeDecisionParameters(DecisionParametersType.CHANGE_DECISION_TIME, decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
    }

    function changeQuorum(uint32 quorumNumerator, uint32 quorumDenominator) external isOwner {
        (uint64 decisionTime, uint64 executionTime,,, uint32 majorityNumerator, uint32 majorityDenominator) = scrutineer.getDecisionParameters();

        doChangeDecisionParameters(DecisionParametersType.CHANGE_QUORUM, decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
    }

    function changeMajority(uint32 majorityNumerator, uint32 majorityDenominator) external isOwner {
        (uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator,,) = scrutineer.getDecisionParameters();

        doChangeDecisionParameters(DecisionParametersType.CHANGE_MAJORITY, decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
    }

    function changeDecisionParameters(uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) external isOwner {
        doChangeDecisionParameters(DecisionParametersType.CHANGE_ALL, decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
    }

    function doChangeDecisionParameters(DecisionParametersType decisionType, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) internal {
        if (pendingDecisionParametersId == 0) {
            (uint256 id, bool noSharesOutstanding) = scrutineer.propose(address(this));

            if (noSharesOutstanding) {
                scrutineer.setDecisionParameters(decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);

                emit DecisionParameters(id, decisionType, VoteResult.NO_OUTSTANDING_SHARES, decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
            } else {
                DecisionParametersData storage dP = decisionParametersData[id];
                dP.decisionType = decisionType;
                dP.decisionTime = decisionTime;
                dP.executionTime = executionTime;
                dP.quorumNumerator = quorumNumerator;
                dP.quorumDenominator = quorumDenominator;
                dP.majorityNumerator = majorityNumerator;
                dP.majorityDenominator = majorityDenominator;

                pendingDecisionParametersId = id;

                emit RequestDecisionParameters(id, decisionType, decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
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

                DecisionParametersData storage dP = decisionParametersData[id];
                DecisionParametersType decisionType = dP.decisionType;
                uint64 decisionTime = dP.decisionTime;
                uint64 executionTime = dP.executionTime;
                uint32 quorumNumerator = dP.quorumNumerator;
                uint32 quorumDenominator = dP.quorumDenominator;
                uint32 majorityNumerator = dP.majorityNumerator;
                uint32 majorityDenominator = dP.majorityDenominator;

                if (!withdraw && (voteResult == VoteResult.APPROVED)) {
                    scrutineer.setDecisionParameters(decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
                }

                pendingDecisionParametersId = 0;

                emit DecisionParameters(id, decisionType, voteResult, decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
            }
        }
    }

    function issueShares(uint256 numberOfShares) public isOwner {
        if (pendingCorporateActionId == 0) {
            (uint256 id, bool noSharesOutstanding) = scrutineer.propose(address(this));

            if (noSharesOutstanding) {
                _mint(address(this), numberOfShares);

                emit CorporateAction(id, CorporateActionType.ISSUE_SHARES, VoteResult.NO_OUTSTANDING_SHARES, numberOfShares, address(0), address(0), 0, address(0), 0);
            } else {
                doRequestCorporateAction(id, CorporateActionType.ISSUE_SHARES, numberOfShares, address(0), address(0), 0, address(0), 0);
            }
        }
    }

    function destroyShares(uint256 numberOfShares) external isOwner {
        if (pendingCorporateActionId == 0) {
            require(shareInfo.getTreasuryShareCount(address(this)) >= numberOfShares, "Cannot destroy more shares than the number of treasury shares");

            (uint256 id, bool noSharesOutstanding) = scrutineer.propose(address(this));

            if (noSharesOutstanding) {
                _burn(address(this), numberOfShares);

                emit CorporateAction(id, CorporateActionType.DESTROY_SHARES, VoteResult.NO_OUTSTANDING_SHARES, numberOfShares, address(0), address(0), 0, address(0), 0);
            } else {
                doRequestCorporateAction(id, CorporateActionType.DESTROY_SHARES, numberOfShares, address(0), address(0), 0, address(0), 0);
            }
        }
    }

    function raiseFunds(uint256 numberOfShares, address exchangeAddress, address currency, uint256 price) external isOwner {
        if (pendingCorporateActionId == 0) {
            require(shareInfo.getTreasuryShareCount(address(this)) >= numberOfShares, "Cannot offer more shares than the number of treasury shares");

            (uint256 id, bool noSharesOutstanding) = scrutineer.propose(address(this));

            if (noSharesOutstanding) {
                shareInfo.registerApprovedExchange(address(this), exchangeAddress);
                increaseAllowance(exchangeAddress, numberOfShares); //only send to safe exchanges, the number of shares are removed from treasury
                IExchange exchange = IExchange(exchangeAddress);
                exchange.ask(address(this), numberOfShares, currency, price);

                emit CorporateAction(id, CorporateActionType.RAISE_FUNDS, VoteResult.NO_OUTSTANDING_SHARES, numberOfShares, exchangeAddress, currency, price, address(0), 0);
            } else {
                doRequestCorporateAction(id, CorporateActionType.RAISE_FUNDS, numberOfShares, exchangeAddress, currency, price, address(0), 0);
            }
        }
    }

    function buyBack(uint256 numberOfShares, address exchangeAddress, address currency, uint256 price) external isOwner {
        if (pendingCorporateActionId == 0) {
            uint256 totalPrice = numberOfShares*price;
            require(shareInfo.getAvailableAmount(address(this), currency) >= totalPrice, "This contract does not have enough of the ERC20 token to buy back all the shares");

            (uint256 id, bool noSharesOutstanding) = scrutineer.propose(address(this));

            if (noSharesOutstanding) {
                shareInfo.registerApprovedExchange(currency, exchangeAddress);
                IERC20(currency).safeIncreaseAllowance(exchangeAddress, totalPrice); //only send to safe exchanges, the total price is locked up
                IExchange exchange = IExchange(exchangeAddress);
                exchange.bid(address(this), numberOfShares, currency, price);

                emit CorporateAction(id, CorporateActionType.BUY_BACK, VoteResult.NO_OUTSTANDING_SHARES, numberOfShares, exchangeAddress, currency, price, address(0), 0);
            } else {
                doRequestCorporateAction(id, CorporateActionType.BUY_BACK, numberOfShares, exchangeAddress, currency, price, address(0), 0);
            }
        }
    }

    function doRequestCorporateAction(uint256 id, CorporateActionType decisionType, uint256 numberOfShares, address exchange, address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount) internal {
        CorporateActionData storage corporateAction = corporateActionsData[id];
        corporateAction.decisionType = decisionType;
        corporateAction.numberOfShares = numberOfShares;
        if (exchange != address(0)) { //only store the exchange address if this is relevant
            corporateAction.exchange = exchange;
        }
        if (currency != address(0)) { //only store currency info if this is relevant
            corporateAction.currency = currency;
            corporateAction.amount = amount;
        }
        if (optionalCurrency != address(0)) { //only store optionalCurrency info if this is relevant
            corporateAction.optionalCurrency = optionalCurrency;
            corporateAction.optionalAmount = optionalAmount;
        }

        pendingCorporateActionId = id;

        emit RequestCorporateAction(id, decisionType, numberOfShares, exchange, currency, amount, optionalCurrency, optionalAmount);
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

    //TODO initiate external proposals (in parallel)
    //TODO approve external proposals
    //TODO withdraw external proposals

    //TODO think about how a company can withdraw funds acquired e.g. through raising funds, may need approval as well!
}