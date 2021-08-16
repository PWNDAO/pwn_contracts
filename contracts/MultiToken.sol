pragma solidity ^0.8.0;

// @dev importing contract interfaces - for supported contracts; nothing more than the interface is needed!
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

library MultiToken {
    /**
     * @title Asset
     * @param cat Corresponding asset category:
     *      cat == 0 := ERC20
     *      cat == 1 := ERC721
     *      cat == 2 := ERC1155
     * @param amount Amount of fungible tokens or 0 -> 1
     * @param id TokenID of an NFT or 0
     * @param tokenAddress Address of the token contract defining the asset
     */
    struct Asset {
        uint8 cat;
        uint256 amount;
        uint256 id;
        address tokenAddress;
    }

    /**
     * @title transferAsset
     * @dev wrapping function for transfer calls on various token interfaces
     * @param _asset Struck defining all necessary context of a token
     * @param _dest Destination address
     */
    function transferAsset(Asset memory _asset, address _dest) internal {
        if (_asset.cat == 0) {
            IERC20 token = IERC20(_asset.tokenAddress);
            require(token.transfer(_dest, _asset.amount), 'ERC20 token transfer failed');

        } else if (_asset.cat == 1 ) {
            IERC721 token = IERC721(_asset.tokenAddress);
            token.transferFrom(address(this), _dest, _asset.id);

        } else if (_asset.cat == 2 ) {
            IERC1155 token = IERC1155(_asset.tokenAddress);
            if (_asset.amount == 0) {
                _asset.amount = 1;
            }
            token.safeTransferFrom(address(this), _dest, _asset.id, _asset.amount, "");

        } else {
            revert("Unsupported category");
        }
    }

    /**
     * @title transferAssetFrom
     * @dev wrapping function for transfer From calls on various token interfaces
     * @param _asset Struck defining all necessary context of a token
     * @param _source Account/address that provided the allowance
     * @param _dest Destination address
     */
    function transferAssetFrom(Asset memory _asset, address _source, address  _dest) internal {
        if (_asset.cat == 0) {
            IERC20 token = IERC20(_asset.tokenAddress);
            token.transferFrom(_source, _dest, _asset.amount);

        } else if (_asset.cat == 1 ) {
            IERC721 token = IERC721(_asset.tokenAddress);
            token.transferFrom(_source, _dest, _asset.id);

        } else if (_asset.cat == 2 ) {
            IERC1155 token = IERC1155(_asset.tokenAddress);
            if (_asset.amount == 0) {
                _asset.amount = 1;
            }
            token.safeTransferFrom(_source, _dest, _asset.id, _asset.amount, "");

        } else {
            revert("Unsupported category");
        }
    }

    /**
     * @title balanceOf
     * @dev wrapping function for checking balances on various token interfaces
     * @param _asset Struck defining all necessary context of a token
     * @param _target Target address to be checked
     */
    function balanceOf(Asset memory _asset, address _target) internal view returns (uint256) {
        if (_asset.cat == 0) {
            IERC20 token = IERC20(_asset.tokenAddress);
            return token.balanceOf(_target);

        } else if (_asset.cat == 1 ) {
            IERC721 token = IERC721(_asset.tokenAddress);
            if (token.ownerOf(_asset.id) == _target) {
                return 1;
            } else {
                return 0;
            }

        } else if (_asset.cat == 2 ) {
            IERC1155 token = IERC1155(_asset.tokenAddress);
            return token.balanceOf(_target,_asset.id);

        } else {
            revert("Unsupported category");
        }

        return 0;
    }

    /**
     * @title approveAsset
     * @dev wrapping function for approve calls on various token interfaces
     * @param _asset Struck defining all necessary context of a token
     * @param _target Target address to be checked
     */
    function approveAsset(Asset memory _asset, address  _target) internal {
        if (_asset.cat == 0) {
            IERC20 token = IERC20(_asset.tokenAddress);
            token.approve(_target, _asset.amount);

        } else if (_asset.cat == 1 ) {
            IERC721 token = IERC721(_asset.tokenAddress);
            token.approve(_target, _asset.id);

        } else if (_asset.cat == 2 ) {
            IERC1155 token = IERC1155(_asset.tokenAddress);
            token.setApprovalForAll(_target, true);

        } else {
            revert("Unsupported category");
        }
    }
}
