// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ERC721 } from "openzeppelin/token/ERC721/ERC721.sol";


contract T721 is ERC721("ERC721", "ERC721") {

	function mint(address owner, uint256 tokenId) external {
		_mint(owner, tokenId);
	}

	function burn(uint256 tokenId) external {
		_burn(tokenId);
	}

}
