// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

contract Share is ERC20 {
    //use enum do define action
    //zet stemmen vast
    //scrutineer en share contract samen
    address public owner;
    address[] public shareHolders;

    event NewOwner(address indexed newOwner);

    modifier isOwner() {
        require(msg.sender == owner);
        _;
    }

    constructor(string memory name, string memory symbol, uint256 numberOfShares) ERC20(name, symbol) {
        require(numberOfShares > 0);
        owner = msg.sender;
        _mint(address(this), numberOfShares);
        emit NewOwner(owner);
    }

    function decimals() public pure override returns (uint8) {
        return 0;
    }

    function changeOwner(address newOwner) external isOwner {
        owner = newOwner;
        emit NewOwner(newOwner);
    }

    function issueShares(uint256 numberOfShares) external isOwner {
        require(numberOfShares > 0);
        _mint(address(this), numberOfShares); //issued amount is stored in Transfer event from address 0
    }

    function burnShares(uint256 numberOfShares) external isOwner {
        require(numberOfShares > 0);
        _burn(address(this), numberOfShares); //burned amount is stored in Transfer event to address 0
    }

    //used to receive wei when msg.data is empty
    receive() external payable {}

    //used to receive wei when msg.data is not empty
    fallback() external payable {}

    function getWeiBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getTokenBalance(address tokenAddress) external view returns (uint256) {
        IERC20 token = IERC20(tokenAddress);
        return token.balanceOf(address(this));
    }

    //TODO distribute ether and ERC20
}