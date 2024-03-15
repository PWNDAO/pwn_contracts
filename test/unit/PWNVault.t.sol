// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import { PWNVault, IERC165, IERC721Receiver, IERC1155Receiver, Permit, MultiToken } from "@pwn/loan/vault/PWNVault.sol";
import "@pwn/PWNErrors.sol";

import { T721 } from "@pwn-test/helper/token/T721.sol";


contract PWNVaultHarness is PWNVault {

    function pull(MultiToken.Asset memory asset, address origin) external {
        _pull(asset, origin);
    }

    function push(MultiToken.Asset memory asset, address beneficiary) external {
        _push(asset, beneficiary);
    }

    function pushFrom(MultiToken.Asset memory asset, address origin, address beneficiary) external {
        _pushFrom(asset, origin, beneficiary);
    }

    function exposed_tryPermit(Permit calldata permit) external {
        _tryPermit(permit);
    }

}

abstract contract PWNVaultTest is Test {

    PWNVaultHarness vault;
    address token = makeAddr("token");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    T721 t721;

    event VaultPull(MultiToken.Asset asset, address indexed origin);
    event VaultPush(MultiToken.Asset asset, address indexed beneficiary);
    event VaultPushFrom(MultiToken.Asset asset, address indexed origin, address indexed beneficiary);


    constructor() {
        vm.etch(token, bytes("data"));
    }

    function setUp() public virtual {
        vault = new PWNVaultHarness();
        t721 = new T721();
    }

}


/*----------------------------------------------------------*|
|*  # PULL                                                  *|
|*----------------------------------------------------------*/

contract PWNVault_Pull_Test is PWNVaultTest {

    function test_shouldCallTransferFrom_fromOrigin_toVault() external {
        t721.mint(alice, 42);
        vm.prank(alice);
        t721.approve(address(vault), 42);

        vm.expectCall(
            address(t721),
            abi.encodeWithSignature("transferFrom(address,address,uint256)", alice, address(vault), 42)
        );

        MultiToken.Asset memory asset = MultiToken.Asset(MultiToken.Category.ERC721, address(t721), 42, 0);
        vault.pull(asset, alice);
    }

    function test_shouldFail_whenIncompleteTransaction() external {
        vm.mockCall(
            token,
            abi.encodeWithSignature("ownerOf(uint256)"),
            abi.encode(alice)
        );

        vm.expectRevert(abi.encodeWithSelector(IncompleteTransfer.selector));
        MultiToken.Asset memory asset = MultiToken.Asset(MultiToken.Category.ERC721, token, 42, 0);
        vault.pull(asset, alice);
    }

    function test_shouldEmitEvent_VaultPull() external {
        t721.mint(alice, 42);
        vm.prank(alice);
        t721.approve(address(vault), 42);

        MultiToken.Asset memory asset = MultiToken.Asset(MultiToken.Category.ERC721, address(t721), 42, 0);

        vm.expectEmit(true, true, true, true);
        emit VaultPull(asset, alice);

        vault.pull(asset, alice);
    }

}


/*----------------------------------------------------------*|
|*  # PUSH                                                  *|
|*----------------------------------------------------------*/

contract PWNVault_Push_Test is PWNVaultTest {

    function test_shouldCallSafeTransferFrom_fromVault_toBeneficiary() external {
        t721.mint(address(vault), 42);

        vm.expectCall(
            address(t721),
            abi.encodeWithSignature("safeTransferFrom(address,address,uint256,bytes)", address(vault), alice, 42, "")
        );

        MultiToken.Asset memory asset = MultiToken.Asset(MultiToken.Category.ERC721, address(t721), 42, 1);
        vault.push(asset, alice);
    }

    function test_shouldFail_whenIncompleteTransaction() external {
        vm.mockCall(
            token,
            abi.encodeWithSignature("ownerOf(uint256)"),
            abi.encode(address(vault))
        );

        vm.expectRevert(abi.encodeWithSelector(IncompleteTransfer.selector));
        MultiToken.Asset memory asset = MultiToken.Asset(MultiToken.Category.ERC721, token, 42, 0);
        vault.push(asset, alice);
    }

    function test_shouldEmitEvent_VaultPush() external {
        t721.mint(address(vault), 42);

        MultiToken.Asset memory asset = MultiToken.Asset(MultiToken.Category.ERC721, address(t721), 42, 1);

        vm.expectEmit(true, true, true, true);
        emit VaultPush(asset, alice);

        vault.push(asset, alice);
    }

}


