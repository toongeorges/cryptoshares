const path = require('path');
const fs = require('fs');
const solc = require('solc');
 
const testTokenPath = path.resolve(__dirname, 'contracts', 'TestGold.sol');
const testTokenSource = fs.readFileSync(testTokenPath, 'utf8');
const sharePath = path.resolve(__dirname, 'contracts', 'Share.sol');
const shareSource = fs.readFileSync(sharePath, 'utf8');
const exchangePath = path.resolve(__dirname, 'contracts', 'Exchange.sol');
const exchangeSource = fs.readFileSync(exchangePath, 'utf8');
 
const input = { //compiler input description
  language: 'Solidity',
  sources: {
    'TestGold.sol': {
      content: testTokenSource,
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
  const absolutePath = path.resolve(__dirname, 'node_modules', relativePath);
  const source = fs.readFileSync(absolutePath, 'utf8');
  return { contents: source };
}

let compilation = solc.compile(JSON.stringify(input), { import: findImports });
let parsed = JSON.parse(compilation);
let contracts = {};
if (parsed.errors) {
  console.log(parsed.errors)
} else {
  let allContracts = parsed.contracts;
  contracts.TestGold = allContracts['TestGold.sol'].TestGold;
  contracts.Share = allContracts['Share.sol'].Share;
  contracts.Exchange = allContracts['Exchange.sol'].Exchange;
}

module.exports = contracts;