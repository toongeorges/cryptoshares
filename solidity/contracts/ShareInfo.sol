// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import 'contracts/IShareInfo.sol';
import 'contracts/IShare.sol';

contract ShareInfo is IShareInfo {
    receive() external payable { //used to receive wei when msg.data is empty
        revert();
    }

    fallback() external payable { //used to receive wei when msg.data is not empty
        revert();
    }
}
