// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import 'contracts/IScrutineer.sol';
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

contract Share is ERC20 {
    using SafeERC20 for IERC20;

    //who manages the smart contract
    event RequestNewOwner(uint256 indexed id, address indexed newOwner);
    event NewOwner(uint256 indexed id, address indexed newOwner, VoteResult indexed voteResult);

    //actions changing how decisions are made
    event RequestDecisionParametersChange(uint256 indexed id, DecisionParametersType indexed decisionType, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator);
    event DecisionParametersChange(uint256 indexed id, DecisionParametersType indexed decisionType, VoteResult indexed voteResult, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator);

    //corporate actions
    event RequestCorporateAction(uint256 indexed id, CorporateActionType indexed decisionType, uint256 numberOfShares, address exchange, address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount);
    event CorporateAction(uint256 indexed id, CorporateActionType indexed decisionType, VoteResult indexed voteResult, uint256 numberOfShares, address exchange, address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount);

    //external proposals, context needs to be provided
    event RequestExternalProposal(uint256 indexed id);
    event ExternalProposal(uint256 indexed id, VoteResult indexed voteResult);

    address public owner;
    IScrutineer public scrutineer;

    mapping(address => uint256) private shareholderIndex;
    address[] private shareholders; //we need to keep track of the shareholders in case of distributing a dividend

    mapping(address => mapping(address => uint256)) private approvedExchangeIndexByToken;
    mapping(address => address[]) private approvedExchangesByToken;

    mapping(uint256 => address) private newOwners;
    mapping(uint256 => DecisionParametersData) private decisionParameters;
    mapping(uint256 => CorporateActionData) private corporateActions;

    uint256 public pendingNewOwnerId;
    uint256 public pendingDecisionParametersId;
    uint256 public pendingCorporateActionId;
    uint256 public pendingExternalProposalCount; //TODO

    modifier isOwner() {
        require(msg.sender == owner);
        _;
    }

    constructor(string memory name, string memory symbol, uint256 numberOfShares, address scrutineerAddress) ERC20(name, symbol) {
        require(numberOfShares > 0); //TODO remove
        scrutineer = IScrutineer(scrutineerAddress);

        //set sensible default values
        scrutineer.setDecisionParameters(2592000, 604800, 0, 1, 1, 2); //2592000s = 30 days, 604800s = 7 days

        doChangeOwner(msg.sender);
        issueShares(numberOfShares);
        shareholders.push(address(this)); //mainly a trick to ensure that if shareholderIndex[shareholderAddress] == 0, then the shareholder has not been registered yet
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



    function getLockedUpAmount(address tokenAddress) public view returns (uint256) {
        address[] storage exchanges = approvedExchangesByToken[tokenAddress];
        IERC20 token = IERC20(tokenAddress);

        uint256 lockedUpAmount = 0;
        for (uint256 i = 0; i < exchanges.length; i++) {
            lockedUpAmount += token.allowance(address(this), exchanges[i]);
        }
        return lockedUpAmount;
    }

    function getAvailableAmount(address tokenAddress) public view returns (uint256) {
        IERC20 token = IERC20(tokenAddress);
        return token.balanceOf(address(this)) - getLockedUpAmount(tokenAddress);
    }

    function getTreasuryShareCount() public view returns (uint256) { //return the number of shares held by the company
        return balanceOf(address(this)) - getLockedUpAmount(address(this));
    }

    function getOutstandingShareCount() public view returns (uint256) { //return the number of shares not held by the company
        return totalSupply() - balanceOf(address(this));
    }

    function getShareholderCount() external view returns (uint256) {
        return shareholders.length - 1; //subtract shareholders[0], which is this contract
    }

    function registerShareholder(address shareholder) external returns (uint256) {
        uint256 index = shareholderIndex[shareholder];
        if (index == 0) { //the shareholder has not been registered yet
            if (balanceOf(shareholder) > 0) { //only register if the address is an actual shareholder
                index = shareholders.length;
                shareholderIndex[shareholder] = index;
                shareholders.push(shareholder);
            }
        }
        return index; //when 0 is returned it means the address is no shareholder, otherwise the index of the shareholder is returned
    }

    function packShareholders() external isOwner { //if a lot of active shareholders change, one may not want to iterate over non existing shareholders anymore when distributing a dividend
        address[] memory old = shareholders; //dynamic memory arrays do not exist, only dynamic storage arrays, so copy the original values to memory and then modify storage
        shareholders = new address[](0); //empty the new storage again, do not use the delete keyword, because this has an unbounded gas cost
        shareholders.push(address(this));
        uint256 packedIndex = 1;

        for (uint256 i = 1; i < old.length; i++) {
            address shareholder = old[i];
            if (balanceOf(shareholder) > 0) {
                shareholderIndex[shareholder] = packedIndex;
                shareholders.push(shareholder);
                packedIndex++;
            } else {
                shareholderIndex[shareholder] = 0;
            }
        }

        if (getOutstandingShareCount() == 0) { //changes do not require approval anymore, resolve all pending votes
            changeOwnerOnApproval();
            changeDecisionParametersOnApproval();

            //TODO resolve corporate action vote
            //TODO resolve multiple! external proposal votes
        }
    }

    function registerApprovedExchange(address tokenAddress, address exchange) internal {
        mapping(address => uint256) storage approvedExchangeIndex = approvedExchangeIndexByToken[tokenAddress];
        uint256 index = approvedExchangeIndex[exchange];
        if (index == 0) { //the exchange has not been registered yet OR was the first registered exchange
            address[] storage approvedExchanges = approvedExchangesByToken[tokenAddress];
            if ((approvedExchanges.length == 0) || (approvedExchanges[0] != exchange)) { //the exchange has not been registered yet
                index = approvedExchanges.length;
                approvedExchangeIndex[exchange] = index;
                approvedExchanges.push(exchange);
            }
        }
    }

    function packApprovedExchanges(address tokenAddress) external isOwner {
        mapping(address => uint256) storage approvedExchangeIndex = approvedExchangeIndexByToken[tokenAddress];
        address[] memory old = approvedExchangesByToken[tokenAddress]; //dynamic memory arrays do not exist, only dynamic storage arrays, so copy the original values to memory and then modify storage
        approvedExchangesByToken[tokenAddress] = new address[](0); //empty the new storage again, do not use the delete keyword, because this has an unbounded gas cost
        address[] storage approvedExchanges = approvedExchangesByToken[tokenAddress];
        uint256 packedIndex = 0;
        IERC20 token = IERC20(tokenAddress);

        for (uint256 i = 0; i < old.length; i++) {
            address exchange = old[i];
            if (token.allowance(address(this), exchange) > 0) {
                approvedExchangeIndex[exchange] = packedIndex;
                approvedExchanges.push(exchange);
                packedIndex++;
            } else {
                approvedExchangeIndex[exchange] = 0;
            }
        }
    }



    function getProposedOwner(uint256 id) external view returns (address) {
        return newOwners[id];
    }

    function getProposedDecisionParameters(uint256 id) external view returns (DecisionParametersType, uint64, uint64, uint32, uint32, uint32, uint32) {
        DecisionParametersData storage dP = decisionParameters[id];
        return (dP.decisionType, dP.decisionTime, dP.executionTime, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator);
    }

    function getProposedCorporateAction(uint256 id) external view returns (CorporateActionType, uint256, address, address, uint256, address, uint256) {
        CorporateActionData storage corporateAction = corporateActions[id];
        return (corporateAction.decisionType, corporateAction.numberOfShares, corporateAction.exchange, corporateAction.currency, corporateAction.amount, corporateAction.optionalCurrency, corporateAction.optionalAmount);
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

    function changeOwnerOnApproval() public {
        uint256 id = pendingNewOwnerId;
        if (id != 0) {
            bool resultHasBeenUpdated = scrutineer.resolveVote(pendingNewOwnerId);

            if (resultHasBeenUpdated) {
                (VoteResult voteResult,,,,,,,,) = scrutineer.getVoteResult(address(this), id);

                address newOwner = newOwners[id];

                if (voteResult == VoteResult.APPROVED) {
                    owner = newOwner;
                }

                pendingNewOwnerId = 0;

                emit NewOwner(id, newOwner, voteResult);
            }
        }
    }

    function withdrawChangeOwnerRequest() external isOwner {
        uint256 id = pendingNewOwnerId;
        if (id != 0) {
            bool withdrawalWasSuccessful = scrutineer.withdrawVote(id);

            if (withdrawalWasSuccessful) {
                (VoteResult voteResult,,,,,,,,) = scrutineer.getVoteResult(address(this), id);

                pendingNewOwnerId = 0;

                emit NewOwner(id, newOwners[id], voteResult);
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

                emit DecisionParametersChange(id, decisionType, VoteResult.NO_OUTSTANDING_SHARES, decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
            } else {
                DecisionParametersData storage dP = decisionParameters[id];
                dP.decisionType = decisionType;
                dP.decisionTime = decisionTime;
                dP.executionTime = executionTime;
                dP.quorumNumerator = quorumNumerator;
                dP.quorumDenominator = quorumDenominator;
                dP.majorityNumerator = majorityNumerator;
                dP.majorityDenominator = majorityDenominator;

                pendingDecisionParametersId = id;

                emit RequestDecisionParametersChange(id, decisionType, decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
            }
        }
    }

    function changeDecisionParametersOnApproval() public {
        uint256 id = pendingDecisionParametersId;
        if (id != 0) {
            bool resultHasBeenUpdated = scrutineer.resolveVote(id);

            if (resultHasBeenUpdated) {
                (VoteResult voteResult,,,,,,,,) = scrutineer.getVoteResult(address(this), id);

                DecisionParametersData storage dP = decisionParameters[id];
                DecisionParametersType decisionType = dP.decisionType;
                uint64 decisionTime = dP.decisionTime;
                uint64 executionTime = dP.executionTime;
                uint32 quorumNumerator = dP.quorumNumerator;
                uint32 quorumDenominator = dP.quorumDenominator;
                uint32 majorityNumerator = dP.majorityNumerator;
                uint32 majorityDenominator = dP.majorityDenominator;

                if (voteResult == VoteResult.APPROVED) {
                    scrutineer.setDecisionParameters(decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
                }

                pendingDecisionParametersId = 0;

                emit DecisionParametersChange(id, decisionType, voteResult, decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
            }
        }
    }

    function withdrawDecisionParametersRequest() external isOwner {
        uint256 id = pendingDecisionParametersId;
        if (id != 0) {
            bool withdrawalWasSuccessful = scrutineer.withdrawVote(id);

            if (withdrawalWasSuccessful) {
                (VoteResult voteResult,,,,,,,,) = scrutineer.getVoteResult(address(this), id);

                DecisionParametersData storage dP = decisionParameters[id];

                pendingDecisionParametersId = 0;

                emit DecisionParametersChange(id, dP.decisionType, voteResult, dP.decisionTime, dP.executionTime, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator);
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
            require(getTreasuryShareCount() >= numberOfShares, "Cannot destroy more shares than the number of treasury shares");

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
            require(getTreasuryShareCount() >= numberOfShares, "Cannot offer more shares than the number of treasury shares");

            (uint256 id, bool noSharesOutstanding) = scrutineer.propose(address(this));

            if (noSharesOutstanding) {
                registerApprovedExchange(address(this), exchangeAddress);
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
            require(getAvailableAmount(currency) >= totalPrice, "This contract does not have enough of the ERC20 token to buy back all the shares");

            (uint256 id, bool noSharesOutstanding) = scrutineer.propose(address(this));

            if (noSharesOutstanding) {
                registerApprovedExchange(currency, exchangeAddress);
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
        CorporateActionData storage corporateAction = corporateActions[id];
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