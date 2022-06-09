// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import 'contracts/Scrutineer.sol';
import 'contracts/IExchange.sol';

contract Share is ERC20 {
    using SafeERC20 for IERC20;

    event NewOwner(uint256 indexed id, address indexed newOwner, VoteResult indexed voteResult);
    event DecisionParametersChange(uint256 indexed id, DecisionActionType indexed actionType, VoteResult indexed voteResult);
    event CorporateAction(uint256 indexed id, CorporateActionType indexed actionType, VoteResult indexed voteResult);

    address public owner;

    Scrutineer public scrutineer;
    
    mapping(address => address[]) private approvedExchangesByToken;

    address[] private shareHolders; //we need to keep track of the shareholders in case of distributing a dividend

    uint256 public newOwnerId;
    uint256 public decisionParametersId;
    uint256 public corporateActionId;
    uint256 public externalProposalId;

    modifier isOwner() {
        require(msg.sender == owner);
        _;
    }

    constructor(string memory name, string memory symbol, uint256 numberOfShares, address scrutineerAddress) ERC20(name, symbol) {
        owner = msg.sender;
        _mint(address(this), numberOfShares);

        scrutineer = Scrutineer(payable(scrutineerAddress));

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
        return totalSupply() - getTreasuryShareCount();
    }

    function getShareHolderCount() external view returns (uint256) {
        return shareHolders.length;
    }

    function changesRequireApproval() public view returns (bool) {
        return shareHolders.length > 0;
    }

    function packShareHolders() external isOwner { //if a lot of active shareholders change, one may not want to iterate over non existing shareholders anymore when distributing a dividend
        uint256 packedIndex = 0;
        address[] memory packed;

        for (uint256 i = 0; i < shareHolders.length; i++) {
            address shareHolder = shareHolders[i];
            if (balanceOf(shareHolder) > 0) {
                packed[packedIndex] = shareHolder;
                packedIndex++;
            }
        }

        shareHolders = packed;

        if (packed.length == 0) { //changes do not require approval anymore, resolve all pending votes
            changeOwnerOnApproval();
            changeDecisionParametersOnApproval();

            //TODO resolve corporate action vote
            //TODO resolve multiple! external proposal votes
        }
    }

    function packApprovedExchanges(address tokenAddress) external isOwner {
        address[] storage approvedExchanges = approvedExchangesByToken[tokenAddress];
        uint256 packedIndex = 0;
        address[] memory packed;
        IERC20 token = IERC20(tokenAddress);

        for (uint256 i = 0; i < approvedExchanges.length; i++) {
            address exchange = approvedExchanges[i];
            if (token.allowance(address(this), exchange) > 0) {
                packed[packedIndex] = exchange;
                packedIndex++;
            }
        }

        approvedExchangesByToken[tokenAddress] = packed;
    }



    function changeOwner(address newOwner) external isOwner {
        if (!changesRequireApproval()) {
            owner = newOwner;

            emit NewOwner(newOwnerId, newOwner, VoteResult.NO_OUTSTANDING_SHARES);
            newOwnerId++;
        } else {
            scrutineer.requestChangeOwner(newOwnerId, newOwner);
        }
    }

    function changeOwnerOnApproval() public {
        bool isEmitEvent;
        VoteResult result;
        address newOwner;

        (isEmitEvent, result, newOwner) = scrutineer.getNewOwnerResults(newOwnerId, changesRequireApproval(), getOutstandingShareCount());

        if (isEmitEvent) {
            if (result == VoteResult.APPROVED) {
                owner = newOwner;
            }

            emit NewOwner(newOwnerId, newOwner, result);
            newOwnerId++;
        }
    }

    function withdrawChangeOwnerRequest() external isOwner {
        bool isWithdrawn;
        VoteResult result;
        address newOwner;

        (isWithdrawn, result, newOwner) = scrutineer.withdrawChangeOwner(newOwnerId);
        if (isWithdrawn) {
            emit NewOwner(newOwnerId, newOwner, result);
        }
    }

    function changeDecisionTime(uint64 decisionTime, uint64 executionTime) external isOwner {
        doChangeDecisionParameters(DecisionActionType.CHANGE_DECISION_TIME, decisionTime, executionTime, 0, 0, 0, 0);
    }

    function changeQuorum(uint32 quorumNumerator, uint32 quorumDenominator) external isOwner {
        doChangeDecisionParameters(DecisionActionType.CHANGE_QUORUM, 0, 0, quorumNumerator, quorumDenominator, 0, 0);
    }

    function changeMajority(uint32 majorityNumerator, uint32 majorityDenominator) external isOwner {
        doChangeDecisionParameters(DecisionActionType.CHANGE_MAJORITY, 0, 0, 0, 0, majorityNumerator, majorityDenominator);
    }

    function changeDecisionParameters(uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) external isOwner {
        doChangeDecisionParameters(DecisionActionType.CHANGE_ALL, decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
    }

    function doChangeDecisionParameters(DecisionActionType actionType, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) internal {
        if (!changesRequireApproval()) {
            if (actionType == DecisionActionType.CHANGE_DECISION_TIME) {
                scrutineer.setDecisionTime(decisionTime, executionTime);
            } else if (actionType == DecisionActionType.CHANGE_QUORUM) {
                scrutineer.setQuorum(quorumNumerator, quorumDenominator);
            } else if (actionType == DecisionActionType.CHANGE_MAJORITY) {
                scrutineer.setMajority(majorityNumerator, majorityDenominator);
            } else { //actionType == DecisionActionType.CHANGE_ALL
                scrutineer.setDecisionParameters(decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
            }

            emit DecisionParametersChange(decisionParametersId, actionType, VoteResult.NO_OUTSTANDING_SHARES);
            decisionParametersId++;
        } else {
            scrutineer.requestChangeDecisionParameters(decisionParametersId, actionType, decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
        }
    }

    function changeDecisionParametersOnApproval() public {
        bool isEmitEvent;
        VoteResult result;
        DecisionActionType actionType;
        uint64 decisionTime;
        uint64 executionTime;
        uint32 quorumNumerator;
        uint32 quorumDenominator;
        uint32 majorityNumerator = 1;
        uint32 majorityDenominator = 2;

        (isEmitEvent, result, actionType, decisionTime, executionTime, quorumNumerator, quorumDenominator) = scrutineer.getDecisionParametersResults(decisionParametersId, changesRequireApproval(), getOutstandingShareCount());

        if (isEmitEvent) {
            if (result == VoteResult.APPROVED) {
                scrutineer.setDecisionParameters(decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
            }

            emit DecisionParametersChange(decisionParametersId, actionType, result);
            decisionParametersId++;
        }
    }

    function withdrawChangeDecisionParametersRequest() external isOwner {
        bool isWithdrawn;
        VoteResult result;
        DecisionActionType actionType;

        (isWithdrawn, result, actionType) = scrutineer.withdrawChangeDecisionParameters(decisionParametersId);
        if (isWithdrawn) {
            emit DecisionParametersChange(decisionParametersId, actionType, result);
        }
    }

    function issueShares(uint256 numberOfShares) external isOwner {
        if (!changesRequireApproval()) {
            _mint(address(this), numberOfShares);

            emit CorporateAction(corporateActionId, CorporateActionType.ISSUE_SHARES, VoteResult.NO_OUTSTANDING_SHARES);
            corporateActionId++;
        } else {
            scrutineer.requestCorporateAction(corporateActionId, CorporateActionType.ISSUE_SHARES, numberOfShares, address(0), address(0), 0, address(0), 0);
        }
    }

    function destroyShares(uint256 numberOfShares) external isOwner {
        require(getTreasuryShareCount() >= numberOfShares, "Cannot destroy more shares than the number of treasury shares");
        if (!changesRequireApproval()) {
            _burn(address(this), numberOfShares);

            emit CorporateAction(corporateActionId, CorporateActionType.DESTROY_SHARES, VoteResult.NO_OUTSTANDING_SHARES);
            corporateActionId++;
        } else {
            scrutineer.requestCorporateAction(corporateActionId, CorporateActionType.DESTROY_SHARES, numberOfShares, address(0), address(0), 0, address(0), 0);
        }
    }

    function raiseFunds(uint256 numberOfShares, address exchange, address currency, uint256 price) external isOwner {
        require(getTreasuryShareCount() >= numberOfShares, "Cannot offer more shares than the number of treasury shares");
        if (!changesRequireApproval()) {
            increaseAllowance(exchange, numberOfShares); //only send to safe exchanges, the from address of the transfer == msg.sender == the address of this contract, these shares are removed from treasury
            IExchange(exchange).ask(address(this), numberOfShares, currency, price);

            emit CorporateAction(corporateActionId, CorporateActionType.RAISE_FUNDS, VoteResult.NO_OUTSTANDING_SHARES);
            corporateActionId++;
        } else {
            scrutineer.requestCorporateAction(corporateActionId, CorporateActionType.RAISE_FUNDS, numberOfShares, exchange, currency, price, address(0), 0);
        }
    }

    function buyBack(uint256 numberOfShares, address exchange, address currency, uint256 price) external isOwner {
        uint256 totalPrice = numberOfShares*price;
        require(getAvailableAmount(currency) >= totalPrice, "This contract does not have enough of the ERC20 token to buy back all the shares");
        if (!changesRequireApproval()) {
            IERC20(currency).safeIncreaseAllowance(exchange, totalPrice); //only send to safe exchanges, the from address of the transfer == msg.sender == the address of this contract
            IExchange(exchange).bid(address(this), numberOfShares, currency, price);

            emit CorporateAction(corporateActionId, CorporateActionType.BUY_BACK, VoteResult.NO_OUTSTANDING_SHARES);
            corporateActionId++;
        } else {
            scrutineer.requestCorporateAction(corporateActionId, CorporateActionType.BUY_BACK, numberOfShares, exchange, currency, price, address(0), 0);
        }
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