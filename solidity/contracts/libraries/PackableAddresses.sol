// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

/**
Deleting an array or resetting an array to an empty array is broken in Solidity,
since the gas cost for both is O(n) with n the number of elements in the original array and n can be unbounded.

Whenever an array is used, a mechanism must be provided to reduce the size of the array, to prevent iterating over the array becoming too costly.
This mechanism however cannot rely on deleting or resetting the array, since these operations fail themselves at this point.

Iteration over an array has to happen in a paged manner

Arrays can be reduced as follows:
- we need to store an extra field for the length of the array in length (the length property is only useful to determine whether we have to push or overwrite an existing value)
- we need to store an extra field for the length of the packed array in packedLength (during packing)
- we need to store an extra field for the array index from where the array has not been packed yet in unpackedIndex

if unpackedIndex == 0, all elements of the array are  in [1, length[

if unpackedIndex > 0, all elements of the array are in [1, packedLength[ and [unpackedIndex, length[
*/
struct PackInfo {
    uint256 unpackedIndex; //up to where the packing went, 0 if no packing in progress
    uint256 packedLength;  //up to where the packing went, 0 if no packing in progress
    mapping(address => uint256) index;
    uint256 length; //after packing, the (invalid) contents at a location from this index onwards are ignored
    address[] addresses;
}

library PackableAddresses {

    function init(PackInfo storage packInfo) internal {
        if (packInfo.addresses.length == 0) {
            packInfo.addresses.push(msg.sender);  //to make later operations on addresses less costly
            packInfo.length = 1;
        }
    }

    function getCount(PackInfo storage packInfo) internal view returns (uint256) {
        uint256 count = packInfo.length;
        unchecked {
            return (count == 0) ? count : count - 1;
        }
    }

    function getPackSize(PackInfo storage packInfo) internal view returns (uint256) {
        unchecked {
            return (packInfo.unpackedIndex == 0) ? getCount(packInfo) : (packInfo.length - packInfo.unpackedIndex);
        }
    }

    function register(PackInfo storage packInfo, address addr) internal {
        uint256 index = packInfo.index[addr];
        if (index == 0) { //the address has not been registered yet
            index = packInfo.length;
            if (index == 0) {
                init(packInfo);
                index = 1;
            }
            packInfo.index[addr] = index;
            if (index < packInfo.length) {
                packInfo.addresses[index] = addr;
            } else {
                packInfo.addresses.push(addr);
            }
            unchecked { packInfo.length++; }
        }
    }

    function pack(PackInfo storage packInfo, uint256 amountToPack, address context, function(address, address) internal returns (bool) isStillValid) internal {
        require(amountToPack > 0);

        uint256 maxEnd = packInfo.length;
        if (maxEnd == 0) {
            init(packInfo);
        } else {
            uint256 start = packInfo.unpackedIndex;

            uint256 packedIndex;
            if (start == 0) { //start a new packing
                start = 1; //keep the first entry in the addresses array (to simplify later calculations)
                packedIndex = start;
            } else {
                packedIndex = packInfo.packedLength;
            }

            uint256 end = start + amountToPack;
            if (end > maxEnd) {
                end = maxEnd;
            }

            mapping(address => uint256) storage index = packInfo.index;
            address[] storage addresses = packInfo.addresses;
            for (uint256 i = start; i < end;) {
                address selected = addresses[i];
                if (isStillValid(context, selected)) { //only register if the address is still valid
                    index[selected] = packedIndex;
                    addresses[packedIndex] = selected;
                    unchecked { packedIndex++; }
                } else {
                    index[selected] = 0;
                }
                unchecked { i++; }
            }
            packInfo.packedLength = packedIndex;

            if (end == maxEnd) {
                packInfo.unpackedIndex = 0;
                packInfo.length = packedIndex;
            } else {
                packInfo.unpackedIndex = end;
            }
        }
   }
}