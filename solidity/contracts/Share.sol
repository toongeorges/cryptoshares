// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import 'contracts/IShare.sol';
import 'contracts/base/ChangeOwner.sol';
import 'contracts/base/ChangeDecisionParameters.sol';
import 'contracts/base/CorporateActions.sol';
import 'contracts/base/ExternalProposal.sol';

contract Share is IShare, ChangeOwner, ChangeDecisionParameters, CorporateActions, ExternalProposal {
    constructor(string memory name, string memory symbol, address exchangeAddress) ERC20(name, symbol) {
        exchange = IExchange(exchangeAddress);
    }



    function decimals() public pure virtual override returns (uint8) {
        return 0;
    }

    receive() external payable { //used to receive wei when msg.data is empty
        revert DoNotAcceptEtherPayments();
    }

    fallback() external payable { //used to receive wei when msg.data is not empty
        revert DoNotAcceptEtherPayments();
    }



    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        bool success = super.transfer(to, amount); //has to happen before the registerTransfer method, because shares of the receiver may be burnt in case a reverse split if going on

        registerTransfer(msg.sender, to, amount);

        return success; //should be always true, the base implementation reverts if something goes wrong, however returning the boolean literal "true" increases the size of the compiled contract
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        bool success = super.transferFrom(from, to, amount); //has to happen before the registerTransfer method, because shares of the receiver may be burnt in case a reverse split if going on

        registerTransfer(from, to, amount);

        return success; //should be always true, the base implementation reverts if something goes wrong, however returning the boolean literal "true" increases the size of the compiled contract
    }

    function registerTransfer(address from, address to, uint256 transferAmount) internal {
        if (transferAmount > 0) { //the ERC20 base class seems not to care if amount == 0, though no registration should happen then
            registerShareholder(to);

            uint256 id = pendingRequestId;
            if (id != 0) { //if there is a request pending
                VoteParameters storage vP = getProposal(id);
                VoteResult result = vP.result;
                if (result == VoteResult.PARTIAL_VOTE_COUNT) {
                    Voting.transferVotes(vP, from, to, transferAmount);
                } else if (result == VoteResult.PARTIAL_EXECUTION) {
                    transferCorporateActionExecution(from, to, transferAmount, vP, id);
                }
            }
        }
    }



    //preferably resolve the vote at once, so voters can not trade shares during the resolution
    function resolveVote() public virtual override {
        resolveVote(getNumberOfVotes(pendingRequestId));
    }

    //if a vote has to be resolved in multiple times, because a gas limit prevents doing it at once, only allow the owner to do so
    function resolveVote(uint256 pageSize) public virtual override returns (uint256) {
        uint256 id = pendingRequestId;
        if (id != 0) {
            VoteParameters storage vP = getProposal(id);

            uint16 decisionType = vP.voteType;
            (bool isUpdated, uint256 remainingVotes) = Voting.resolveVote(vP, isAlwaysApprovedCorporateAction(decisionType), isPartialExecutionCorporateAction(decisionType, id), IERC20(this), getOutstandingShareCount(), pageSize);

            if (remainingVotes > 0) {
                return remainingVotes;
            } else if (isUpdated) {
                doResolve(id, vP.voteType, vP.result);

                return remainingVotes;
            } else {
                revert RequestNotResolved();
            }
        } else {
            revert NoRequestPending();
        }
    }

    function withdrawVote() external virtual override isOwner {
        uint256 id = pendingRequestId;
        if (id != 0) {
            VoteParameters storage vP = getProposal(id);
            if (Voting.withdrawVote(vP)) {
                doResolve(id, vP.voteType, vP.result);
            } else {
                revert RequestNotResolved();
            }
        } else {
            revert NoRequestPending();
        }
    }

    function doResolve(uint256 id, uint16 voteTypeInt, VoteResult voteResult) internal {
        bool isFullyExecuted = true;
        if (voteTypeInt >= uint16(ActionType.EXTERNAL)) {
            executeExternalProposal(id, voteResult);
        } else {
            ActionType voteType = ActionType(voteTypeInt);
            if (voteType > ActionType.CHANGE_DECISION_PARAMETERS) { //this is a corporate action
                isFullyExecuted = executeCorporateAction(id, voteResult);
            } else if (voteType == ActionType.CHANGE_DECISION_PARAMETERS) {
                executeSetDecisionParameters(id, voteResult);
            } else if (voteType == ActionType.CHANGE_OWNER) {
                executeChangeOwner(id, voteResult);
            } else { //cannot resolve ActionType.DEFAULT, which is not an action
                revert RequestNotResolved();
            }
        }

        if (isFullyExecuted) {
            pendingRequestId = 0;
        }
    }
}