// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "MultiToken/MultiToken.sol";

import "@pwn/hub/PWNHubTags.sol";
import "@pwn/loan/type/PWNSimpleLoan.sol";
import "@pwn/loan-factory/simple-loan/offer/PWNSimpleLoanSimpleOffer.sol";


// The only reason for this contract is to expose internal functions of PWNVault
// No additional logic is applied here
contract PWNSimpleLoanOfferExposed is PWNSimpleLoanOffer {

    constructor(address hub, address _revokedOfferNonce) PWNSimpleLoanOffer(hub, _revokedOfferNonce) {

    }

    function makeOffer(bytes32 offerHash, address lender, bytes32 nonce) external {
        _makeOffer(offerHash, lender, nonce);
    }

    // Dummy implementation, is not tester here
    function createLOAN(
        address /*caller*/,
        bytes calldata /*loanFactoryData*/,
        bytes calldata /*signature*/
    ) override external pure returns (PWNSimpleLoan.LOAN memory, address, address) {
        return (
            PWNSimpleLoan.LOAN({
                status: 0,
                borrower: address(0),
                duration: 0,
                expiration: 0,
                collateral: MultiToken.Asset(MultiToken.Category.ERC20, address(0), 0, 0),
                asset: MultiToken.Asset(MultiToken.Category.ERC20, address(0), 0, 0),
                loanRepayAmount: 0
            }),
            address(0),
            address(0)
        );
    }

}

abstract contract PWNSimpleLoanOfferTest is Test {

    bytes32 internal constant OFFERS_MADE_SLOT = bytes32(uint256(0)); // `offersMade` mapping position

    PWNSimpleLoanOfferExposed offerContract;
    address hub = address(0x80b);
    address revokedOfferNonce = address(0x80c);

    bytes32 offerHash = keccak256("offer_hash_1");
    address lender = address(0x070ce3);
    bytes32 nonce = keccak256("nonce_1");

    event OfferMade(bytes32 indexed offerHash);

    constructor() {
        vm.etch(hub, bytes("data"));
        vm.etch(revokedOfferNonce, bytes("data"));
    }

    function setUp() virtual public {
        offerContract = new PWNSimpleLoanOfferExposed(hub, revokedOfferNonce);

        vm.mockCall(
            revokedOfferNonce,
            abi.encodeWithSignature("revokedOfferNonces(address,bytes32)"),
            abi.encode(false)
        );
    }

}


/*----------------------------------------------------------*|
|*  # MAKE OFFER                                            *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanSimpleOffer_MakeOffer_Test is PWNSimpleLoanOfferTest {

    function test_shouldFail_whenCallerIsNotLender() external {
        vm.expectRevert("Caller is not stated as a lender");
        offerContract.makeOffer(offerHash, lender, nonce);
    }

    function test_shouldFail_whenOfferHasBeenMadeAlready() external {
        vm.store(
            address(offerContract),
            keccak256(abi.encode(offerHash, OFFERS_MADE_SLOT)),
            bytes32(uint256(1))
        );

        vm.expectRevert("Offer already exists");
        vm.prank(lender);
        offerContract.makeOffer(offerHash, lender, nonce);
    }

    function test_shouldFail_whenOfferIsRevoked() external {
        vm.mockCall(
            revokedOfferNonce,
            abi.encodeWithSignature("revokedOfferNonces(address,bytes32)", lender, nonce),
            abi.encode(true)
        );

        vm.expectCall(
            revokedOfferNonce,
            abi.encodeWithSignature("revokedOfferNonces(address,bytes32)", lender, nonce)
        );

        vm.expectRevert("Offer nonce is revoked");
        vm.prank(lender);
        offerContract.makeOffer(offerHash, lender, nonce);
    }

    function test_shouldMarkOfferAsMade() external {
        vm.prank(lender);
        offerContract.makeOffer(offerHash, lender, nonce);

        bytes32 isMadeValue = vm.load(
            address(offerContract),
            keccak256(abi.encode(offerHash, OFFERS_MADE_SLOT))
        );
        assertEq(isMadeValue, bytes32(uint256(1)));
    }

    function test_shouldEmitEvent_OfferMade() external {
        vm.expectEmit(true, false, false, false);
        emit OfferMade(offerHash);

        vm.prank(lender);
        offerContract.makeOffer(offerHash, lender, nonce);
    }

}


/*----------------------------------------------------------*|
|*  # REVOKE OFFER NONCE                                    *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanSimpleOffer_RevokeOfferNonce_Test is PWNSimpleLoanOfferTest {

    function test_shouldCallRevokeOfferNonce() external {
        bytes32 nonce = keccak256("its my monkey");

        vm.expectCall(
            revokedOfferNonce,
            abi.encodeWithSignature("revokeOfferNonce(address,bytes32)", lender, nonce)
        );

        vm.prank(lender);
        offerContract.revokeOfferNonce(nonce);
    }

}
