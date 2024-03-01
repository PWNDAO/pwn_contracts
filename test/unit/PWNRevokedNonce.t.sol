// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "@pwn/hub/PWNHubTags.sol";
import "@pwn/nonce/PWNRevokedNonce.sol";
import "@pwn/PWNErrors.sol";


abstract contract PWNRevokedNonceTest is Test {

    bytes32 internal constant REVOKED_NONCE_SLOT = bytes32(uint256(0)); // `_revokedNonce` mapping position
    bytes32 internal constant NONCE_SPACE_SLOT = bytes32(uint256(1)); // `_nonceSpace` mapping position

    PWNRevokedNonce revokedNonce;
    bytes32 accessTag = keccak256("Some nice pwn tag");
    address hub = address(0x80b);
    address alice = address(0xa11ce);

    event NonceRevoked(address indexed owner, uint256 indexed nonceSpace, uint256 indexed nonce);
    event NonceSpaceRevoked(address indexed owner, uint256 indexed nonceSpace);


    function setUp() public virtual {
        revokedNonce = new PWNRevokedNonce(hub, accessTag);
    }


    function _revokedNonceSlot(address _owner, uint256 _nonceSpace, uint256 _nonce) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            _nonce,
            keccak256(abi.encode(
                _nonceSpace,
                keccak256(abi.encode(_owner, REVOKED_NONCE_SLOT))
            ))
        ));
    }

    function _nonceSpaceSlot(address _owner) internal pure returns (bytes32) {
        return keccak256(abi.encode(_owner, NONCE_SPACE_SLOT));
    }

}


/*----------------------------------------------------------*|
|*  # REVOKE NONCE BY OWNER                                 *|
|*----------------------------------------------------------*/

contract PWNRevokedNonce_RevokeNonceByOwner_Test is PWNRevokedNonceTest {

    function testFuzz_shouldStoreNonceAsRevoked(uint256 nonceSpace, uint256 nonce) external {
        vm.prank(alice);
        revokedNonce.revokeNonce(nonceSpace, nonce);

        bytes32 isRevokedValue = vm.load(
            address(revokedNonce),
            _revokedNonceSlot(alice, nonceSpace, nonce)
        );
        assertTrue(uint256(isRevokedValue) == 1);
    }

    function testFuzz_shouldEmit_NonceRevoked(uint256 nonceSpace, uint256 nonce) external {
        vm.expectEmit();
        emit NonceRevoked(alice, nonceSpace, nonce);

        vm.prank(alice);
        revokedNonce.revokeNonce(nonceSpace, nonce);
    }

}


/*----------------------------------------------------------*|
|*  # REVOKE NONCE WITH OWNER                               *|
|*----------------------------------------------------------*/

contract PWNRevokedNonce_RevokeNonceWithOwner_Test is PWNRevokedNonceTest {

    address accessEnabledAddress = address(0x01);

    function setUp() override public {
        super.setUp();

        vm.mockCall(
            hub,
            abi.encodeWithSignature("hasTag(address,bytes32)"),
            abi.encode(false)
        );
        vm.mockCall(
            hub,
            abi.encodeWithSignature("hasTag(address,bytes32)", accessEnabledAddress, accessTag),
            abi.encode(true)
        );
    }


    function testFuzz_shouldFail_whenCallerIsDoesNotHaveAccessTag(address caller) external {
        vm.assume(caller != accessEnabledAddress);

        vm.expectRevert(abi.encodeWithSelector(CallerMissingHubTag.selector, accessTag));
        vm.prank(caller);
        revokedNonce.revokeNonce(caller, 1, 1);
    }

    function testFuzz_shouldStoreNonceAsRevoked(address owner, uint256 nonceSpace, uint256 nonce) external {
        vm.prank(accessEnabledAddress);
        revokedNonce.revokeNonce(owner, nonceSpace, nonce);

        bytes32 isRevokedValue = vm.load(
            address(revokedNonce),
            _revokedNonceSlot(owner, nonceSpace, nonce)
        );
        assertTrue(uint256(isRevokedValue) == 1);
    }

    function testFuzz_shouldEmit_NonceRevoked(address owner, uint256 nonceSpace, uint256 nonce) external {
        vm.expectEmit();
        emit NonceRevoked(owner, nonceSpace, nonce);

        vm.prank(accessEnabledAddress);
        revokedNonce.revokeNonce(owner, nonceSpace, nonce);
    }

}


