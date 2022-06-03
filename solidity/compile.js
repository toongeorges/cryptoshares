const path = require('path');
const fs = require('fs');
const solc = require('solc');
 
const testTokenPath = path.resolve(__dirname, 'contracts', 'TestGold.sol');
const testTokenSource = fs.readFileSync(testTokenPath, 'utf8');
const exchangePath = path.resolve(__dirname, 'contracts', 'Exchange.sol');
const exchangeSource = fs.readFileSync(exchangePath, 'utf8');
const sharePath = path.resolve(__dirname, 'contracts', 'Share.sol');
const shareSource = fs.readFileSync(sharePath, 'utf8');
 
const input = { //compiler input description
  language: 'Solidity',
  sources: {
    'TestGold.sol': {
      content: testTokenSource,
    },
    'Exchange.sol': {
      content: exchangeSource,
    },
    'Share.sol': {
      content: shareSource,
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
  const absolutePath = path.resolve(__dirname, 'node_modules', relativePath);
  const source = fs.readFileSync(absolutePath, 'utf8');
  return { contents: source };
}

let compilation = solc.compile(JSON.stringify(input), { import: findImports });
let allContracts = JSON.parse(compilation).contracts;
let contracts = {};
contracts.TestGold = allContracts['TestGold.sol'].TestGold;
contracts.Exchange = allContracts['Exchange.sol'].Exchange;
contracts.Share = allContracts['Share.sol'].Share;

module.exports = contracts;