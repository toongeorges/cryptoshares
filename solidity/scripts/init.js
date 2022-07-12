const hre = require("hardhat");

async function main() {
  const metaMaskAddress = '0x3D8c354aB26A48DE315948141399ff20f39b70D5';

  const accounts = await hre.web3.eth.getAccounts();

  await hre.web3.eth.sendTransaction({
    from: accounts[0],
    to: metaMaskAddress,
    value: hre.web3.utils.toWei('100', 'ether')
  });
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
