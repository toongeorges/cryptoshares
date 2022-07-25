const { ethers } = require("hardhat");
const seedTokenData = require("../artifacts/contracts/SeedToken.sol/SeedToken.json");

async function main() {
  let firstTestAccount = ethers.provider.getSigner(); //has 10000 ETH
  let addressWithEther = await firstTestAccount.getAddress();

  const SeedTokenFactory = await ethers.getContractFactory("SeedTokenFactory");
  const seedTokenFactory = await SeedTokenFactory.deploy();
  await seedTokenFactory.deployed();
  console.log("SeedTokenFactory deployed to:", seedTokenFactory.address);

  await seedTokenFactory.create("Euro", "EUR");
  await seedTokenFactory.create("US Dollar", "USD");
  await seedTokenFactory.create("British Pound", "GBP");
  await seedTokenFactory.create("Japanese Yen", "JPY");
  await seedTokenFactory.create("Argentine Peso", "ARS");

  const events = await seedTokenFactory.queryFilter("SeedTokenCreation");

  const euro = new ethers.Contract(events[0].args.tokenAddress, seedTokenData.abi, firstTestAccount);
  await euro.mint(ethers.BigNumber.from('1000000000'));
  const dollar = new ethers.Contract(events[1].args.tokenAddress, seedTokenData.abi, firstTestAccount);
  await dollar.mint(ethers.BigNumber.from('1000000000'));
  const pound = new ethers.Contract(events[2].args.tokenAddress, seedTokenData.abi, firstTestAccount);
  await pound.mint(ethers.BigNumber.from('900000000'));
  const yen = new ethers.Contract(events[3].args.tokenAddress, seedTokenData.abi, firstTestAccount);
  await yen.mint(ethers.BigNumber.from('100000000000'));
  const peso = new ethers.Contract(events[4].args.tokenAddress, seedTokenData.abi, firstTestAccount);
  await peso.mint(ethers.BigNumber.from('1000000000000000'));

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

  const erc20NumberOfDecimals = 18;
  for (let i = 0; i < metaMaskAddresses.length; i++) {
    await firstTestAccount.sendTransaction({
      from: addressWithEther,
      to: metaMaskAddresses[i],
      value: ethers.utils.parseEther("100")
    });
    await euro.transfer(metaMaskAddresses[i], ethers.BigNumber.from('10').pow(6 + erc20NumberOfDecimals));
    await dollar.transfer(metaMaskAddresses[i], ethers.BigNumber.from('10').pow(6 + erc20NumberOfDecimals));
    await pound.transfer(metaMaskAddresses[i], ethers.BigNumber.from('10').pow(6 + erc20NumberOfDecimals));
    await yen.transfer(metaMaskAddresses[i], ethers.BigNumber.from('10').pow(6 + erc20NumberOfDecimals));
    await peso.transfer(metaMaskAddresses[i], ethers.BigNumber.from('10').pow(6 + erc20NumberOfDecimals));
  }

  await euro.changeOwner(metaMaskAddresses[0]);
  await dollar.changeOwner(metaMaskAddresses[1]);
  await pound.changeOwner(metaMaskAddresses[2]);
  await yen.changeOwner(metaMaskAddresses[3]);
  await peso.changeOwner(metaMaskAddresses[4]);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
