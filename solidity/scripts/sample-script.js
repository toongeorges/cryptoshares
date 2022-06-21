// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // We get the contract to deploy
  const Scrutineer = await hre.ethers.getContractFactory("Scrutineer");
  const scrutineer = await Scrutineer.deploy();
  await scrutineer.deployed();
  console.log("Scrutineer deployed to:", scrutineer.address);

  const Exchange = await hre.ethers.getContractFactory("Exchange");
  const exchange = await Exchange.deploy();
  await exchange.deployed();
  console.log("Exchange deployed to:", exchange.address);

  const LegacyShare = await hre.ethers.getContractFactory("LegacyShare");
  const legacyShare = await LegacyShare.deploy("Cryptoshare", "CTS", scrutineer.address);
  await legacyShare.deployed();
  console.log("LegacyShare deployed to:", legacyShare.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
