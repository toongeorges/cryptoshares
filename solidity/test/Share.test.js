const assert = require('assert'); //chai does not handle promises in which an error is thrown
const { expect } = require("chai");
const { ethers } = require("hardhat");
const Web3 = require("web3");
hre.Web3 = Web3;
hre.web3 = new Web3(hre.network.provider);

describe("Share test suite", function() {
  let accounts;
  let share;

  beforeEach(async () => {
    // Get a list of all accounts
    accounts = await hre.web3.eth.getAccounts();
  
    const Exchange = await ethers.getContractFactory("Exchange");
    const exchange = await Exchange.deploy();
    await exchange.deployed();

    const Share = await hre.ethers.getContractFactory("Share");
    share = await Share.deploy("Cryptoshare", "CTS", exchange.address);
    await share.deployed();
  });

  describe('Share creation', () => {
    it('can not accept ether payments', async () => {
      await assert.rejects(hre.web3.eth.sendTransaction({ from: accounts[0], to: share.address, value: 200 })); //msg.data is empty, test receive()
      await assert.rejects(hre.web3.eth.sendTransaction({ from: accounts[0], to: share.address, value: 300, data: '0xABCDEF01' })); //msg.data is not empty, test fallback()
    });
  });
});
