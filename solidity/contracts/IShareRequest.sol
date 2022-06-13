// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

enum DecisionParametersType {
    CHANGE_DECISION_TIME, CHANGE_QUORUM, CHANGE_MAJORITY, CHANGE_ALL
}

enum CorporateActionType {
    ISSUE_SHARES, DESTROY_SHARES, RAISE_FUNDS, BUY_BACK, DISTRIBUTE_DIVIDEND
}

interface IShareRequest {
    event RequestNewOwner(address indexed messageSender, uint256 indexed id, address indexed newOwner); //who manages the smart contract
    event RequestDecisionParametersChange(address indexed messageSender, uint256 indexed id, DecisionParametersType indexed decisionType, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator); //actions changing how decisions are made
    event RequestCorporateAction(address indexed messageSender, uint256 indexed id, CorporateActionType indexed decisionType, uint256 numberOfShares, address exchange, address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount); //corporate actions
    event RequestExternalProposal(address indexed messageSender, uint256 indexed id); //external proposals, context needs to be provided

    function getProposedOwner(uint256 id) external view returns (address);
    function getProposedDecisionParameters(uint256 id) external view returns (DecisionParametersType, uint64, uint64, uint32, uint32, uint32, uint32);
    function getProposedCorporateAction(uint256 id) external view returns (CorporateActionType, uint256, address, address, uint256, address, uint256);

    function requestNewOwner(uint256 id, address newOwner) external;
    function requestDecisionParametersChange(uint256 id, DecisionParametersType decisionType, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) external;
    function requestCorporateAction(uint256 id, CorporateActionType decisionType, uint256 numberOfShares, address exchange, address currency, uint256 amount, address optionalCurrency, uint256 optionalAmount) external;
}