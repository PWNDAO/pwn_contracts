pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

/**
 * @dev this is just a dummy mintable/burnable ERC20 for testing purposes
 */
contract Basic721 is ERC721, IERC721Metadata, Ownable {
    
    constructor(string memory name, string memory symbol) public 
        ERC721(name, symbol)
        Ownable()
    { }

    function mint(address account, uint256 id) public {
        _mint(account, id);
    }

    function burn(uint256 id) public onlyOwner {
        _burn(id);
    }

    function setBaseURI(string memory baseURI_) public onlyOwner {
        _setBaseURI(baseURI_);
    }
}