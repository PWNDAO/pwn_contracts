// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../../src/hub/PWNHubTags.sol";
import "../../src/loan-factory/PWNRevokedOfferNonce.sol";


abstract contract PWNRevokedOfferNonceTest is Test {

    bytes32 internal constant REVOKED_OFFER_NONCES_SLOT = bytes32(uint256(0)); // `revokedOfferNonces` mapping position

    PWNRevokedOfferNonce revokedOfferNonce;
    address hub = address(0x80b);
    address alice = address(0xa11ce);
    bytes32 nonce = keccak256("nonce_1");

    event OfferNonceRevoked(address indexed owner, bytes32 indexed offerNonce);


    function setUp() public virtual {
        revokedOfferNonce = new PWNRevokedOfferNonce(hub);
    }


    function _revokedOfferNonceSlot(address owner, bytes32 _nonce) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            _nonce,
            keccak256(abi.encode(
                owner,
                REVOKED_OFFER_NONCES_SLOT
            ))
        ));
    }

}


/*----------------------------------------------------------*|
|*  # REVOKE OFFER NONCE                                    *|
|*----------------------------------------------------------*/

contract PWNRevokedOfferNonce_RevokeOfferNonce_Test is PWNRevokedOfferNonceTest {

    function test_shouldFail_whenNonceIsRevoked() external {
        vm.store(
            address(revokedOfferNonce),
            _revokedOfferNonceSlot(alice, nonce),
            bytes32(uint256(1))
        );

        vm.expectRevert("Nonce is already revoked");
        vm.prank(alice);
        revokedOfferNonce.revokeOfferNonce(nonce);
    }

    function test_shouldStoreNonceAsRevoked() external {
        vm.prank(alice);
        revokedOfferNonce.revokeOfferNonce(nonce);

        bytes32 isRevokedValue = vm.load(
            address(revokedOfferNonce),
            _revokedOfferNonceSlot(alice, nonce)
        );
        assertTrue(uint256(isRevokedValue) == 1);
    }

    function test_shouldEmitOfferNonceRevokedEvent() external {
        vm.expectEmit(true, true, false, false);
        emit OfferNonceRevoked(alice, nonce);

        vm.prank(alice);
        revokedOfferNonce.revokeOfferNonce(nonce);
    }

}


/*----------------------------------------------------------*|
|*  # REVOKE OFFER NONCE BY LOAN OFFER                      *|
|*----------------------------------------------------------*/

contract PWNRevokedOfferNonce_RevokeOfferNonceWithOwner_Test is PWNRevokedOfferNonceTest {

    address loanOffer = address(0x01);

    function setUp() override public {
        super.setUp();

        vm.mockCall(
            hub,
            abi.encodeWithSignature("hasTag(address,bytes32)"),
            abi.encode(false)
        );
        vm.mockCall(
            hub,
            abi.encodeWithSignature("hasTag(address,bytes32)", loanOffer, PWNHubTags.LOAN_OFFER),
            abi.encode(true)
        );
    }


    function test_shouldFail_whenCallerIsNotActiveLoanContract() external {
        vm.expectRevert("Caller is not loan offer");
        vm.prank(alice);
        revokedOfferNonce.revokeOfferNonce(alice, nonce);
    }

    function test_shouldFail_whenNonceIsRevoked() external {
        vm.store(
            address(revokedOfferNonce),
            _revokedOfferNonceSlot(alice, nonce),
            bytes32(uint256(1))
        );

        vm.expectRevert("Nonce is already revoked");
        vm.prank(loanOffer);
        revokedOfferNonce.revokeOfferNonce(alice, nonce);
    }

    function test_shouldStoreNonceAsRevoked() external {
        vm.prank(loanOffer);
        revokedOfferNonce.revokeOfferNonce(alice, nonce);

        bytes32 isRevokedValue = vm.load(
            address(revokedOfferNonce),
            _revokedOfferNonceSlot(alice, nonce)
        );
        assertTrue(uint256(isRevokedValue) == 1);
    }

    function test_shouldEmitOfferNonceRevokedEvent() external {
        vm.expectEmit(true, true, false, false);
        emit OfferNonceRevoked(alice, nonce);

        vm.prank(loanOffer);
        revokedOfferNonce.revokeOfferNonce(alice, nonce);
    }

}