pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/**
 * @dev this is just a dummy mintable/burnable ERC20 for testing purposes
 */
contract Basic721 is ERC721, Ownable {
    
    constructor(string memory name, string memory symbol) public 
        ERC721(name, symbol)
        Ownable()
    { }

    string baseURI;

    function mint(address account, uint256 id) public {
        _mint(account, id);
    }

    function burn(uint256 id) public onlyOwner {
        _burn(id);
    }

    /**
     * @dev Base URI for computing {tokenURI}. Empty by default, can be overriden
     * in child contracts.
     */
    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function setBaseURI(string memory _baseURI) public onlyOwner {
        baseURI = _baseURI;
    }
}