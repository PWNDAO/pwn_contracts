// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/interfaces/IERC1271.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC1155/IERC1155Receiver.sol";

contract ContractWallet is Ownable, IERC1271, IERC1155Receiver {

	bytes4 constant internal EIP1271_VALID_SIGNATURE = 0x1626ba7e;


	constructor() Ownable() {

	}


	function approve(address token, address spender, uint256 amount) public onlyOwner returns (bool) {
		return IERC20(token).approve(spender, amount);
    }

    function onERC1155Received(
        address /*operator*/,
        address /*from*/,
        uint256 /*id*/,
        uint256 /*value*/,
        bytes calldata /*data*/
    )
        override
        external
        pure
        returns(bytes4)
    {
        return 0xf23a6e61;
    }

    function onERC1155BatchReceived(
        address /*operator*/,
        address /*from*/,
        uint256[] calldata /*ids*/,
        uint256[] calldata /*values*/,
        bytes calldata /*data*/
    )
        override
        external
        pure
        returns(bytes4)
    {
        return 0xbc197c81;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC165).interfaceId
        	|| interfaceId == type(IERC1271).interfaceId
        	|| interfaceId == type(IERC1155Receiver).interfaceId
        	|| interfaceId == type(Ownable).interfaceId;
    }

	/**
	 * @notice Simple contract wallet where owner can sign messages on behalf of the contract
	 */
	function isValidSignature(
		bytes32 _hash,
		bytes memory _signature
	) override public view returns (bytes4 magicValue) {
		if (ECDSA.recover(_hash, _signature) == owner()) {
			return EIP1271_VALID_SIGNATURE;
		}

		return 0xffffffff;
	}
}
