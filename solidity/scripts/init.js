const { ethers } = require("hardhat");

async function main() {
  let firstTestAccount = ethers.provider.getSigner(); //has 10000 ETH
  let addressWithEther = await firstTestAccount.getAddress();

  const Exchange = await ethers.getContractFactory("Exchange");
  const exchange = await Exchange.deploy();
  await exchange.deployed();
  console.log("Exchange deployed to:", exchange.address);

  const metaMaskAddresses = [
    '0x3D8c354aB26A48DE315948141399ff20f39b70D5',
    '0x3D81DEe885a77a275d81eF51C23EF50712E39D65',
    '0x26432603F1Dd752c988b718585e5fcF1C60D79ae',
    '0xACdAcC8CaBAF9Fc84C17E3748b9878D5A55D3A9a',
    '0x8456EF8b829F3E8dE47d20cbc4063E48D888F75F'
  ];

  for (let i = 0; i < metaMaskAddresses.length; i++) {
    await firstTestAccount.sendTransaction({
      from: addressWithEther,
      to: metaMaskAddresses[i],
      value: ethers.utils.parseEther("100")
    });
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
