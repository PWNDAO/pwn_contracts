pragma solidity ^0.8.0;

import "../MultiToken.sol";

contract MultiTokenTestAdapter {
	using MultiToken for MultiToken.Asset;


	function transferAsset(uint8 _cat, uint256 _amount, uint256 _id, address _tokenAddress, address _dest) external {
		MultiToken.Asset(_cat, _amount, _id, _tokenAddress).transferAsset(_dest);
	}

	function transferAssetFrom(uint8 _cat, uint256 _amount, uint256 _id, address _tokenAddress, address _source, address  _dest) external {
		MultiToken.Asset(_cat, _amount, _id, _tokenAddress).transferAssetFrom(_source, _dest);
	}

	function balanceOf(uint8 _cat, uint256 _amount, uint256 _id, address _tokenAddress, address _target) external view returns (uint256) {
		return MultiToken.Asset(_cat, _amount, _id, _tokenAddress).balanceOf(_target);
	}

	function approveAsset(uint8 _cat, uint256 _amount, uint256 _id, address _tokenAddress, address _target) external {
		MultiToken.Asset(_cat, _amount, _id, _tokenAddress).approveAsset(_target);
	}

}
