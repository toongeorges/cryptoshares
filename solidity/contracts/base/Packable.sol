// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import 'contracts/libraries/PackableAddresses.sol';
import 'contracts/base/Proposals.sol';

abstract contract Packable is Proposals {
    PackInfo internal shareholders;
    PackInfo internal tradedTokens;



    function getShareholderCount() public view virtual override returns (uint256) {
        return PackableAddresses.getCount(shareholders);
    }

    function getShareholderNumber(address shareholder) external view virtual override returns (uint256) {
        return shareholders.index[shareholder];
    }

    function getShareholderPackSize() external view virtual override returns (uint256) {
        return PackableAddresses.getPackSize(shareholders);
    }

    function packShareholders(uint256 amountToPack) external virtual override {
        PackableAddresses.pack(shareholders, amountToPack, isShareholder);
    }

    function isShareholder(address shareholder) internal view returns (bool) {
        return balanceOf(shareholder) > 0;
    }

    function registerShareholder(address shareholder) internal {
        PackableAddresses.register(shareholders, shareholder);
    }



    function getTradedTokenCount() public view virtual override returns (uint256) {
        return PackableAddresses.getCount(tradedTokens);
    }

    function getTradedTokenNumber(address tokenAddress) external virtual override returns (uint256) {
        return tradedTokens.index[tokenAddress];
    }

    function getTradedTokenPackSize() external view virtual override returns (uint256) {
        return PackableAddresses.getPackSize(tradedTokens);
    }

    function packTradedTokens(uint256 amountToPack) external virtual override {
        PackableAddresses.pack(tradedTokens, amountToPack, isTradedToken);
    }

    function isTradedToken(address tokenAddress) internal view returns (bool) {
        return getLockedUpAmount(tokenAddress) > 0;
    }

    function registerTradedToken(address tokenAddress) internal {
        PackableAddresses.register(tradedTokens, tokenAddress);
    }
}