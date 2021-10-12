// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.4;

import "../MultiToken.sol";

contract MultiTokenTestAdapter {
	using MultiToken for MultiToken.Asset;


	function transferAsset(address _assetAddress, MultiToken.Category _category, uint256 _amount, uint256 _id, address _destination) external {
		MultiToken.Asset(_assetAddress, _category, _amount, _id).transferAsset(_destination);
	}

	function transferAssetFrom(address _assetAddress, MultiToken.Category _category, uint256 _amount, uint256 _id, address _source, address _destination) external {
		MultiToken.Asset(_assetAddress, _category, _amount, _id).transferAssetFrom(_source, _destination);
	}

	function balanceOf(address _assetAddress, MultiToken.Category _category, uint256 _amount, uint256 _id, address _target) external view returns (uint256) {
		return MultiToken.Asset(_assetAddress, _category, _amount, _id).balanceOf(_target);
	}

	function approveAsset(address _assetAddress, MultiToken.Category _category, uint256 _amount, uint256 _id, address _target) external {
		MultiToken.Asset(_assetAddress, _category, _amount, _id).approveAsset(_target);
	}

}
