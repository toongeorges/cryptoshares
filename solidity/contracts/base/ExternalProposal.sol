// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import 'contracts/base/Proposals.sol';

abstract contract ExternalProposal is Proposals {
    function makeExternalProposal() external virtual override returns (uint256) {
        return makeExternalProposal(0);
    }

    function makeExternalProposal(uint16 subType) public virtual override returns (uint256) {
        return propose(uint16(ActionType.EXTERNAL) + subType, executeExternalProposal, requestExternalProposal);
    }

    function executeExternalProposal(uint256 id, VoteResult voteResult) internal returns (bool) {
        emit ExternalProposal(id, voteResult);

        return true;
    }

    function requestExternalProposal(uint256 id) internal {
        emit RequestExternalProposal(id);
    }
}