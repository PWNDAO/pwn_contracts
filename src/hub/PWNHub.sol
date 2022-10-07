// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "openzeppelin-contracts/contracts/access/Ownable.sol";


contract PWNHub is Ownable {

    /// Store that address has associated tag
    mapping (address => mapping (bytes32 => bool)) private tags;

    constructor() Ownable() {

    }


    function setTag(address _address, bytes32 tag, bool _hasTag) public onlyOwner {
        tags[_address][tag] = _hasTag;
    }

    function setTags(address _address, bytes32[] memory _tags, bool _hasTag) external onlyOwner {
        uint256 length = _tags.length;
        for (uint256 i; i < length;) {
            setTag(_address, _tags[i], _hasTag);
            unchecked { ++i; }
        }
    }


    function hasTag(address _address, bytes32 tag) external view returns (bool) {
        return tags[_address][tag];
    }

}
