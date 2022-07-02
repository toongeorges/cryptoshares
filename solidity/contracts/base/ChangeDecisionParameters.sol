// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import 'contracts/base/Proposals.sol';

abstract contract ChangeDecisionParameters is Proposals {
    mapping(uint256 => uint16) private decisionParametersVoteType;
    mapping(uint256 => DecisionParameters) private decisionParametersData;

    function getProposedDecisionParameters(uint256 id) external view virtual override returns (uint16, uint64, uint64, uint32, uint32, uint32, uint32) {
        DecisionParameters storage dP = decisionParametersData[id];
        return (decisionParametersVoteType[id], dP.decisionTime, dP.executionTime, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator);
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

        decisionParametersVoteType[id] = voteType;

        DecisionParameters storage dPD = decisionParametersData[id];
        dPD.decisionTime = decisionTime;
        dPD.executionTime = executionTime;
        dPD.quorumNumerator = quorumNumerator;
        dPD.quorumDenominator = quorumDenominator;
        dPD.majorityNumerator = majorityNumerator;
        dPD.majorityDenominator = majorityDenominator;

        return propose(uint16(ActionType.CHANGE_DECISION_PARAMETERS), executeSetDecisionParameters, requestSetDecisionParameters);
    }

    function executeSetDecisionParameters(uint256 id, VoteResult voteResult) internal returns (bool) {
        uint16 voteType = decisionParametersVoteType[id];

        DecisionParameters storage dPD = decisionParametersData[id];
        uint64 decisionTime = dPD.decisionTime;
        uint64 executionTime = dPD.executionTime;
        uint32 quorumNumerator = dPD.quorumNumerator;
        uint32 quorumDenominator = dPD.quorumDenominator;
        uint32 majorityNumerator = dPD.majorityNumerator;
        uint32 majorityDenominator = dPD.majorityDenominator;
        
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
        DecisionParameters storage dP = decisionParametersData[id];

        emit RequestChangeDecisionParameters(id, decisionParametersVoteType[id], dP.decisionTime, dP.executionTime, dP.quorumNumerator, dP.quorumDenominator, dP.majorityNumerator, dP.majorityDenominator);
    }
}