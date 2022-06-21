const { expect } = require("chai");
const { ethers } = require("hardhat");

const maxContractSize = 24*1024;

describe("Compiled Smart Contract Size Test", function () {
    it("Should deploy the SeedToken contract", async function () {
        const SeedToken = await ethers.getContractFactory("SeedToken");
        const seedToken = await SeedToken.deploy("Seed Token", "SEED");
        await seedToken.deployed();
        expect(seedToken.address).to.exist;
        const size = (seedToken.deployTransaction.data.length - 2)/2; //- 2 to remove the leading 0x, /2 because 2 hexadecimal ciphers = 1 byte
        console.log('    SeedToken contract size: ' + size + ' bytes');
        expect(size <= maxContractSize).to.be.true;
    });
    it("Should deploy the Scrutineer contract", async function () {
        const Scrutineer = await ethers.getContractFactory("Scrutineer");
        const scrutineer = await Scrutineer.deploy();
        await scrutineer.deployed();
        expect(scrutineer.address).to.exist;
        const size = (scrutineer.deployTransaction.data.length - 2)/2; //- 2 to remove the leading 0x, /2 because 2 hexadecimal ciphers = 1 byte
        console.log('    Scrutineer contract size: ' + size + ' bytes');
        expect(size <= maxContractSize).to.be.true;
    });
    it("Should deploy the Exchange contract", async function () {
        const Exchange = await ethers.getContractFactory("Exchange");
        const exchange = await Exchange.deploy();
        await exchange.deployed();
        expect(exchange.address).to.exist;
        const size = (exchange.deployTransaction.data.length - 2)/2; //- 2 to remove the leading 0x, /2 because 2 hexadecimal ciphers = 1 byte
        console.log('    Exchange contract size: ' + size + ' bytes');
        expect(size <= maxContractSize).to.be.true;
    });
    it("Should deploy the LegacyShare contract", async function () {
        const Scrutineer = await ethers.getContractFactory("Scrutineer");
        const scrutineer = await Scrutineer.deploy();
        await scrutineer.deployed();

        const LegacyShare = await ethers.getContractFactory("LegacyShare");
        const legacyShare = await LegacyShare.deploy('The Blockchain Company', 'TBC', scrutineer.address);
        await legacyShare.deployed();
        expect(legacyShare.address).to.exist;
        const size = (legacyShare.deployTransaction.data.length - 2)/2; //- 2 to remove the leading 0x, /2 because 2 hexadecimal ciphers = 1 byte
        console.log('    LegacyShare contract size: ' + size + ' bytes');
        expect(size <= maxContractSize).to.be.true;
    });
    it("Should deploy the Share contract", async function () {
        const Share = await ethers.getContractFactory("Share");
        const share = await Share.deploy('The Blockchain Company', 'TBC');
        await share.deployed();
        expect(share.address).to.exist;
        const size = (share.deployTransaction.data.length - 2)/2; //- 2 to remove the leading 0x, /2 because 2 hexadecimal ciphers = 1 byte
        console.log('    Share contract size: ' + size + ' bytes');
        expect(size <= maxContractSize).to.be.true;
    });
});