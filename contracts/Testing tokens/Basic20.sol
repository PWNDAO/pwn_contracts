pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @dev this is just a dummy mintable/burnable ERC20 for testing purposes
 */
contract Basic20 is ERC20, Ownable {
    
    constructor(string memory name, string memory symbol) public 
        ERC20(name, symbol)
        Ownable()
    { }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public onlyOwner {
        _burn(account, amount);
    }
}