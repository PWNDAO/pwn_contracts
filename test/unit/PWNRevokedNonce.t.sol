// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "@pwn/hub/PWNHubTags.sol";
import "@pwn/nonce/PWNRevokedNonce.sol";
import "@pwn/PWNErrors.sol";


abstract contract PWNRevokedNonceTest is Test {

    bytes32 internal constant REVOKED_NONCES_SLOT = bytes32(uint256(0)); // `revokedNonces` mapping position

    PWNRevokedNonce revokedNonce;
    bytes32 accessTag = keccak256("Some nice pwn tag");
    address hub = address(0x80b);
    address alice = address(0xa11ce);
    bytes32 nonce = keccak256("nonce_1");

    event NonceRevoked(address indexed owner, bytes32 indexed nonce);


    function setUp() public virtual {
        revokedNonce = new PWNRevokedNonce(hub, accessTag);
    }


    function _revokedNonceSlot(address owner, bytes32 _nonce) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            _nonce,
            keccak256(abi.encode(
                owner,
                REVOKED_NONCES_SLOT
            ))
        ));
    }

}


/*----------------------------------------------------------*|
|*  # REVOKE NONCE BY OWNER                                 *|
|*----------------------------------------------------------*/

contract PWNRevokedNonce_RevokeNonceByOwner_Test is PWNRevokedNonceTest {

    function test_shouldFail_whenNonceIsRevoked() external {
        vm.store(
            address(revokedNonce),
            _revokedNonceSlot(alice, nonce),
            bytes32(uint256(1))
        );

        vm.expectRevert(abi.encodeWithSelector(NonceAlreadyRevoked.selector));
        vm.prank(alice);
        revokedNonce.revokeNonce(nonce);
    }

    function test_shouldStoreNonceAsRevoked() external {
        vm.prank(alice);
        revokedNonce.revokeNonce(nonce);

        bytes32 isRevokedValue = vm.load(
            address(revokedNonce),
            _revokedNonceSlot(alice, nonce)
        );
        assertTrue(uint256(isRevokedValue) == 1);
    }

    function test_shouldEmitEvent_NonceRevoked() external {
        vm.expectEmit(true, true, false, false);
        emit NonceRevoked(alice, nonce);

        vm.prank(alice);
        revokedNonce.revokeNonce(nonce);
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


    function test_shouldFail_whenCallerIsNotLoanOfferContract() external {
        vm.expectRevert(abi.encodeWithSelector(CallerMissingHubTag.selector, accessTag));
        vm.prank(alice);
        revokedNonce.revokeNonce(alice, nonce);
    }

    function test_shouldFail_whenNonceIsRevoked() external {
        vm.store(
            address(revokedNonce),
            _revokedNonceSlot(alice, nonce),
            bytes32(uint256(1))
        );

        vm.expectRevert(abi.encodeWithSelector(NonceAlreadyRevoked.selector));
        vm.prank(accessEnabledAddress);
        revokedNonce.revokeNonce(alice, nonce);
    }

    function test_shouldStoreNonceAsRevoked() external {
        vm.prank(accessEnabledAddress);
        revokedNonce.revokeNonce(alice, nonce);

        bytes32 isRevokedValue = vm.load(
            address(revokedNonce),
            _revokedNonceSlot(alice, nonce)
        );
        assertTrue(uint256(isRevokedValue) == 1);
    }

    function test_shouldEmitEvent_NonceRevoked() external {
        vm.expectEmit(true, true, false, false);
        emit NonceRevoked(alice, nonce);

        vm.prank(accessEnabledAddress);
        revokedNonce.revokeNonce(alice, nonce);
    }

}


/*----------------------------------------------------------*|
|*  # IS NONCE REVOKED                                      *|
|*----------------------------------------------------------*/

contract PWNRevokedNonce_IsNonceRevoked_Test is PWNRevokedNonceTest {

    function test_shouldReturnTrue_whenNonceIsRevoked() external {
        vm.store(
            address(revokedNonce),
            _revokedNonceSlot(alice, nonce),
            bytes32(uint256(1))
        );

        bool isRevoked = revokedNonce.isNonceRevoked(alice, nonce);

        assertTrue(isRevoked);
    }

    function test_shouldReturnFalse_whenNonceIsNotRevoked() external {
        bool isRevoked = revokedNonce.isNonceRevoked(alice, nonce);

        assertFalse(isRevoked);
    }

}
