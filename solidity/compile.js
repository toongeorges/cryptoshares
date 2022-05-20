const path = require('path');
const fs = require('fs');
const solc = require('solc');
 
const testTokenPath = path.resolve(__dirname, 'contracts', 'TestGold.sol');
const testTokenSource = fs.readFileSync(testTokenPath, 'utf8');
const marketPath = path.resolve(__dirname, 'contracts', 'Market.sol');
const marketSource = fs.readFileSync(marketPath, 'utf8');
const companyPath = path.resolve(__dirname, 'contracts', 'Company.sol');
const companySource = fs.readFileSync(companyPath, 'utf8');
 
const input = { //compiler input description
  language: 'Solidity',
  sources: {
    'TestGold.sol': {
      content: testTokenSource,
    },
    'Market.sol': {
      content: marketSource,
    },
    'Company.sol': {
      content: companySource,
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
contracts.Market = allContracts['Market.sol'].Market;
contracts.Company = allContracts['Company.sol'].Company;

module.exports = contracts;