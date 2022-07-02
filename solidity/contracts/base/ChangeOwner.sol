// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import 'contracts/base/Proposals.sol';

abstract contract ChangeOwner is Proposals {
    mapping(uint256 => address) private newOwners;

    function getProposedOwner(uint256 id) external view virtual override returns (address) {
        return newOwners[id];
    }

    function changeOwner(address newOwner) external virtual override returns (uint256) {
        newOwners[getNextProposalId()] = newOwner; //lambdas are planned, but not supported yet by Solidity, so initialization has to happen outside the propose method

        return propose(uint16(ActionType.CHANGE_OWNER), executeChangeOwner, requestChangeOwner);
    }

    function executeChangeOwner(uint256 id, VoteResult voteResult) internal returns (bool) {
        address newOwner = newOwners[id];

        if (isApproved(voteResult)) {
            owner = newOwner;
        }

        emit ChangeOwner(id, voteResult, newOwner);

        return true;
    }

    function requestChangeOwner(uint256 id) internal {
        emit RequestChangeOwner(id, newOwners[id]);
    }
}