/*----------------------------------------------------------*|
|*  # IS NONCE REVOKED                                      *|
|*----------------------------------------------------------*/

contract PWNRevokedNonce_IsNonceRevoked_Test is PWNRevokedNonceTest {

    function testFuzz_shouldReturnTrue_whenNonceSpaceIsSmallerThanCurrentNonceSpace(uint256 currentNonceSpace, uint256 nonce) external {
        currentNonceSpace = bound(currentNonceSpace, 1, type(uint256).max);
        uint256 nonceSpace = bound(currentNonceSpace, 0, currentNonceSpace - 1);

        vm.store(address(revokedNonce), _nonceSpaceSlot(alice), bytes32(currentNonceSpace));

        assertTrue(revokedNonce.isNonceRevoked(alice, nonceSpace, nonce));
    }

    function testFuzz_shouldReturnTrue_whenNonceIsRevoked(uint256 nonce) external {
        vm.store(address(revokedNonce), _revokedNonceSlot(alice, 0, nonce), bytes32(uint256(1)));

        assertTrue(revokedNonce.isNonceRevoked(alice, 0, nonce));
    }

    function testFuzz_shouldReturnFalse_whenNonceIsNotRevoked(uint256 nonceSpace, uint256 nonce) external {
        assertFalse(revokedNonce.isNonceRevoked(alice, nonceSpace, nonce));
    }

}


/*----------------------------------------------------------*|
|*  # REVOKE NONCE SPACE                                    *|
|*----------------------------------------------------------*/

contract PWNRevokedNonce_RevokeNonceSpace_Test is PWNRevokedNonceTest {

    function testFuzz_shouldIncrementCurrentNonceSpace(uint256 nonceSpace) external {
        nonceSpace = bound(nonceSpace, 0, type(uint256).max - 1);
        bytes32 nonceSpaceSlot = _nonceSpaceSlot(alice);
        vm.store(address(revokedNonce), nonceSpaceSlot, bytes32(nonceSpace));

        vm.prank(alice);
        revokedNonce.revokeNonceSpace();

        assertEq(revokedNonce.currentNonceSpace(alice), nonceSpace + 1);
    }

    function testFuzz_shouldEmit_NonceSpaceRevoked(uint256 nonceSpace) external {
        nonceSpace = bound(nonceSpace, 0, type(uint256).max - 1);
        bytes32 nonceSpaceSlot = _nonceSpaceSlot(alice);
        vm.store(address(revokedNonce), nonceSpaceSlot, bytes32(nonceSpace));

        vm.expectEmit();
        emit NonceSpaceRevoked(alice, nonceSpace);

        vm.prank(alice);
        revokedNonce.revokeNonceSpace();
    }

    function testFuzz_shouldReturnNewNonceSpace(uint256 nonceSpace) external {
        nonceSpace = bound(nonceSpace, 0, type(uint256).max - 1);
        bytes32 nonceSpaceSlot = _nonceSpaceSlot(alice);
        vm.store(address(revokedNonce), nonceSpaceSlot, bytes32(nonceSpace));

        vm.prank(alice);
        uint256 currentNonceSpace = revokedNonce.revokeNonceSpace();

        assertEq(currentNonceSpace, nonceSpace + 1);
    }

}


/*----------------------------------------------------------*|
|*  # CURRENT NONCE SPACE                                   *|
|*----------------------------------------------------------*/

contract PWNRevokedNonce_CurrentNonceSpace_Test is PWNRevokedNonceTest {

    function testFuzz_shouldReturnCurrentNonceSpace(uint256 nonceSpace) external {
        vm.store(address(revokedNonce), _nonceSpaceSlot(alice), bytes32(nonceSpace));

        uint256 currentNonceSpace = revokedNonce.currentNonceSpace(alice);

        assertEq(currentNonceSpace, nonceSpace);
    }

}
