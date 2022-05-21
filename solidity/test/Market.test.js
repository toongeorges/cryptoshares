const assert = require('assert');
const ganache = require('ganache-cli');
const Web3 = require('web3');
const web3 = new Web3(ganache.provider());
 
const contracts = require('../compile');
 
let accounts;
let testGold;
let market;
 
beforeEach(async () => {
  // Get a list of all accounts
  accounts = await web3.eth.getAccounts();

  testGold = await new web3.eth.Contract(contracts.TestGold.abi)
    .deploy({
      data: contracts.TestGold.evm.bytecode.object,
      arguments: [9000],
    })
    .send({ from: accounts[0], gas: '3000000' });

  market = await new web3.eth.Contract(contracts.Market.abi)
    .deploy({
      data: contracts.Market.evm.bytecode.object,
      arguments: [],
    })
    .send({ from: accounts[0], gas: '3000000' });
});
 
describe('Market creation', () => {
  it('deploys a contract', () => {
    assert.ok(testGold.options.address);
    assert.ok(market.options.address);
  });
  it('can accept ether payments', async () => {
    let initialBalance = await market.methods.verifyWeiBalance(accounts[1]).call();
    await web3.eth.sendTransaction({ from: accounts[1], to: market.options.address, value: 200 }); //msg.data is empty, test receive()
    let balanceAfterFirstTransfer = await market.methods.verifyWeiBalance(accounts[1]).call();
    await web3.eth.sendTransaction({ from: accounts[1], to: market.options.address, value: 300, data: '0xABCDEF01' }); //msg.data is not empty, test fallback()
    let balanceAfterSecondTransfer = await market.methods.verifyWeiBalance(accounts[1]).call();

    assert.equal(initialBalance, 0);
    assert.equal(balanceAfterFirstTransfer, 200);
    assert.equal(balanceAfterSecondTransfer, 500);
  });
  it('can accept ERC20 allowances', async() => {
    await testGold.methods.transfer(accounts[1], 500).send({ from: accounts[0] });
    let initialBalance = await market.methods.verifyTokenBalance(accounts[1], testGold.options.address).call();
    await testGold.methods.approve(market.options.address, 200).send({ from: accounts[1] });
    let finalBalance = await market.methods.verifyTokenBalance(accounts[1], testGold.options.address).call();

    assert.equal(initialBalance, 0);
    assert.equal(finalBalance, 200);
  });
});