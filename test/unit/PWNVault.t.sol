// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "MultiToken/MultiToken.sol";

import "openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import "openzeppelin-contracts/contracts/token/ERC1155/IERC1155Receiver.sol";

import "@pwn/loan/PWNVault.sol";
import "@pwn/PWNError.sol";


// The only reason for this contract is to expose internal functions of PWNVault
// No additional logic is applied here
contract PWNVaultExposed is PWNVault {

    function pull(MultiToken.Asset memory asset, address origin, bytes memory permit) external {
        _pull(asset, origin, permit);
    }

    function push(MultiToken.Asset memory asset, address beneficiary) external {
        _push(asset, beneficiary);
    }

    function pushFrom(MultiToken.Asset memory asset, address origin, address beneficiary, bytes memory permit) external {
        _pushFrom(asset, origin, beneficiary, permit);
    }
}

abstract contract PWNVaultTest is Test {

    PWNVaultExposed vault;
    address token = address(0x070ce2);
    address alice = address(0xa11ce);
    address bob = address(0xb0b);

    event VaultPull(MultiToken.Asset asset, address indexed origin);
    event VaultPush(MultiToken.Asset asset, address indexed beneficiary);
    event VaultPushFrom(MultiToken.Asset asset, address indexed origin, address indexed beneficiary);


    constructor() {
        vm.etch(token, bytes("data"));
    }

    function setUp() external {
        vault = new PWNVaultExposed();
    }

}


/*----------------------------------------------------------*|
|*  # PULL                                                  *|
|*----------------------------------------------------------*/

contract PWNVault_Pull_Test is PWNVaultTest {

    function test_shouldCallPermit_whenPermitNonZero() external {
        vm.mockCall(
            token,
            abi.encodeWithSignature("transferFrom(address,address,uint256)"),
            abi.encode(true)
        );
        vm.expectCall(
            token,
            abi.encodeWithSignature(
                "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
                alice, address(vault), 100, 1, uint8(4), bytes32(uint256(2)), bytes32(uint256(3)))
        );

        MultiToken.Asset memory asset = MultiToken.Asset(MultiToken.Category.ERC20, token, 0, 100);
        bytes memory permit = abi.encodePacked(
            uint256(1),
            bytes32(uint256(2)),
            bytes32(uint256(3)),
            uint8(4)
        );
        vault.pull(asset, alice, permit);
    }

    function test_shouldCallTransferFrom_fromOrigin_toVault() external {
        vm.expectCall(
            token,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", alice, address(vault), 42)
        );

        MultiToken.Asset memory asset = MultiToken.Asset(MultiToken.Category.ERC721, token, 42, 1);
        vault.pull(asset, alice, "");
    }

    function test_shouldEmitEvent_VaultPull() external {
        MultiToken.Asset memory asset = MultiToken.Asset(MultiToken.Category.ERC721, token, 42, 1);

        vm.expectEmit(true, true, false, false);
        emit VaultPull(asset, alice);

        vault.pull(asset, alice, "");
    }

}


/*----------------------------------------------------------*|
|*  # PUSH                                                  *|
|*----------------------------------------------------------*/

contract PWNVault_Push_Test is PWNVaultTest {

    function test_shouldCallSafeTransferFrom_fromVault_toBeneficiary() external {
        vm.expectCall(
            token,
            abi.encodeWithSignature("safeTransferFrom(address,address,uint256,bytes)", address(vault), alice, 42, "")
        );

        MultiToken.Asset memory asset = MultiToken.Asset(MultiToken.Category.ERC721, token, 42, 1);
        vault.push(asset, alice);
    }

    function test_shouldEmitEvent_VaultPush() external {
        MultiToken.Asset memory asset = MultiToken.Asset(MultiToken.Category.ERC721, token, 42, 1);

        vm.expectEmit(true, true, false, false);
        emit VaultPush(asset, alice);

        vault.push(asset, alice);
    }

}


/*----------------------------------------------------------*|
|*  # PUSH FROM                                             *|
|*----------------------------------------------------------*/