/*----------------------------------------------------------*|
|*  # PUSH FROM                                             *|
|*----------------------------------------------------------*/

contract PWNVault_PushFrom_Test is PWNVaultTest {

    function test_shouldCallSafeTransferFrom_fromOrigin_toBeneficiary() external {
        t721.mint(alice, 42);
        vm.prank(alice);
        t721.approve(address(vault), 42);

        vm.expectCall(
            address(t721),
            abi.encodeWithSignature("safeTransferFrom(address,address,uint256,bytes)", alice, bob, 42, "")
        );

        MultiToken.Asset memory asset = MultiToken.Asset(MultiToken.Category.ERC721, address(t721), 42, 1);
        vault.pushFrom(asset, alice, bob);
    }

    function test_shouldFail_whenIncompleteTransaction() external {
        vm.mockCall(
            token,
            abi.encodeWithSignature("ownerOf(uint256)"),
            abi.encode(alice)
        );

        vm.expectRevert(abi.encodeWithSelector(IncompleteTransfer.selector));
        MultiToken.Asset memory asset = MultiToken.Asset(MultiToken.Category.ERC721, token, 42, 0);
        vault.pushFrom(asset, alice, bob);
    }

    function test_shouldEmitEvent_VaultPushFrom() external {
        t721.mint(alice, 42);
        vm.prank(alice);
        t721.approve(address(vault), 42);

        MultiToken.Asset memory asset = MultiToken.Asset(MultiToken.Category.ERC721, address(t721), 42, 1);

        vm.expectEmit(true, true, true, false);
        emit VaultPushFrom(asset, alice, bob);

        vault.pushFrom(asset, alice, bob);
    }

}


/*----------------------------------------------------------*|
|*  # TRY PERMIT                                            *|
|*----------------------------------------------------------*/

contract PWNVault_TryPermit_Test is PWNVaultTest {

    Permit permit;
    string permitSignature = "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)";

    function setUp() public override {
        super.setUp();

        vm.mockCall(
            token,
            abi.encodeWithSignature("permit(address,address,uint256,uint256,uint8,bytes32,bytes32)"),
            abi.encode("")
        );

        permit = Permit({
            asset: token,
            owner: alice,
            amount: 100,
            deadline: 1,
            v: 4,
            r: bytes32(uint256(2)),
            s: bytes32(uint256(3))
        });
    }


    function test_shouldCallPermit_whenPermitAssetNonZero() external {
        vm.expectCall(
            token,
            abi.encodeWithSignature(
                permitSignature,
                permit.owner, address(vault), permit.amount, permit.deadline, permit.v, permit.r, permit.s
            )
        );

        vault.exposed_tryPermit(permit);
    }

    function test_shouldNotCallPermit_whenPermitIsZero() external {
        vm.expectCall({
            callee: token,
            data: abi.encodeWithSignature(permitSignature),
            count: 0
        });

        permit.asset = address(0);
        vault.exposed_tryPermit(permit);
    }

    function test_shouldNotFail_whenPermitReverts() external {
        vm.mockCallRevert(token, abi.encodeWithSignature(permitSignature), abi.encode(""));

        vault.exposed_tryPermit(permit);
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
        vm.expectRevert(abi.encodeWithSelector(UnsupportedTransferFunction.selector));
        vault.onERC721Received(address(0), address(0), 0, "");
    }

    function test_shouldReturnCorrectValue_whenOperatorIsVault_onERC1155Received() external {
        bytes4 returnValue = vault.onERC1155Received(address(vault), address(0), 0, 0, "");

        assertTrue(returnValue == IERC1155Receiver.onERC1155Received.selector);
    }

    function test_shouldFail_whenOperatorIsNotVault_onERC1155Received() external {
        vm.expectRevert(abi.encodeWithSelector(UnsupportedTransferFunction.selector));
        vault.onERC1155Received(address(0), address(0), 0, 0, "");
    }

    function test_shouldFail_whenOnERC1155BatchReceived() external {
        uint256[] memory ids;
        uint256[] memory values;

        vm.expectRevert(abi.encodeWithSelector(UnsupportedTransferFunction.selector));
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
