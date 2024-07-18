// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";


contract T20 is ERC20("ERC20", "ERC20") {

	function mint(address owner, uint256 amount) external {
		_mint(owner, amount);
	}

	function burn(address owner, uint256 amount) external {
		_burn(owner, amount);
	}

}