contract PWNVault_PushFrom_Test is PWNVaultTest {

    function test_shouldCallPermit_whenPermitNonZero() external {
        vm.mockCall(
            token,
            abi.encodeWithSignature("transferFrom(address,address,uint256)"),
            abi.encode(true)
        );
        vm.expectCall(
            token,
            abi.encodeWithSignature(
                "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
                alice, bob, 100, 1, uint8(4), bytes32(uint256(2)), bytes32(uint256(3)))
        );

        MultiToken.Asset memory asset = MultiToken.Asset(MultiToken.Category.ERC20, token, 0, 100);
        bytes memory permit = abi.encodePacked(
            uint256(1),
            bytes32(uint256(2)),
            bytes32(uint256(3)),
            uint8(4)
        );
        vault.pushFrom(asset, alice, bob, permit);
    }

    function test_shouldCallSafeTransferFrom_fromOrigin_toBeneficiary() external {
        vm.expectCall(
            token,
            abi.encodeWithSignature("safeTransferFrom(address,address,uint256,bytes)", alice, bob, 42, "")
        );

        MultiToken.Asset memory asset = MultiToken.Asset(MultiToken.Category.ERC721, token, 42, 1);
        vault.pushFrom(asset, alice, bob, "");
    }

    function test_shouldEmitEvent_VaultPushFrom() external {
        MultiToken.Asset memory asset = MultiToken.Asset(MultiToken.Category.ERC721, token, 42, 1);

        vm.expectEmit(true, true, true, false);
        emit VaultPushFrom(asset, alice, bob);

        vault.pushFrom(asset, alice, bob, "");
    }

}


/*----------------------------------------------------------*|
|*  # ERC721/1155 RECEIVED HOOKS                            *|
|*----------------------------------------------------------*/

contract PWNVault_ReceivedHooks_Test is PWNVaultTest {

    function test_shouldReturnCorrectValue_whenOperatorIsVault_onERC721Received() external {
        bytes4 returnValue = vault.onERC721Received(address(vault), address(0), 0, "");

        assertTrue(returnValue == IERC721Receiver.onERC721Received.selector);
    }

    function test_shouldFail_whenOperatorIsNotVault_onERC721Received() external {
        vm.expectRevert(abi.encodeWithSelector(PWNError.UnsupportedTransferFunction.selector));
        vault.onERC721Received(address(0), address(0), 0, "");
    }

    function test_shouldReturnCorrectValue_whenOperatorIsVault_onERC1155Received() external {
        bytes4 returnValue = vault.onERC1155Received(address(vault), address(0), 0, 0, "");

        assertTrue(returnValue == IERC1155Receiver.onERC1155Received.selector);
    }

    function test_shouldFail_whenOperatorIsNotVault_onERC1155Received() external {
        vm.expectRevert(abi.encodeWithSelector(PWNError.UnsupportedTransferFunction.selector));
        vault.onERC1155Received(address(0), address(0), 0, 0, "");
    }

    function test_shouldFail_whenOnERC1155BatchReceived() external {
        uint256[] memory ids;
        uint256[] memory values;

        vm.expectRevert(abi.encodeWithSelector(PWNError.UnsupportedTransferFunction.selector));
        vault.onERC1155BatchReceived(address(0), address(0), ids, values, "");
    }

}


/*----------------------------------------------------------*|
|*  # SUPPORTS INTERFACE                                    *|
|*----------------------------------------------------------*/

contract PWNVault_SupportsInterface_Test is PWNVaultTest {

    function test_shouldReturnTrue_whenIERC165() external {
        assertTrue(vault.supportsInterface(type(IERC165).interfaceId));
    }

    function test_shouldReturnTrue_whenIERC721Receiver() external {
        assertTrue(vault.supportsInterface(type(IERC721Receiver).interfaceId));
    }

    function test_shouldReturnTrue_whenIERC1155Receiver() external {
        assertTrue(vault.supportsInterface(type(IERC1155Receiver).interfaceId));
    }

}
