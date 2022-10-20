// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "@pwn/hub/PWNHubTags.sol";
import "@pwn/loan-factory/PWNRevokedRequestNonce.sol";
import "@pwn/PWNError.sol";


abstract contract PWNRevokedRequestNonceTest is Test {

    bytes32 internal constant REVOKED_REQUEST_NONCES_SLOT = bytes32(uint256(0)); // `revokedRequestNonces` mapping position

    PWNRevokedRequestNonce revokedRequestNonce;
    address hub = address(0x80b);
    address alice = address(0xa11ce);
    bytes32 nonce = keccak256("nonce_1");

    event RequestNonceRevoked(address indexed owner, bytes32 indexed requestNonce);


    function setUp() public virtual {
        revokedRequestNonce = new PWNRevokedRequestNonce(hub);
    }


    function _revokedRequestNonceSlot(address owner, bytes32 _nonce) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            _nonce,
            keccak256(abi.encode(
                owner,
                REVOKED_REQUEST_NONCES_SLOT
            ))
        ));
    }

}


/*----------------------------------------------------------*|
|*  # REVOKE REQUEST NONCE                                  *|
|*----------------------------------------------------------*/

contract PWNRevokedRequestNonce_RevokeRequestNonce_Test is PWNRevokedRequestNonceTest {

    function test_shouldFail_whenNonceIsRevoked() external {
        vm.store(
            address(revokedRequestNonce),
            _revokedRequestNonceSlot(alice, nonce),
            bytes32(uint256(1))
        );

        vm.expectRevert(abi.encodeWithSelector(PWNError.NonceRevoked.selector));
        vm.prank(alice);
        revokedRequestNonce.revokeRequestNonce(nonce);
    }

    function test_shouldStoreNonceAsRevoked() external {
        vm.prank(alice);
        revokedRequestNonce.revokeRequestNonce(nonce);

        bytes32 isRevokedValue = vm.load(
            address(revokedRequestNonce),
            _revokedRequestNonceSlot(alice, nonce)
        );
        assertTrue(uint256(isRevokedValue) == 1);
    }

    function test_shouldEmitEvent_RequestNonceRevoked() external {
        vm.expectEmit(true, true, false, false);
        emit RequestNonceRevoked(alice, nonce);

        vm.prank(alice);
        revokedRequestNonce.revokeRequestNonce(nonce);
    }

}


/*----------------------------------------------------------*|
|*  # REVOKE REQUEST NONCE BY LOAN REQUEST                  *|
|*----------------------------------------------------------*/

contract PWNRevokedRequestNonce_RevokeRequestNonceWithOwner_Test is PWNRevokedRequestNonceTest {

    address loanRequest = address(0x01);

    function setUp() override public {
        super.setUp();

        vm.mockCall(
            hub,
            abi.encodeWithSignature("hasTag(address,bytes32)"),
            abi.encode(false)
        );
        vm.mockCall(
            hub,
            abi.encodeWithSignature("hasTag(address,bytes32)", loanRequest, PWNHubTags.LOAN_REQUEST),
            abi.encode(true)
        );
    }


    function test_shouldFail_whenCallerIsNotLoanRequestContract() external {
        vm.expectRevert(abi.encodeWithSelector(PWNError.CallerMissingHubTag.selector, PWNHubTags.LOAN_REQUEST));
        vm.prank(alice);
        revokedRequestNonce.revokeRequestNonce(alice, nonce);
    }

    function test_shouldFail_whenNonceIsRevoked() external {
        vm.store(
            address(revokedRequestNonce),
            _revokedRequestNonceSlot(alice, nonce),
            bytes32(uint256(1))
        );

        vm.expectRevert(abi.encodeWithSelector(PWNError.NonceRevoked.selector));
        vm.prank(loanRequest);
        revokedRequestNonce.revokeRequestNonce(alice, nonce);
    }

    function test_shouldStoreNonceAsRevoked() external {
        vm.prank(loanRequest);
        revokedRequestNonce.revokeRequestNonce(alice, nonce);

        bytes32 isRevokedValue = vm.load(
            address(revokedRequestNonce),
            _revokedRequestNonceSlot(alice, nonce)
        );
        assertTrue(uint256(isRevokedValue) == 1);
    }

    function test_shouldEmitEvent_RequestNonceRevoked() external {
        vm.expectEmit(true, true, false, false);
        emit RequestNonceRevoked(alice, nonce);

        vm.prank(loanRequest);
        revokedRequestNonce.revokeRequestNonce(alice, nonce);
    }

}


/*----------------------------------------------------------*|
|*  # IS REQUEST NONCE REVOKED                              *|
|*----------------------------------------------------------*/

contract PWNRevokedRequestNonce_IsOfferNonceRevoked_Test is PWNRevokedRequestNonceTest {

    function test_shouldReturnTrue_whenNonceIsRevoked() external {
        vm.store(
            address(revokedRequestNonce),
            _revokedRequestNonceSlot(alice, nonce),
            bytes32(uint256(1))
        );

        bool isRevoked = revokedRequestNonce.isRequestNonceRevoked(alice, nonce);

        assertTrue(isRevoked);
    }

    function test_shouldReturnFalse_whenNonceIsNotRevoked() external {
        bool isRevoked = revokedRequestNonce.isRequestNonceRevoked(alice, nonce);

        assertFalse(isRevoked);
    }

}
