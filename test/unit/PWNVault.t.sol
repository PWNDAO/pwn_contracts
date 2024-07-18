// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import {
    MultiToken,
    IERC165,
    IERC721Receiver,
    IERC1155Receiver,
    PWNVault,
    IPoolAdapter,
    Permit
} from "pwn/loan/vault/PWNVault.sol";

import { DummyPoolAdapter } from "test/helper/DummyPoolAdapter.sol";
import { T20 } from "test/helper/T20.sol";
import { T721 } from "test/helper/T721.sol";


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

    function withdrawFromPool(MultiToken.Asset memory asset, IPoolAdapter poolAdapter, address pool, address owner) external {
        _withdrawFromPool(asset, poolAdapter, pool, owner);
    }

    function supplyToPool(MultiToken.Asset memory asset, IPoolAdapter poolAdapter, address pool, address owner) external {
        _supplyToPool(asset, poolAdapter, pool, owner);
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

    T20 t20;
    T721 t721;

    event VaultPull(MultiToken.Asset asset, address indexed origin);
    event VaultPush(MultiToken.Asset asset, address indexed beneficiary);
    event VaultPushFrom(MultiToken.Asset asset, address indexed origin, address indexed beneficiary);
    event PoolWithdraw(MultiToken.Asset asset, address indexed poolAdapter, address indexed pool, address indexed owner);
    event PoolSupply(MultiToken.Asset asset, address indexed poolAdapter, address indexed pool, address indexed owner);

    constructor() {
        vm.etch(token, bytes("data"));
    }

    function setUp() public virtual {
        vault = new PWNVaultHarness();
        t20 = new T20();
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

        vm.expectRevert(abi.encodeWithSelector(PWNVault.IncompleteTransfer.selector));
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

        vm.expectRevert(abi.encodeWithSelector(PWNVault.IncompleteTransfer.selector));
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

        vm.expectRevert(abi.encodeWithSelector(PWNVault.IncompleteTransfer.selector));
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
|*  # WITHDRAW FROM POOL                                    *|
|*----------------------------------------------------------*/

contract PWNVault_WithdrawFromPool_Test is PWNVaultTest {
    using MultiToken for address;

    IPoolAdapter poolAdapter = IPoolAdapter(new DummyPoolAdapter());
    address pool = makeAddr("pool");
    MultiToken.Asset asset;

    function setUp() override public {
        super.setUp();

        asset = address(t20).ERC20(42e18);

        t20.mint(pool, asset.amount);
        vm.prank(pool);
        t20.approve(address(poolAdapter), asset.amount);
    }


    function test_shouldCallWithdrawOnPoolAdapter() external {
        vm.expectCall(
            address(poolAdapter),
            abi.encodeWithSelector(IPoolAdapter.withdraw.selector, pool, alice, asset.assetAddress, asset.amount)
        );

        vault.withdrawFromPool(asset, poolAdapter, pool, alice);
    }

    function test_shouldFail_whenIncompleteTransaction() external {
        vm.mockCall(
            asset.assetAddress,
            abi.encodeWithSignature("balanceOf(address)", alice),
            abi.encode(asset.amount)
        );

        vm.expectRevert(abi.encodeWithSelector(PWNVault.IncompleteTransfer.selector));
        vault.withdrawFromPool(asset, poolAdapter, pool, alice);
    }

    function test_shouldEmitEvent_PoolWithdraw() external {
        vm.expectEmit();
        emit PoolWithdraw(asset, address(poolAdapter), pool, alice);

        vault.withdrawFromPool(asset, poolAdapter, pool, alice);
    }

}


/*----------------------------------------------------------*|
|*  # SUPPLY TO POOL                                        *|
|*----------------------------------------------------------*/

contract PWNVault_SupplyToPool_Test is PWNVaultTest {
    using MultiToken for address;

    IPoolAdapter poolAdapter = IPoolAdapter(new DummyPoolAdapter());
    address pool = makeAddr("pool");
    MultiToken.Asset asset;

    function setUp() override public {
        super.setUp();

        asset = address(t20).ERC20(42e18);

        t20.mint(address(vault), asset.amount);
    }


    function test_shouldTransferAssetToPoolAdapter() external {
        vm.expectCall(
            asset.assetAddress,
            abi.encodeWithSignature("transfer(address,uint256)", address(poolAdapter), asset.amount)
        );

        vault.supplyToPool(asset, poolAdapter, pool, alice);
    }

    function test_shouldCallSupplyOnPoolAdapter() external {
        vm.expectCall(
            address(poolAdapter),
            abi.encodeWithSelector(IPoolAdapter.supply.selector, pool, alice, asset.assetAddress, asset.amount)
        );

        vault.supplyToPool(asset, poolAdapter, pool, alice);
    }

    function test_shouldFail_whenIncompleteTransaction() external {
        vm.mockCall(
            asset.assetAddress,
            abi.encodeWithSignature("balanceOf(address)", address(vault)),
            abi.encode(asset.amount)
        );

        vm.expectRevert(abi.encodeWithSelector(PWNVault.IncompleteTransfer.selector));
        vault.supplyToPool(asset, poolAdapter, pool, alice);
    }

    function test_shouldEmitEvent_PoolSupply() external {
        vm.expectEmit();
        emit PoolSupply(asset, address(poolAdapter), pool, alice);

        vault.supplyToPool(asset, poolAdapter, pool, alice);
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
        vm.expectRevert(abi.encodeWithSelector(PWNVault.UnsupportedTransferFunction.selector));
        vault.onERC721Received(address(0), address(0), 0, "");
    }

    function test_shouldReturnCorrectValue_whenOperatorIsVault_onERC1155Received() external {
        bytes4 returnValue = vault.onERC1155Received(address(vault), address(0), 0, 0, "");

        assertTrue(returnValue == IERC1155Receiver.onERC1155Received.selector);
    }

    function test_shouldFail_whenOperatorIsNotVault_onERC1155Received() external {
        vm.expectRevert(abi.encodeWithSelector(PWNVault.UnsupportedTransferFunction.selector));
        vault.onERC1155Received(address(0), address(0), 0, 0, "");
    }

    function test_shouldFail_whenOnERC1155BatchReceived() external {
        uint256[] memory ids;
        uint256[] memory values;

        vm.expectRevert(abi.encodeWithSelector(PWNVault.UnsupportedTransferFunction.selector));
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
