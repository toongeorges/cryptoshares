const { ethers } = require("hardhat");
const seedTokenData = require("../artifacts/contracts/SeedToken.sol/SeedToken.json");
const shareData = require("../artifacts/contracts/Share.sol/Share.json");

async function main() {
  let firstTestAccount = ethers.provider.getSigner(); //has 10000 ETH
  let firstTestAccountAddress = await firstTestAccount.getAddress();

  const SeedTokenFactory = await ethers.getContractFactory("SeedTokenFactory");
  const seedTokenFactory = await SeedTokenFactory.deploy();
  await seedTokenFactory.deployed();
  console.log("SeedTokenFactory deployed to:", seedTokenFactory.address);

  const Exchange = await ethers.getContractFactory("Exchange");
  const exchange = await Exchange.deploy();
  await exchange.deployed();
  console.log("Exchange deployed to:", exchange.address);

  const ShareFactory = await ethers.getContractFactory("ShareFactory");
  const shareFactory = await ShareFactory.deploy();
  await shareFactory.deployed();
  console.log("ShareFactory deployed to:", shareFactory.address);

  await seedTokenFactory.create("Euro", "EUR");
  await seedTokenFactory.create("US Dollar", "USD");
  await seedTokenFactory.create("British Pound", "GBP");
  await seedTokenFactory.create("Japanese Yen", "JPY");
  await seedTokenFactory.create("Argentine Peso", "ARS");

  let events = await seedTokenFactory.queryFilter("SeedTokenCreation");

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

  await shareFactory.create("AB InBev", "ABI", ethers.BigNumber.from('1737188612'), [120, 300, 0, 1, 1, 2], exchange.address);
  await shareFactory.create("Ackermans & van Haaren", "ACKB", ethers.BigNumber.from('33496904'), [120, 300, 0, 1, 1, 2], exchange.address);
  await shareFactory.create("Aedifica", "AED", ethers.BigNumber.from('39855243'), [120, 300, 0, 1, 1, 2], exchange.address);
  await shareFactory.create("Ageas", "AGS", ethers.BigNumber.from('189731187'), [120, 300, 0, 1, 1, 2], exchange.address);
  await shareFactory.create("Aperam", "APAM", ethers.BigNumber.from('79996280'), [120, 300, 0, 1, 1, 2], exchange.address);
  await shareFactory.create("arGEN-X", "ARGX", ethers.BigNumber.from('55061502'), [120, 300, 0, 1, 1, 2], exchange.address);
  await shareFactory.create("Cofinimmo", "COFB", ethers.BigNumber.from('32251549'), [120, 300, 0, 1, 1, 2], exchange.address);
  await shareFactory.create("Colruyt", "COLR", ethers.BigNumber.from('133839188'), [120, 300, 0, 1, 1, 2], exchange.address);
  await shareFactory.create("Elia", "ELI", ethers.BigNumber.from('73467919'), [120, 300, 0, 1, 1, 2], exchange.address);
  await shareFactory.create("Galapagos", "GLPG", ethers.BigNumber.from('65728511'), [120, 300, 0, 1, 1, 2], exchange.address);
  await shareFactory.create("GBL", "GBLB", ethers.BigNumber.from('153000000'), [120, 300, 0, 1, 1, 2], exchange.address);
  await shareFactory.create("KBC", "KBC", ethers.BigNumber.from('416883592'), [120, 300, 0, 1, 1, 2], exchange.address);
  await shareFactory.create("Melexis", "MELE", ethers.BigNumber.from('40400000'), [120, 300, 0, 1, 1, 2], exchange.address);
  await shareFactory.create("Proximus Group", "PROX", ethers.BigNumber.from('338025135'), [120, 300, 0, 1, 1, 2], exchange.address);
  await shareFactory.create("Sofina", "SOF", ethers.BigNumber.from('34250000'), [120, 300, 0, 1, 1, 2], exchange.address);
  await shareFactory.create("Solvay", "SOLB", ethers.BigNumber.from('105876416'), [120, 300, 0, 1, 1, 2], exchange.address);
  await shareFactory.create("Telenet Group", "TNET", ethers.BigNumber.from('112646946'), [120, 300, 0, 1, 1, 2], exchange.address);
  await shareFactory.create("UCB", "UCB", ethers.BigNumber.from('194505658'), [120, 300, 0, 1, 1, 2], exchange.address);
  await shareFactory.create("Umicore", "UMI", ethers.BigNumber.from('246400000'), [120, 300, 0, 1, 1, 2], exchange.address);
  await shareFactory.create("WDP", "WDP", ethers.BigNumber.from('186557793'), [120, 300, 0, 1, 1, 2], exchange.address);

  events = await shareFactory.queryFilter("ShareCreation");

  const ABI = new ethers.Contract(events[0].args.shareAddress, shareData.abi, firstTestAccount);
  const ACKB = new ethers.Contract(events[1].args.shareAddress, shareData.abi, firstTestAccount);
  const AED = new ethers.Contract(events[2].args.shareAddress, shareData.abi, firstTestAccount);
  const AGS = new ethers.Contract(events[3].args.shareAddress, shareData.abi, firstTestAccount);
  const APAM = new ethers.Contract(events[4].args.shareAddress, shareData.abi, firstTestAccount);
  const ARGX = new ethers.Contract(events[5].args.shareAddress, shareData.abi, firstTestAccount);
  const COFB = new ethers.Contract(events[6].args.shareAddress, shareData.abi, firstTestAccount);
  const COLR = new ethers.Contract(events[7].args.shareAddress, shareData.abi, firstTestAccount);
  const ELI = new ethers.Contract(events[8].args.shareAddress, shareData.abi, firstTestAccount);
  const GLPG = new ethers.Contract(events[9].args.shareAddress, shareData.abi, firstTestAccount);
  const GBLB = new ethers.Contract(events[10].args.shareAddress, shareData.abi, firstTestAccount);
  const KBC = new ethers.Contract(events[11].args.shareAddress, shareData.abi, firstTestAccount);
  const MELE = new ethers.Contract(events[12].args.shareAddress, shareData.abi, firstTestAccount);
  const PROX = new ethers.Contract(events[13].args.shareAddress, shareData.abi, firstTestAccount);
  const SOF = new ethers.Contract(events[14].args.shareAddress, shareData.abi, firstTestAccount);
  const SOLB = new ethers.Contract(events[15].args.shareAddress, shareData.abi, firstTestAccount);
  const TNET = new ethers.Contract(events[16].args.shareAddress, shareData.abi, firstTestAccount);
  const UCB = new ethers.Contract(events[17].args.shareAddress, shareData.abi, firstTestAccount);
  const UMI = new ethers.Contract(events[18].args.shareAddress, shareData.abi, firstTestAccount);
  const WDP = new ethers.Contract(events[19].args.shareAddress, shareData.abi, firstTestAccount);

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
      from: firstTestAccountAddress,
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
