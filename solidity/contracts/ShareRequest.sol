// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import 'contracts/IShareRequest.sol';

struct DecisionParametersData { //this is the same struct as the Scrutineer's DecisionParameters struct, with one extra field: decisionType
    DecisionParametersType decisionType;
    uint64 decisionTime; //How much time in seconds shareholders have to approve a request
    uint64 executionTime; //How much time in seconds the owner has to execute an approved request after the decisionTime has ended
    uint32 quorumNumerator;
    uint32 quorumDenominator;
    uint32 majorityNumerator;
    uint32 majorityDenominator;
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

contract ShareRequest is IShareRequest {
    mapping(address => mapping(uint256 => address)) private newOwners;
    mapping(address => mapping(uint256 => DecisionParametersData)) private decisionParameters;
    mapping(address => mapping(uint256 => CorporateActionData)) private corporateActions;

    receive() external payable { //used to receive wei when msg.data is empty
        revert("This is a free service"); //as long as Ether is not ERC20 compliant
    }

    fallback() external payable { //used to receive wei when msg.data is not empty
        revert("This is a free service"); //as long as Ether is not ERC20 compliant
    }



    function getProposedOwner(uint256 id) external view override returns (address) {
        return newOwners[msg.sender][id];
    }

    function getProposedDecisionParameters(uint256 id) external view override returns (DecisionParametersType, uint64, uint64, uint32, uint32, uint32, uint32) {
        DecisionParametersData storage dP = decisionParameters[msg.sender][id];
        return (dP.decisionType, dP.decisionTime, dP.executionTime, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator);
    }

    function getProposedCorporateAction(uint256 id) external view override returns (CorporateActionType, uint256, address, address, uint256, address, uint256) {
        CorporateActionData storage corporateAction = corporateActions[msg.sender][id];
        return (corporateAction.decisionType, corporateAction.numberOfShares, corporateAction.exchange, corporateAction.currency, corporateAction.amount, corporateAction.optionalCurrency, corporateAction.optionalAmount);
    }



    function requestNewOwner(uint256 id, address newOwner) external override {
                newOwners[msg.sender][id] = newOwner;

                emit RequestNewOwner(msg.sender, id, newOwner);
    }

    function requestDecisionParametersChange(uint256 id, DecisionParametersType decisionType, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) external override {
                DecisionParametersData storage dP = decisionParameters[msg.sender][id];
                dP.decisionType = decisionType;
                dP.decisionTime = decisionTime;
                dP.executionTime = executionTime;
                dP.quorumNumerator = quorumNumerator;
                dP.quorumDenominator = quorumDenominator;
                dP.majorityNumerator = majorityNumerator;
                dP.majorityDenominator = majorityDenominator;

                emit RequestDecisionParametersChange(msg.sender, id, decisionType, decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
    }

    function requestCorporateAction(uint256 id, CorporateActionType decisionType, uint256 numberOfShares, address exchange, address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount) external override {
        CorporateActionData storage corporateAction = corporateActions[msg.sender][id];
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

        emit RequestCorporateAction(msg.sender, id, decisionType, numberOfShares, exchange, currency, amount, optionalCurrency, optionalAmount);
    }
}