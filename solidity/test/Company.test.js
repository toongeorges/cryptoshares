const assert = require('assert');
const ganache = require('ganache-cli');
const Web3 = require('web3');
const web3 = new Web3(ganache.provider());
 
const { abi, evm } = require('../compile');
 
let accounts;
let company;
 
beforeEach(async () => {
  // Get a list of all accounts
  accounts = await web3.eth.getAccounts();
  company = await new web3.eth.Contract(abi)
    .deploy({
      data: evm.bytecode.object,
      arguments: ['The Blockchain Company', 'TBC', 10000],
    })
    .send({ from: accounts[0], gas: '3000000' });
});
 
describe('Company creation', () => {
  it('deploys a contract', () => {
    assert.ok(company.options.address);
  });
  it('has expected initial values', async () => {
    const name = await company.methods.name().call();
    const symbol = await company.methods.symbol().call();
    const decimals = await company.methods.decimals().call();
    const numberOfShares = await company.methods.totalSupply().call();
    const etherBalance = await company.methods.getEtherBalance().call();

    assert.equal(name, 'The Blockchain Company');
    assert.equal(symbol, 'TBC');
    assert.equal(decimals, 0);
    assert.equal(numberOfShares, 10000);
    assert.equal(etherBalance, 0);
  });
  it('sets the right owner', async () => {
    const originalOwner = await company.methods.getOwner().call();
    assert.rejects(async () => { //test if accounts[1] cannot change the owner
      await company.methods.changeOwner(accounts[1]).send({ from: accounts[1] });
    });
    await company.methods.changeOwner(accounts[1]).send({ from: accounts[0] });
    const newOwner = await company.methods.getOwner().call();
    assert.rejects(async () => { //test if accounts[0] cannot change the owner
      await company.methods.changeOwner(accounts[0]).send({ from: accounts[0] });
    });

    assert.equal(originalOwner, accounts[0]);
    assert.equal(newOwner, accounts[1]);
  });
  it('can issue shares', async () => {
    await company.methods.issueShares(2000).send({ from: accounts[0] });
    const numberOfShares = await company.methods.totalSupply().call();
    assert.rejects(async () => { //test if accounts[1] cannot change the number of shares
      await company.methods.issueShares(3000).send({ from: accounts[1] });
    });

    assert.equal(numberOfShares, 12000);
  });
  it('can burn shares', async () => {
    await company.methods.burnShares(2000).send({ from: accounts[0] });
    const numberOfShares = await company.methods.totalSupply().call();
    assert.rejects(async () => { //test if accounts[1] cannot change the number of shares
      await company.methods.burnShares(3000).send({ from: accounts[1] });
    });

    assert.equal(numberOfShares, 8000);
  });
});