pragma solidity ^0.8.0;

import "../MultiToken.sol";
import "../PWNVault.sol";

contract PWNVaultTestAdapter {

	PWNVault public vault;

	constructor(address _vault) {
		vault = PWNVault(_vault);
	}


	function push(address _tokenAddress, MultiToken.Category _cat, uint256 _amount, uint256 _id, address _origin) external returns (bool) {
		return vault.push(MultiToken.Asset(_tokenAddress, _cat, _amount, _id), _origin);
	}

	function pull(address _tokenAddress, MultiToken.Category _cat, uint256 _amount, uint256 _id, address _beneficiary) external returns (bool) {
		return vault.pull(MultiToken.Asset(_tokenAddress, _cat, _amount, _id), _beneficiary);
	}

	function pullProxy(address _tokenAddress, MultiToken.Category _cat, uint256 _amount, uint256 _id, address _origin, address _beneficiary) external returns (bool) {
		return vault.pullProxy(MultiToken.Asset(_tokenAddress, _cat, _amount, _id), _origin, _beneficiary);
	}

}
