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

    mapping(uint256 => address) private newOwners;
    mapping(uint256 => DecisionParameters) private decisionParametersData;
    mapping(uint256 => CorporateActionData) private corporateActionsData;

    uint256 public pendingNewOwnerId;
    uint256 public pendingDecisionParametersId;
    uint256 public pendingCorporateActionId;

    mapping(address => uint256) private shareholderIndex;
    address[] private shareholders; //we need to keep track of the shareholders in case of distributing a dividend

    mapping(address => mapping(address => uint256)) private approvedExchangeIndexByToken;
    mapping(address => address[]) private approvedExchangesByToken;

    modifier isOwner() {
        _isOwner(); //putting the code in a fuction reduces the size of the compiled smart contract!
        _;
    }

    function _isOwner() internal view {
        require(msg.sender == owner);
    }

    constructor(string memory name, string memory symbol, address scrutineerAddress) ERC20(name, symbol) {
        scrutineer = IScrutineer(scrutineerAddress);
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
        return IERC20(tokenAddress).balanceOf(address(this)) - getLockedUpAmount(tokenAddress);
    }

    function verifyAvailable(address currency, uint256 amount) internal view {
        require(getAvailableAmount(currency) >= amount);
    }

    function getTreasuryShareCount() public view returns (uint256) { //return the number of shares held by the company
        return balanceOf(address(this)) - getLockedUpAmount(address(this));
    }

    function getOutstandingShareCount() public view returns (uint256) { //return the number of shares not held by the company
        return totalSupply() - balanceOf(address(this));
    }

    //getMaxOutstandingShareCount() >= getOutstandingShareCount(), we are also counting the shares that have been locked up in exchanges and may be sold
    function getMaxOutstandingShareCount() public view returns (uint256) {
        return totalSupply() - getTreasuryShareCount();
    }

    function getShareholderCount() external view returns (uint256) {
        return shareholders.length;
    }

    function registerShareholder(address shareholder) external returns (uint256) {
        if (shareholderIndex[shareholder] == 0) { //the shareholder has not been registered yet OR the shareholder was the first shareholder
            if ((shareholders.length == 0) || (shareholders[0] != shareholder)) { //the shareholder has not been registered yet
                return doRegisterShareHolder(shareholder);
            }
        }
        return 0;
    }

    function packShareholders() external { //if a lot of active shareholders change, one may not want to iterate over non existing shareholders anymore when distributing a dividend
        address[] memory old = shareholders; //dynamic memory arrays do not exist, only dynamic storage arrays, so copy the original values to memory and then modify storage
        shareholders = new address[](0); //empty the new storage again, do not use the delete keyword, because this has an unbounded gas cost

        for (uint256 i = 0; i < old.length; i++) {
            doRegisterShareHolder(old[i]);
        }

        if (getOutstandingShareCount() == 0) { //changes do not require approval anymore, resolve all pending votes
            changeOwnerOnApproval();
            changeDecisionParametersOnApproval();
            corporateActionOnApproval();
        }
    }

    function doRegisterShareHolder(address shareholder) internal returns (uint256) {
        if (balanceOf(shareholder) > 0) { //only register if the address is an actual shareholder
            uint256 index = shareholders.length;
            shareholderIndex[shareholder] = index;
            shareholders.push(shareholder);
            return index;
        } else {
            shareholderIndex[shareholder] = 0;
            return 0;
        }
    }

    function registerExchange(address exchange, address tokenAddress) internal returns (uint256) {
        mapping(address => uint256) storage approvedExchangeIndex = approvedExchangeIndexByToken[tokenAddress];
        uint256 index = approvedExchangeIndex[exchange];
        if (index == 0) { //the exchange has not been registered yet OR was the first registered exchange
            address[] storage approvedExchanges = approvedExchangesByToken[tokenAddress];
            if ((approvedExchanges.length == 0) || (approvedExchanges[0] != exchange)) { //the exchange has not been registered yet
                return doRegisterExchange(exchange, tokenAddress, approvedExchangeIndex, approvedExchanges);
            }
        }
        return index;
    }

    function packExchanges(address tokenAddress) external {
        address[] memory old = approvedExchangesByToken[tokenAddress]; //dynamic memory arrays do not exist, only dynamic storage arrays, so copy the original values to memory and then modify storage
        approvedExchangesByToken[tokenAddress] = new address[](0); //empty the new storage again, do not use the delete keyword, because this has an unbounded gas cost

        for (uint256 i = 0; i < old.length; i++) {
            doRegisterExchange(old[i], tokenAddress, approvedExchangeIndexByToken[tokenAddress], approvedExchangesByToken[tokenAddress]);
        }
    }

    function doRegisterExchange(address exchange, address tokenAddress, mapping(address => uint256) storage approvedExchangeIndex, address[] storage approvedExchanges) internal returns (uint256) {
        if (IERC20(tokenAddress).allowance(address(this), exchange) > 0) {
            uint256 index = approvedExchanges.length;
            approvedExchangeIndex[exchange] = index;
            approvedExchanges.push(exchange);
            return index;
        } else {
            approvedExchangeIndex[exchange] = 0;
            return 0;
        }
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
            (uint256 id, bool noSharesOutstanding) = doPropose();

            if (noSharesOutstanding) {
                doChangeOwner(id, VoteResult.NO_OUTSTANDING_SHARES, newOwner);
            } else {
                newOwners[id] = newOwner;

                pendingNewOwnerId = id;

                emit RequestNewOwner(id, newOwner);
            }
        }
    }

    function changeOwnerOnApproval() public override {
        resolveNewOwner(false, pendingNewOwnerId);
    }

    function withdrawChangeOwnerRequest() external override isOwner {
        resolveNewOwner(true, pendingNewOwnerId);
    }

    function resolveNewOwner(bool withdraw, uint256 id) internal {
        if (resultHasBeenUpdated(id, withdraw)) {
            VoteResult voteResult = doGetVoteResults(id);

            doChangeOwner(id, voteResult, newOwners[id]);

            pendingNewOwnerId = 0;
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
            (uint256 id, bool noSharesOutstanding) = doPropose();

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

    function changeDecisionParametersOnApproval() public override {
        resolveDecisionParametersChange(false, pendingDecisionParametersId);
    }

    function withdrawChangeDecisionParametersRequest() external override isOwner {
        resolveDecisionParametersChange(true, pendingDecisionParametersId);
    }

    function resolveDecisionParametersChange(bool withdraw, uint256 id) internal {
        if (resultHasBeenUpdated(id, withdraw)) {
            VoteResult voteResult = doGetVoteResults(id);

            DecisionParameters storage dP = decisionParametersData[id];
            doSetDecisionParameters(id, voteResult, dP.decisionTime, dP.executionTime, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator);

            pendingDecisionParametersId = 0;
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
        require(getTreasuryShareCount() >= numberOfShares);
        doCorporateAction(CorporateActionType.RAISE_FUNDS, numberOfShares, exchangeAddress, currency, price, address(0), 0);
    }

    function buyBack(uint256 numberOfShares, address exchangeAddress, address currency, uint256 price) external override {
        verifyAvailable(currency, numberOfShares*price);
        doCorporateAction(CorporateActionType.BUY_BACK, numberOfShares, exchangeAddress, currency, price, address(0), 0);
    }

    function cancelOrder(address exchangeAddress, uint256 orderId) external override {
        doCorporateAction(CorporateActionType.CANCEL_ORDER, 0, exchangeAddress, address(0), orderId, address(0), 0);
    }

    function reverseSplit(address currency, uint256 amount, uint256 reverseSplitToOne) external override {
        require(getLockedUpAmount(address(this)) == 0); //do not start a reverse split if some exchanges may still be selling shares, cancel these orders first
        //we are not verifying here that company has enough funds to distribute the currency to each possible outstanding share (possible worst case if everyone owns 1 share)
        //instead the execution of the reverse split will revert if not enough funds are available, in which case the owner can still withdraw the reverse split
        doCorporateAction(CorporateActionType.REVERSE_SPLIT, 0, address(0), currency, amount, address(0), reverseSplitToOne);
    }

    function distributeDividend(address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount) external override {
        uint256 maxOutstandingShareCount = getMaxOutstandingShareCount();
        verifyAvailable(currency, maxOutstandingShareCount*amount);

        if (optionalCurrency != address(0)) {
            verifyAvailable(optionalCurrency, maxOutstandingShareCount*optionalAmount);
        }

        doCorporateAction(CorporateActionType.DISTRIBUTE_DIVIDEND, maxOutstandingShareCount, address(0), currency, amount, optionalCurrency, optionalAmount);
    }

    function withdrawFunds(address destination, address currency, uint256 amount) external override {
        verifyAvailable(currency, amount);
        doCorporateAction(CorporateActionType.WITHDRAW_FUNDS, 0, destination, currency, amount, address(0), 0);
    }

    function doCorporateAction(CorporateActionType decisionType, uint256 numberOfShares, address exchangeAddress, address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount) internal isOwner {
        if (pendingCorporateActionId == 0) {
            (uint256 id, bool noSharesOutstanding) = doPropose();

            if (noSharesOutstanding) {
                executeCorporateAction(id, VoteResult.NO_OUTSTANDING_SHARES, decisionType, numberOfShares, exchangeAddress, currency, amount, optionalCurrency, optionalAmount);
            } else {
                doRequestCorporateAction(id, decisionType, numberOfShares, exchangeAddress, currency, amount, optionalCurrency, optionalAmount);
            }
        }
    }

    function doRequestCorporateAction(uint256 id, CorporateActionType decisionType, uint256 numberOfShares, address exchange, address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount) internal {
        if (numberOfShares == 0) {
            numberOfShares = getMaxOutstandingShareCount();
        }

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


    function corporateActionOnApproval() public override {
        resolveCorporateAction(false, pendingCorporateActionId);
    }

    function withdrawCorporateActionRequest() external override isOwner {
        resolveCorporateAction(true, pendingCorporateActionId);
    }

    function resolveCorporateAction(bool withdraw, uint256 id) internal {
        if (resultHasBeenUpdated(id, withdraw)) {
            VoteResult voteResult = doGetVoteResults(id);

            CorporateActionData storage cA = corporateActionsData[id];
            CorporateActionType decisionType = cA.decisionType;
            address currency = cA.currency;
            uint256 amount = cA.amount;
            address optionalCurrency = cA.optionalCurrency;
            uint256 optionalAmount = cA.optionalAmount;

            executeCorporateAction(id, voteResult, decisionType, cA.numberOfShares, cA.exchange, currency, amount, optionalCurrency, optionalAmount);

            pendingCorporateActionId = 0;

            if ((optionalCurrency != address(0)) && isApproved(voteResult)) { //(optionalCurrency != address(0)) implies that (decisionType == CorporateActionType.DISTRIBUTE_DIVIDEND)
                doCorporateAction(CorporateActionType.DISTRIBUTE_OPTIONAL_DIVIDEND, 0, address(0), currency, amount, optionalCurrency, optionalAmount);
            }
        }
    }

    function executeCorporateAction(uint256 id, VoteResult voteResult, CorporateActionType decisionType, uint256 numberOfShares, address exchangeAddress, address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount) internal {
        if (isApproved(voteResult)) {
            if (decisionType == CorporateActionType.DISTRIBUTE_DIVIDEND) { //should be the most common action
                if (optionalCurrency == address(0)) {
                    IERC20 erc20 = IERC20(currency);
                    for (uint256 i = 0; i < shareholders.length; i++) {
                        address shareholder = shareholders[i];
                        safeTransfer(erc20, shareholder, balanceOf(shareholder)*amount);
                    }
                } //else a DISTRIBUTE_OPTIONAL_DIVIDEND corporate action will be triggered in the resolveCorporateAction() method
            } else if (decisionType == CorporateActionType.ISSUE_SHARES) {
                _mint(address(this), numberOfShares);
            } else if (decisionType == CorporateActionType.DESTROY_SHARES) {
                _burn(address(this), numberOfShares);
            } else if (decisionType == CorporateActionType.RAISE_FUNDS) {
                increaseAllowance(exchangeAddress, numberOfShares); //only send to safe exchanges, the number of shares are removed from treasury
                registerExchange(exchangeAddress, address(this)); //execute only after the allowance has been increased, because this method implicitly does an allowance check (for code reuse to minimize the contract size)
                IExchange exchange = IExchange(exchangeAddress);
                exchange.ask(address(this), numberOfShares, currency, amount);
            } else if (decisionType == CorporateActionType.BUY_BACK) {
                IERC20(currency).safeIncreaseAllowance(exchangeAddress, numberOfShares*amount); //only send to safe exchanges, the total price is locked up
                registerExchange(exchangeAddress, currency); //execute only after the allowance has been increased, because this method implicitly does an allowance check (for code reuse to minimize the contract size)
                IExchange exchange = IExchange(exchangeAddress);
                exchange.bid(address(this), numberOfShares, currency, amount);
            } else if (decisionType == CorporateActionType.CANCEL_ORDER) {
                IExchange exchange = IExchange(exchangeAddress);
                exchange.cancel(amount);
            } else if (decisionType == CorporateActionType.REVERSE_SPLIT) {
                doReverseSplit(address(this), optionalAmount);

                uint256 availableAmount = getAvailableAmount(currency); //do not execute the getAvailableAmount() method every time again in the loop!
                IERC20 erc20 = IERC20(currency);
                for (uint256 i = 0; i < shareholders.length; i++) {
                    address shareholder = shareholders[i];

                    //pay out fractional shares
                    uint256 payOut = (balanceOf(shareholder)%optionalAmount)*amount;
                    if (availableAmount >= payOut) { //availableAmount may be < erc20.balanceOf(address(this)), because we may still have a pending allowance at an exchange!
                        safeTransfer(erc20, shareholder, payOut);
                        availableAmount -= payOut;
                    } else {
                        revert(); //run out of funds
                    }

                    //reduce the stake of the shareholder from stake -> stake/optionalAmount == stake - (stake - stake/optionalAmount)
                    doReverseSplit(shareholder, optionalAmount);
                }
            } else if (decisionType == CorporateActionType.WITHDRAW_FUNDS) {
                safeTransfer(IERC20(currency), exchangeAddress, amount); //we have to transfer, we cannot work with safeIncreaseAllowance, because unlike an exchange, which we can choose, we have no control over how the currency will be spent
            } else { //decisionType == CorporateActionType.DISTRIBUTE_OPTIONAL_DIVIDEND, should be a safe default action
                //work around there being no memory mapping in Solidity
                IERC20 optionalERC20 = IERC20(optionalCurrency);
                Vote[] memory votes = scrutineer.getVotes(pendingNewOwnerId);
                for (uint256 i = 0; i < votes.length; i++) {
                    Vote memory v = votes[i];
                    if (v.choice == VoteChoice.IN_FAVOR) {
                        address shareholder = v.voter;
                        optionalERC20.safeIncreaseAllowance(shareholder, balanceOf(shareholder)*optionalAmount);
                    }
                }

                IERC20 erc20 = IERC20(currency);
                for (uint256 i = 0; i < shareholders.length; i++) {
                    address shareholder = shareholders[i];
                    uint256 optionalAllowance = optionalERC20.allowance(address(this), shareholder);
                    if (optionalAllowance > 0) {
                        optionalERC20.safeDecreaseAllowance(shareholder, optionalAllowance);
                        safeTransfer(optionalERC20, shareholder, optionalAllowance);
                    } else {
                        safeTransfer(erc20, shareholder, balanceOf(shareholder)*amount);
                    }
                }
            }
        }

        emit CorporateAction(id, decisionType, voteResult, numberOfShares, exchangeAddress, currency, amount, optionalCurrency, optionalAmount);
    }

    function doPropose() internal returns (uint256, bool) {
        return scrutineer.propose(address(this));
    }

    function resultHasBeenUpdated(uint256 id, bool withdraw) internal returns (bool) {
        return (id != 0) && (withdraw ? scrutineer.withdrawVote(id) : scrutineer.resolveVote(id)); //return true if a result is pending (id != 0) and if the vote has been withdrawn or resolved
    }

    function doGetVoteResults(uint256 id) internal view returns (VoteResult) {
        return scrutineer.getVoteResult(address(this), id);
    }

    function isApproved(VoteResult voteResult) internal pure returns (bool) {
        return ((voteResult == VoteResult.APPROVED) || (voteResult == VoteResult.NO_OUTSTANDING_SHARES));
    }

    function safeTransfer(IERC20 token, address destination, uint256 amount) internal {
        token.safeTransfer(destination, amount);
    }

    function doReverseSplit(address account, uint256 reverseSplitRatio) internal {
        uint256 stake = balanceOf(account);
        //reduce the treasury shares from stake -> stake/reverseSplitRatio == stake - (stake - stake/reverseSplitRatio)
        _burn(account, stake - (stake/reverseSplitRatio));
    }
}