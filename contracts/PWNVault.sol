pragma abicoder v2;
pragma solidity ^0.8.0;

import "./MultiToken.sol";
import "./PWN.sol";
import "./PWNDeed.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

contract PWNVault is Ownable, IERC1155Receiver{
    using MultiToken for MultiToken.Asset;

    address public PWN;

    modifier onlyPWN() {
        require(msg.sender == PWN);
        _;
    }

    event VaultPush(MultiToken.Asset asset);
    event VaultPull(MultiToken.Asset asset, address beneficiary);
    event VaultProxy(MultiToken.Asset asset, address origin, address beneficiary);

    constructor()
    Ownable()
    ERC1155Receiver()
    {
    }
    
    function push(MultiToken.Asset memory _asset) external onlyPWN returns (bool) {
        _asset.transferAssetFrom(tx.origin, address(this));
        emit VaultPush(_asset);
        return true;
    }

    function pull(MultiToken.Asset memory _asset, address _beneficiary) external onlyPWN returns (bool) {
        _asset.transferAsset(_beneficiary);
        emit VaultPull(_asset, _beneficiary);
        return true;
    }

    function pullProxy(MultiToken.Asset memory _asset, address _origin, address _beneficiary) external onlyPWN returns (bool){
        _asset.transferAssetFrom(_origin, _beneficiary);
        emit VaultProxy(_asset, _origin, _beneficiary);
        return true;
    }
    
     /**
        @dev Handles the receipt of a single ERC1155 token type. This function is
        called at the end of a `safeTransferFrom` after the balance has been updated.
        To accept the transfer, this must return
        `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))`
        (i.e. 0xf23a6e61, or its own function selector).
        @param operator The address which initiated the transfer (i.e. msg.sender)
        @param from The address which previously owned the token
        @param id The ID of the token being transferred
        @param value The amount of tokens being transferred
        @param data Additional data with no specified format
        @return `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))` if transfer is allowed
    */
    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    )
        override
        external
        returns(bytes4)
    {
        return "";
    }
    
    /**
        @dev Handles the receipt of a multiple ERC1155 token types. This function
        is called at the end of a `safeBatchTransferFrom` after the balances have
        been updated. To accept the transfer(s), this must return
        `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`
        (i.e. 0xbc197c81, or its own function selector).
        @param operator The address which initiated the batch transfer (i.e. msg.sender)
        @param from The address which previously owned the token
        @param ids An array containing ids of each token being transferred (order and length must match values array)
        @param values An array containing amounts of each token being transferred (order and length must match ids array)
        @param data Additional data with no specified format
        @return `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))` if transfer is allowed
    */
    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    )
        override
        external
        returns(bytes4)
    {
        return "";
    }

    function setPWN(address _address) external onlyOwner {
        PWN = _address;
    }
}
