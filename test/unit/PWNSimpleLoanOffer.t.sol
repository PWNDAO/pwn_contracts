// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "MultiToken/MultiToken.sol";

import "@pwn/hub/PWNHubTags.sol";
import "@pwn/loan/terms/simple/factory/offer/base/PWNSimpleLoanOffer.sol";
import "@pwn/loan/terms/PWNLOANTerms.sol";
import "@pwn/PWNErrors.sol";


// The only reason for this contract is to expose internal functions of PWNSimpleLoanOffer
// No additional logic is applied here
contract PWNSimpleLoanOfferExposed is PWNSimpleLoanOffer {

    constructor(address hub, address _revokedOfferNonce) PWNSimpleLoanOffer(hub, _revokedOfferNonce) {

    }

    function makeOffer(bytes32 offerHash, address lender) external {
        _makeOffer(offerHash, lender);
    }

    // Dummy implementation, is not tester here
    function createLOANTerms(
        address /*caller*/,
        bytes calldata /*factoryData*/,
        bytes calldata /*signature*/
    ) override external pure returns (PWNLOANTerms.Simple memory, bytes32) {
        revert("Missing implementation");
    }

}

abstract contract PWNSimpleLoanOfferTest is Test {

    bytes32 internal constant OFFERS_MADE_SLOT = bytes32(uint256(0)); // `offersMade` mapping position

    PWNSimpleLoanOfferExposed offerContract;
    address hub = address(0x80b);
    address revokedOfferNonce = address(0x80c);

    bytes32 offerHash = keccak256("offer_hash_1");
    address lender = address(0x070ce3);
    uint256 nonce = uint256(keccak256("nonce_1"));

    function setUp() virtual public {
        vm.etch(hub, bytes("data"));
        vm.etch(revokedOfferNonce, bytes("data"));

        offerContract = new PWNSimpleLoanOfferExposed(hub, revokedOfferNonce);

        vm.mockCall(
            revokedOfferNonce,
            abi.encodeWithSignature("isNonceRevoked(address,uint256)"),
            abi.encode(false)
        );
    }

}


/*----------------------------------------------------------*|
|*  # MAKE OFFER                                            *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanOffer_MakeOffer_Test is PWNSimpleLoanOfferTest {

    function test_shouldFail_whenCallerIsNotLender() external {
        vm.expectRevert(abi.encodeWithSelector(CallerIsNotStatedLender.selector, lender));
        offerContract.makeOffer(offerHash, lender);
    }

    function test_shouldMarkOfferAsMade() external {
        vm.prank(lender);
        offerContract.makeOffer(offerHash, lender);

        bytes32 isMadeValue = vm.load(
            address(offerContract),
            keccak256(abi.encode(offerHash, OFFERS_MADE_SLOT))
        );
        assertEq(isMadeValue, bytes32(uint256(1)));
    }

}


/*----------------------------------------------------------*|
|*  # REVOKE OFFER NONCE                                    *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanOffer_RevokeOfferNonce_Test is PWNSimpleLoanOfferTest {

    function test_shouldCallRevokeOfferNonce() external {
        uint256 nonce = uint256(keccak256("its my monkey"));

        vm.expectCall(
            revokedOfferNonce,
            abi.encodeWithSignature("revokeNonce(address,uint256)", lender, nonce)
        );

        vm.prank(lender);
        offerContract.revokeOfferNonce(nonce);
    }

}
