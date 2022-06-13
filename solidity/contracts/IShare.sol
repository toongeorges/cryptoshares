// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface IShare {
    function changeOwnerOnApproval() external;
    function changeDecisionParametersOnApproval() external;
}