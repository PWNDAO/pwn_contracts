// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @dev this is just a dummy mintable/burnable ERC20 for testing purposes
 */
contract Basic1155 is ERC1155, Ownable {
    
    constructor(string memory uri) public
        ERC1155(uri)
        Ownable()
    { }

    function mint(address account, uint256 id, uint256 amount, bytes memory data) public {
        _mint(account, id, amount, data);
    }

    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) public onlyOwner {
        _mintBatch(to, ids, amounts, data);
    }
}