const path = require('path');
const fs = require('fs');
const solc = require('solc');
 
const companyPath = path.resolve(__dirname, 'contracts', 'Company.sol');
const companySource = fs.readFileSync(companyPath, 'utf8');
 
const input = { //compiler input description
  language: 'Solidity',
  sources: {
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
module.exports = JSON.parse(compilation).contracts[
  'Company.sol'
].Company;