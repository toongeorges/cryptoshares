const assert = require('assert');
const ganache = require('ganache-cli');
const Web3 = require('web3');
const web3 = new Web3(ganache.provider());
 
const contracts = require('../compile');
 
let accounts;
let testGold;
let exchange;
 
beforeEach(async () => {
  // Get a list of all accounts
  accounts = await web3.eth.getAccounts();

  testGold = await new web3.eth.Contract(contracts.TestGold.abi)
    .deploy({
      data: contracts.TestGold.evm.bytecode.object,
      arguments: [9000],
    })
    .send({ from: accounts[0], gas: '3000000' });

  exchange = await new web3.eth.Contract(contracts.Exchange.abi)
    .deploy({
      data: contracts.Exchange.evm.bytecode.object,
      arguments: [],
    })
    .send({ from: accounts[0], gas: '3000000' });
});
 
describe('Exchange creation', () => {
  it('deploys a contract', () => {
    assert.ok(testGold.options.address);
    assert.ok(exchange.options.address);
  });
  it('can not accept native ether payments', async () => {
    await assert.rejects(web3.eth.sendTransaction({ from: accounts[1], to: exchange.options.address, value: 200 })); //msg.data is empty, test receive()
    await assert.rejects(web3.eth.sendTransaction({ from: accounts[1], to: exchange.options.address, value: 300, data: '0xABCDEF01' })); //msg.data is not empty, test fallback()
  });
  it('can accept ERC20 allowances', async() => {
    await testGold.methods.transfer(accounts[1], 500).send({ from: accounts[0] });
    let initialBalance = await exchange.methods.verifyTokenBalance(accounts[1], testGold.options.address).call();
    await testGold.methods.approve(exchange.options.address, 200).send({ from: accounts[1] });
    let finalBalance = await exchange.methods.verifyTokenBalance(accounts[1], testGold.options.address).call();

    assert.equal(initialBalance, 0);
    assert.equal(finalBalance, 200);
  });
});