// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import 'contracts/base/Proposals.sol';

struct ExtendedDecisionParameters {
    uint64 decisionTime; //How much time in seconds shareholders have to approve a request
    uint64 executionTime; //How much time in seconds the owner has to execute an approved request after the decisionTime has ended
    //to approve a vote, both the quorum and the majority need to be reached.
    //a vote is approved if and only if the quorum and the majority are reached on the decisionTime, otherwise it is rejected
    uint32 quorumNumerator;     //the required quorum is calculated as quorumNumerator/quorumDenominator
    uint32 quorumDenominator;   //the required quorum is compared to the number of votes that are in favor, against or abstain divided by the total number of votes
    uint32 majorityNumerator;   //the required majority is calculated as majorityNumerator/majorityDenominator and must be greater than 1/2
    uint32 majorityDenominator; //the required majority is compared to the number of votes that are in favor divided by the number of votes that are either in favor or against
    uint16 voteType;
}

abstract contract ChangeDecisionParameters is Proposals {
    mapping(uint256 => ExtendedDecisionParameters) private decisionParametersData;

    function getProposedDecisionParameters(uint256 id) external view virtual override returns (uint16, uint64, uint64, uint32, uint32, uint32, uint32) {
        ExtendedDecisionParameters storage eDP = decisionParametersData[id];
        return (eDP.voteType, eDP.decisionTime, eDP.executionTime, eDP.quorumNumerator, eDP.quorumDenominator, eDP.majorityNumerator, eDP.majorityDenominator);
    }

    function changeDecisionParameters(ActionType voteType, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) external virtual override returns (uint256) {
        return doChangeDecisionParameters(uint16(voteType), decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
    }

    function changeExternalProposalDecisionParameters(uint16 subType, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) external virtual override returns (uint256) {
        return doChangeDecisionParameters(uint16(ActionType.EXTERNAL) + subType, decisionTime, executionTime, quorumNumerator, quorumDenominator, majorityNumerator, majorityDenominator);
    }

    function doChangeDecisionParameters(uint16 voteType, uint64 decisionTime, uint64 executionTime, uint32 quorumNumerator, uint32 quorumDenominator, uint32 majorityNumerator, uint32 majorityDenominator) internal returns (uint256) {
        require(quorumDenominator > 0);
        require(majorityDenominator > 0);
        require((majorityNumerator << 1) >= majorityDenominator);

        uint256 id = getNextProposalId(); //lambdas are planned, but not supported yet by Solidity, so initialization has to happen outside the propose method

        ExtendedDecisionParameters storage eDP = decisionParametersData[id];
        eDP.voteType = voteType;
        eDP.decisionTime = decisionTime;
        eDP.executionTime = executionTime;
        eDP.quorumNumerator = quorumNumerator;
        eDP.quorumDenominator = quorumDenominator;
        eDP.majorityNumerator = majorityNumerator;
        eDP.majorityDenominator = majorityDenominator;

        return propose(uint16(ActionType.CHANGE_DECISION_PARAMETERS), executeSetDecisionParameters, requestSetDecisionParameters);
    }

    function executeSetDecisionParameters(uint256 id, VoteResult voteResult) internal returns (bool) {

        ExtendedDecisionParameters storage eDP = decisionParametersData[id];
        uint16 voteType = eDP.voteType;
        uint64 decisionTime = eDP.decisionTime;
        uint64 executionTime = eDP.executionTime;
        uint32 quorumNumerator = eDP.quorumNumerator;
        uint32 quorumDenominator = eDP.quorumDenominator;
        uint32 majorityNumerator = eDP.majorityNumerator;
        uint32 majorityDenominator = eDP.majorityDenominator;
        
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

        return true;
    }

    function requestSetDecisionParameters(uint256 id) internal {
        ExtendedDecisionParameters storage eDP = decisionParametersData[id];

        emit RequestChangeDecisionParameters(id, eDP.voteType, eDP.decisionTime, eDP.executionTime, eDP.quorumNumerator, eDP.quorumDenominator, eDP.majorityNumerator, eDP.majorityDenominator);
    }
}