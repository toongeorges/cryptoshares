const assert = require('assert');
const ganache = require('ganache-cli');
const Web3 = require('web3');
const web3 = new Web3(ganache.provider());
 
const contracts = require('../compile');
 
let accounts;
let testGold;
let company;
 
beforeEach(async () => {
  // Get a list of all accounts
  accounts = await web3.eth.getAccounts();

  testGold = await new web3.eth.Contract(contracts.TestGold.abi)
    .deploy({
      data: contracts.TestGold.evm.bytecode.object,
      arguments: [9000],
    })
    .send({ from: accounts[0], gas: '3000000' });

  company = await new web3.eth.Contract(contracts.Company.abi)
    .deploy({
      data: contracts.Company.evm.bytecode.object,
      arguments: ['The Blockchain Company', 'TBC', 10000],
    })
    .send({ from: accounts[0], gas: '3000000' });
});
 
describe('Company creation', () => {
  it('deploys a contract', () => {
    assert.ok(testGold.options.address);
    assert.ok(company.options.address);
  });
  it('has expected initial values', async () => {
    const name = await company.methods.name().call();
    const symbol = await company.methods.symbol().call();
    const decimals = await company.methods.decimals().call();
    const numberOfShares = await company.methods.totalSupply().call();
    const weiBalance = await company.methods.getWeiBalance().call();

    assert.equal(name, 'The Blockchain Company');
    assert.equal(symbol, 'TBC');
    assert.equal(decimals, 0);
    assert.equal(numberOfShares, 10000);
    assert.equal(weiBalance, 0);
  });
  it('sets the right owner', async () => {
    const originalOwner = await company.methods.owner().call();
    assert.rejects(async () => { //test if accounts[1] cannot change the owner
      await company.methods.changeOwner(accounts[1]).send({ from: accounts[1] });
    });
    await company.methods.changeOwner(accounts[1]).send({ from: accounts[0] });
    const newOwner = await company.methods.owner().call();
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
  it('can receive ether', async () => {
    let initialBalance = await company.methods.getWeiBalance().call();
    await web3.eth.sendTransaction({ from: accounts[0], to: company.options.address, value: 1000000 });
    let receivedBalance = await company.methods.getWeiBalance().call();

    assert.equal(initialBalance, 0);
    assert.equal(receivedBalance, 1000000);
  });
  it('can receive ERC20 tokens', async () => {
    let testGoldERC20 = testGold.options.address;
    let companyERC20 = company.options.address;
    let testGoldOwner = accounts[0];
    let companyOwner = accounts[1];

    await company.methods.changeOwner(companyOwner).send({ from: accounts[0] });

    let initialGoldSupply = await testGold.methods.balanceOf(testGoldOwner).call();
    let initialSharesSupply = await company.methods.balanceOf(companyERC20).call();

    let initialOwnedGold = await company.methods.getTokenBalance(testGoldERC20).call();
    let initialOwnedShares = await company.methods.getTokenBalance(companyERC20).call();

    await testGold.methods.transfer(companyERC20, 200).send({ from: testGoldOwner });

    let finalOwnedGold = await company.methods.getTokenBalance(testGoldERC20).call();

    assert.equal(initialGoldSupply, 9000 * 10**18);
    assert.equal(initialSharesSupply, 10000);
    assert.equal(initialOwnedGold, 0);
    assert.equal(initialOwnedShares, 10000);
    assert.equal(finalOwnedGold, 200);
  });
});