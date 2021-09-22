pragma solidity ^0.8.0;

import "../MultiToken.sol";
import "../PWNVault.sol";

contract PWNVaultTestAdapter {

	PWNVault public vault;

	constructor(address _vault) {
		vault = PWNVault(_vault);
	}


	function push(uint8 _cat, uint256 _amount, uint256 _id, address _tokenAddress, address _origin) external returns (bool) {
		return vault.push(MultiToken.Asset(_cat, _amount, _id, _tokenAddress), _origin);
	}

	function pull(uint8 _cat, uint256 _amount, uint256 _id, address _tokenAddress, address _beneficiary) external returns (bool) {
		return vault.pull(MultiToken.Asset(_cat, _amount, _id, _tokenAddress), _beneficiary);
	}

	function pullProxy(uint8 _cat, uint256 _amount, uint256 _id, address _tokenAddress, address _origin, address _beneficiary) external returns (bool) {
		return vault.pullProxy(MultiToken.Asset(_cat, _amount, _id, _tokenAddress), _origin, _beneficiary);
	}

}
