const assert = require('assert');
const ganache = require('ganache-cli');
const Web3 = require('web3');
const web3 = new Web3(ganache.provider());
 
const contracts = require('../compile');
 
let accounts;
let seedToken;
let exchange;
 
beforeEach(async () => {
  // Get a list of all accounts
  accounts = await web3.eth.getAccounts();

  seedToken = await new web3.eth.Contract(contracts.SeedToken.abi)
    .deploy({
      data: contracts.SeedToken.evm.bytecode.object,
      arguments: [accounts[1]],
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
    assert.ok(seedToken.options.address);
    assert.ok(exchange.options.address);
  });
  it('can not accept native ether payments', async () => {
    await assert.rejects(web3.eth.sendTransaction({ from: accounts[1], to: exchange.options.address, value: 200 })); //msg.data is empty, test receive()
    await assert.rejects(web3.eth.sendTransaction({ from: accounts[1], to: exchange.options.address, value: 300, data: '0xABCDEF01' })); //msg.data is not empty, test fallback()
  });
});