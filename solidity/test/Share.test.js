const assert = require('assert');
const ganache = require('ganache-cli');
const Web3 = require('web3');
const web3 = new Web3(ganache.provider());
 
const contracts = require('../compile');
 
let accounts;
let testGold;
let share;
 
beforeEach(async () => {
  // Get a list of all accounts
  accounts = await web3.eth.getAccounts();

  testGold = await new web3.eth.Contract(contracts.TestGold.abi)
    .deploy({
      data: contracts.TestGold.evm.bytecode.object,
      arguments: [9000],
    })
    .send({ from: accounts[0], gas: '3000000' });

  share = await new web3.eth.Contract(contracts.Share.abi)
    .deploy({
      data: contracts.Share.evm.bytecode.object,
      arguments: ['The Blockchain Company', 'TBC', 10000],
    })
    .send({ from: accounts[0], gas: '5000000' });
 
describe('Share creation', () => {
  it('deploys a contract', () => {
    assert.ok(testGold.options.address);
    assert.ok(share.options.address);
  });
  it('can not accept native ether payments', async () => {
    await assert.rejects(web3.eth.sendTransaction({ from: accounts[1], to: share.options.address, value: 200 })); //msg.data is empty, test receive()
    await assert.rejects(web3.eth.sendTransaction({ from: accounts[1], to: share.options.address, value: 300, data: '0xABCDEF01' })); //msg.data is not empty, test fallback()
  });
  it('has expected initial values', async () => {
    const name = await share.methods.name().call();
    const symbol = await share.methods.symbol().call();
    const decimals = await share.methods.decimals().call();
    const numberOfShares = await share.methods.totalSupply().call();
    const owner = await share.methods.owner().call();
    const numberOfShareHolders = await share.methods.shareHolderCount().call();
    const decisionParameters = await share.methods.decisionParameters().call();

    assert.equal(name, 'The Blockchain Company');
    assert.equal(symbol, 'TBC');
    assert.equal(decimals, 0);
    assert.equal(numberOfShares, 10000);
    assert.equal(owner, accounts[0]);
    assert.equal(decisionParameters.decisionTime, 60*60*24*30);
    assert.equal(decisionParameters.executionTime, 60*60*24*7);
    assert.equal(decisionParameters.quorumNumerator, 0);
    assert.equal(decisionParameters.quorumDenominator, 1);
    assert.equal(decisionParameters.majorityNumerator, 1);
    assert.equal(decisionParameters.majorityDenominator, 2);
    assert.equal(numberOfShareHolders, 0);
  });

  /*
  it('sets the right owner', async () => {
    const originalOwner = await share.methods.owner().call();
    await assert.rejects( //test if accounts[1] cannot change the owner
      share.methods.changeOwner(accounts[1]).send({ from: accounts[1] })
    );
    await share.methods.changeOwner(accounts[1]).send({ from: accounts[0] });
    const newOwner = await share.methods.owner().call();
    await assert.rejects( //test if accounts[0] cannot change the owner
      share.methods.changeOwner(accounts[0]).send({ from: accounts[0] })
    );

    assert.equal(originalOwner, accounts[0]);
    assert.equal(newOwner, accounts[1]);
  });
  it('can issue shares', async () => {
    await share.methods.issueShares(2000).send({ from: accounts[0] });
    const numberOfShares = await share.methods.totalSupply().call();
    await assert.rejects( //test if accounts[1] cannot change the number of shares
      share.methods.issueShares(3000).send({ from: accounts[1] })
    );

    assert.equal(numberOfShares, 12000);
  });
  it('can burn shares', async () => {
    await share.methods.burnShares(2000).send({ from: accounts[0] });
    const numberOfShares = await share.methods.totalSupply().call();
    await assert.rejects( //test if accounts[1] cannot change the number of shares
      share.methods.burnShares(3000).send({ from: accounts[1] })
    );

    assert.equal(numberOfShares, 8000);
  });
  it('can receive ether', async () => {
    let initialBalance = await share.methods.getWeiBalance().call();
    await web3.eth.sendTransaction({ from: accounts[0], to: share.options.address, value: 1000000 });
    let receivedBalance = await share.methods.getWeiBalance().call();

    assert.equal(initialBalance, 0);
    assert.equal(receivedBalance, 1000000);
  });
  it('can receive ERC20 tokens', async () => {
    let testGoldERC20 = testGold.options.address;
    let companyERC20 = share.options.address;
    let testGoldOwner = accounts[0];
    let companyOwner = accounts[1];

    await share.methods.changeOwner(companyOwner).send({ from: accounts[0] });

    let initialGoldSupply = await testGold.methods.balanceOf(testGoldOwner).call();
    let initialSharesSupply = await share.methods.balanceOf(companyERC20).call();

    let initialOwnedGold = await share.methods.getTokenBalance(testGoldERC20).call();
    let initialOwnedShares = await share.methods.getTokenBalance(companyERC20).call();

    await testGold.methods.transfer(companyERC20, 200).send({ from: testGoldOwner });

    let finalOwnedGold = await share.methods.getTokenBalance(testGoldERC20).call();

    assert.equal(initialGoldSupply, 9000 * 10**18);
    assert.equal(initialSharesSupply, 10000);
    assert.equal(initialOwnedGold, 0);
    assert.equal(initialOwnedShares, 10000);
    assert.equal(finalOwnedGold, 200);
  });
  */
});