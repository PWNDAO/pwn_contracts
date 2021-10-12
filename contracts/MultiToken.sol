// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.4;

// @dev importing contract interfaces - for supported contracts; nothing more than the interface is needed!
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

library MultiToken {

    /**
     * @title Category
     * @dev enum represention Asset category
     */
    enum Category {
        ERC20,
        ERC721,
        ERC1155
    }

    /**
     * @title Asset
     * @param assetAddress Address of the token contract defining the asset
     * @param category Corresponding asset category
     * @param amount Amount of fungible tokens or 0 -> 1
     * @param id TokenID of an NFT or 0
     */
    struct Asset {
        address assetAddress;
        Category category;
        uint256 amount;
        uint256 id;
    }

    /**
     * transferAsset
     * @dev wrapping function for transfer calls on various token interfaces
     * @param _asset Struck defining all necessary context of a token
     * @param _dest Destination address
     */
    function transferAsset(Asset memory _asset, address _dest) internal {
        if (_asset.category == Category.ERC20) {
            IERC20 token = IERC20(_asset.assetAddress);
            token.transfer(_dest, _asset.amount);

        } else if (_asset.category == Category.ERC721) {
            IERC721 token = IERC721(_asset.assetAddress);
            token.transferFrom(address(this), _dest, _asset.id);

        } else if (_asset.category == Category.ERC1155) {
            IERC1155 token = IERC1155(_asset.assetAddress);
            if (_asset.amount == 0) {
                _asset.amount = 1;
            }
            token.safeTransferFrom(address(this), _dest, _asset.id, _asset.amount, "");
        }
    }

    /**
     * transferAssetFrom
     * @dev wrapping function for transfer From calls on various token interfaces
     * @param _asset Struck defining all necessary context of a token
     * @param _source Account/address that provided the allowance
     * @param _dest Destination address
     */
    function transferAssetFrom(Asset memory _asset, address _source, address _dest) internal {
        if (_asset.category == Category.ERC20) {
            IERC20 token = IERC20(_asset.assetAddress);
            token.transferFrom(_source, _dest, _asset.amount);

        } else if (_asset.category == Category.ERC721) {
            IERC721 token = IERC721(_asset.assetAddress);
            token.transferFrom(_source, _dest, _asset.id);

        } else if (_asset.category == Category.ERC1155) {
            IERC1155 token = IERC1155(_asset.assetAddress);
            if (_asset.amount == 0) {
                _asset.amount = 1;
            }
            token.safeTransferFrom(_source, _dest, _asset.id, _asset.amount, "");
        }
    }

    /**
     * balanceOf
     * @dev wrapping function for checking balances on various token interfaces
     * @param _asset Struck defining all necessary context of a token
     * @param _target Target address to be checked
     */
    function balanceOf(Asset memory _asset, address _target) internal view returns (uint256) {
        if (_asset.category == Category.ERC20) {
            IERC20 token = IERC20(_asset.assetAddress);
            return token.balanceOf(_target);

        } else if (_asset.category == Category.ERC721) {
            IERC721 token = IERC721(_asset.assetAddress);
            if (token.ownerOf(_asset.id) == _target) {
                return 1;
            } else {
                return 0;
            }

        } else if (_asset.category == Category.ERC1155) {
            IERC1155 token = IERC1155(_asset.assetAddress);
            return token.balanceOf(_target, _asset.id);
        }
    }

    /**
     * approveAsset
     * @dev wrapping function for approve calls on various token interfaces
     * @param _asset Struck defining all necessary context of a token
     * @param _target Target address to be checked
     */
    function approveAsset(Asset memory _asset, address _target) internal {
        if (_asset.category == Category.ERC20) {
            IERC20 token = IERC20(_asset.assetAddress);
            token.approve(_target, _asset.amount);

        } else if (_asset.category == Category.ERC721) {
            IERC721 token = IERC721(_asset.assetAddress);
            token.approve(_target, _asset.id);

        } else if (_asset.category == Category.ERC1155) {
            IERC1155 token = IERC1155(_asset.assetAddress);
            token.setApprovalForAll(_target, true);
        }
    }
}
