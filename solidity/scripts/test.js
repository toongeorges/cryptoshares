const { ethers } = require("hardhat");
const seedTokenData = require("../artifacts/contracts/SeedToken.sol/SeedToken.json");
const shareData = require("../artifacts/contracts/Share.sol/Share.json");

async function main() {
  let firstTestAccount = ethers.provider.getSigner(); //has 10000 ETH
  let firstTestAccountAddress = await firstTestAccount.getAddress();

  const TBC = new ethers.Contract('0x27A0D478BABeb113179fFB3bFe329aBBaC64806c', shareData.abi, firstTestAccount);
  console.log(await TBC.getVoteChoice(2));

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
