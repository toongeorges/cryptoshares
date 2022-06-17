const assert = require('assert');
const path = require('path');
const fs = require('fs');
const solc = require('solc');
 
const seedTokenPath = path.resolve(__dirname, 'contracts', 'SeedToken.sol');
const seedTokenSource = fs.readFileSync(seedTokenPath, 'utf8');
const scrutineerPath = path.resolve(__dirname, 'contracts', 'Scrutineer.sol');
const scrutineerSource = fs.readFileSync(scrutineerPath, 'utf8');
const sharePath = path.resolve(__dirname, 'contracts', 'Share.sol');
const shareSource = fs.readFileSync(sharePath, 'utf8');
const exchangePath = path.resolve(__dirname, 'contracts', 'Exchange.sol');
const exchangeSource = fs.readFileSync(exchangePath, 'utf8');
 
const input = { //compiler input description
  language: 'Solidity',
  sources: {
    'SeedToken.sol': {
      content: seedTokenSource,
    },
    'Scrutineer.sol': {
      content: scrutineerSource,
    },
    'Share.sol': {
      content: shareSource,
    },
    'Exchange.sol': {
      content: exchangeSource,
    },
  },
  settings: {
    outputSelection: {
      '*': {
        '*': ['*'],
      },
    },
  },
};

function findImports(relativePath) { //how to deal with imports of external contracts, see https://github.com/ethereum/solc-js
  if (relativePath.startsWith('contracts/')) {
    const absolutePath = path.resolve(__dirname, relativePath);
    const source = fs.readFileSync(absolutePath, 'utf8');
    return { contents: source };
  } else {
    const absolutePath = path.resolve(__dirname, 'node_modules', relativePath);
    const source = fs.readFileSync(absolutePath, 'utf8');
    return { contents: source };
  }
}

let compilation = solc.compile(JSON.stringify(input), { import: findImports });
let parsed = JSON.parse(compilation);
let contracts = {};
if (parsed.errors) {
  console.log(parsed.errors)
}

const allContracts = parsed.contracts;
contracts.SeedToken = allContracts['SeedToken.sol'].SeedToken;
contracts.Scrutineer = allContracts['Scrutineer.sol'].Scrutineer;
contracts.Share = allContracts['Share.sol'].Share;
contracts.Exchange = allContracts['Exchange.sol'].Exchange;

//evm.bytecode.object is in hexadecimal notation, so the length in bytes is half the length of the string 
const seedTokenSize = contracts.SeedToken.evm.bytecode.object.length/2;
const scrutineerSize = contracts.Scrutineer.evm.bytecode.object.length/2;
const shareSize = contracts.Share.evm.bytecode.object.length/2;
const exchangeSize = contracts.Exchange.evm.bytecode.object.length/2;

console.log('SeedToken contract size: ' + seedTokenSize + ' bytes');
console.log('Scrutineer contract size: ' + scrutineerSize + ' bytes');
console.log('Share contract size: ' + shareSize + ' bytes');
console.log('Exchange contract size: ' + exchangeSize + ' bytes');

const maxContractSize = 24576; //The Ethereum blockchain does not allow contracts with a greater size

assert.ok(seedTokenSize <= maxContractSize);
assert.ok(scrutineerSize <= maxContractSize);
assert.ok(shareSize <= maxContractSize);
assert.ok(exchangeSize <= maxContractSize);

module.exports = contracts;