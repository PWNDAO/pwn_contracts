pragma solidity ^0.8.0;

import "../MultiToken.sol";

contract MultiTokenTestAdapter {
	using MultiToken for MultiToken.Asset;


	function transferAsset(address _tokenAddress, uint8 _cat, uint256 _amount, uint256 _id, address _dest) external {
		MultiToken.Asset(_tokenAddress, _cat, _amount, _id).transferAsset(_dest);
	}

	function transferAssetFrom(address _tokenAddress, uint8 _cat, uint256 _amount, uint256 _id, address _source, address  _dest) external {
		MultiToken.Asset(_tokenAddress, _cat, _amount, _id).transferAssetFrom(_source, _dest);
	}

	function balanceOf(address _tokenAddress, uint8 _cat, uint256 _amount, uint256 _id, address _target) external view returns (uint256) {
		return MultiToken.Asset(_tokenAddress, _cat, _amount, _id).balanceOf(_target);
	}

	function approveAsset(address _tokenAddress, uint8 _cat, uint256 _amount, uint256 _id, address _target) external {
		MultiToken.Asset(_tokenAddress, _cat, _amount, _id).approveAsset(_target);
	}

}
