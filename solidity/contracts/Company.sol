// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract Company is ERC20 {
    address private owner;
    mapping(address => uint256) private tokenBalances;

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

    function getOwner() external view returns (address) {
        return owner;
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

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

    // Fallback function is called when msg.data is not empty
    fallback() external payable {}

    function getEtherBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getTokenBalance(address ierc20Address) external view returns (uint256) {
        return tokenBalances[ierc20Address];
    }
}