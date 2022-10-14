// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "MultiToken/MultiToken.sol";

import "../../src/hub/PWNHubTags.sol";
import "../../src/loan/type/PWNSimpleLoan.sol";
import "../../src/loan-factory/simple-loan/offer/PWNSimpleLoanSimpleOffer.sol";


abstract contract PWNSimpleLoanSimpleOfferTest is Test {

    bytes32 internal constant OFFERS_MADE_SLOT = bytes32(uint256(0)); // `offersMade` mapping position

    PWNSimpleLoanSimpleOffer offerContract;
    address hub = address(0x80b);
    address revokedOfferNonce = address(0x80c);
    address activeLoanContract = address(0x80d);
    PWNSimpleLoanSimpleOffer.Offer offer;
    address token = address(0x070ce2);
    uint256 lenderPK = uint256(73661723);
    address lender = vm.addr(lenderPK);

    event OfferMade(bytes32 indexed offerHash);

    constructor() {
        vm.etch(hub, bytes("data"));
        vm.etch(revokedOfferNonce, bytes("data"));
        vm.etch(token, bytes("data"));
    }

    function setUp() virtual public {
        offerContract = new PWNSimpleLoanSimpleOffer(hub, revokedOfferNonce);

        offer = PWNSimpleLoanSimpleOffer.Offer({
            collateralCategory: MultiToken.Category.ERC721,
            collateralAddress: token,
            collateralId: 42,
            collateralAmount: 1032,
            loanAssetAddress: token,
            loanAmount: 1101001,
            loanYield: 1,
            duration: 1000,
            expiration: 0,
            borrower: address(0),
            lender: lender,
            isPersistent: false,
            nonce: keccak256("nonce_1")
        });

        vm.mockCall(
            revokedOfferNonce,
            abi.encodeWithSignature("revokedOfferNonces(address,bytes32)"),
            abi.encode(false)
        );
    }


    function _mockMadeOffer(PWNSimpleLoanSimpleOffer.Offer memory _offer) internal {
        vm.store(
            address(offerContract),
            keccak256(abi.encode(_offerHash(_offer), OFFERS_MADE_SLOT)),
            bytes32(uint256(1))
        );
    }

    function _offerHash(PWNSimpleLoanSimpleOffer.Offer memory _offer) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            "\x19\x01",
            keccak256(abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("PWNSimpleLoanSimpleOffer"),
                keccak256("1"),
                block.chainid,
                address(offerContract)
            )),
            keccak256(abi.encodePacked(
                keccak256("Offer(uint8 collateralCategory,address collateralAddress,uint256 collateralId,uint256 collateralAmount,address loanAssetAddress,uint256 loanAmount,uint256 loanYield,uint32 duration,uint40 expiration,address borrower,address lender,bool isPersistent,bytes32 nonce)"),
                abi.encode(
                    _offer.collateralCategory,
                    _offer.collateralAddress,
                    _offer.collateralId,
                    _offer.collateralAmount
                ), // Need to prevent `slot(s) too deep inside the stack` error
                abi.encode(
                    _offer.loanAssetAddress,
                    _offer.loanAmount,
                    _offer.loanYield,
                    _offer.duration,
                    _offer.expiration,
                    _offer.borrower,
                    _offer.lender,
                    _offer.isPersistent,
                    _offer.nonce
                )
            ))
        ));
    }

}


/*----------------------------------------------------------*|
|*  # MAKE OFFER                                            *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanSimpleOffer_MakeOffer_Test is PWNSimpleLoanSimpleOfferTest {

    function test_shouldFail_whenCallerIsNotLender() external {
        vm.expectRevert("Caller is not stated as a lender");
        offerContract.makeOffer(offer);
    }

    function test_shouldFail_whenOfferHasBeenMadeAlready() external {
        _mockMadeOffer(offer);

        vm.expectRevert("Offer already exists");
        vm.prank(lender);
        offerContract.makeOffer(offer);
    }

    function test_shouldFail_whenOfferIsRevoked() external {
        vm.mockCall(
            revokedOfferNonce,
            abi.encodeWithSignature("revokedOfferNonces(address,bytes32)", offer.lender, offer.nonce),
            abi.encode(true)
        );

        vm.expectCall(
            revokedOfferNonce,
            abi.encodeWithSignature("revokedOfferNonces(address,bytes32)", offer.lender, offer.nonce)
        );

        vm.expectRevert("Offer nonce is revoked");
        vm.prank(lender);
        offerContract.makeOffer(offer);
    }

    function test_shouldMarkOfferAsMade() external {
        vm.prank(lender);
        offerContract.makeOffer(offer);

        bytes32 isMadeValue = vm.load(
            address(offerContract),
            keccak256(abi.encode(_offerHash(offer), OFFERS_MADE_SLOT))
        );
        assertEq(isMadeValue, bytes32(uint256(1)));
    }

    function test_shouldEmitEvent_OfferMade() external {
        vm.expectEmit(true, false, false, false);
        emit OfferMade(_offerHash(offer));

        vm.prank(lender);
        offerContract.makeOffer(offer);
    }

}


/*----------------------------------------------------------*|
|*  # REVOKE OFFER NONCE                                    *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanSimpleOffer_RevokeOfferNonce_Test is PWNSimpleLoanSimpleOfferTest {

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


/*----------------------------------------------------------*|
|*  # CREATE LOAN                                           *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanSimpleOffer_CreateLOAN_Test is PWNSimpleLoanSimpleOfferTest {

    bytes signature;
    address borrower = address(0x0303030303);

    function setUp() override public {
        super.setUp();

        vm.mockCall(
            address(hub),
            abi.encodeWithSignature("hasTag(address,bytes32)"),
            abi.encode(false)
        );
        vm.mockCall(
            address(hub),
            abi.encodeWithSignature("hasTag(address,bytes32)", activeLoanContract, PWNHubTags.ACTIVE_LOAN),
            abi.encode(true)
        );

        signature = "";
    }

    // Helpers

    function _signOffer(uint256 pk, PWNSimpleLoanSimpleOffer.Offer memory _offer) private returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _offerHash(_offer));
        return abi.encodePacked(r, s, v);
    }

    function _signOfferCompact(uint256 pk, PWNSimpleLoanSimpleOffer.Offer memory _offer) private returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _offerHash(_offer));
        return abi.encodePacked(r, bytes32(uint256(v) - 27) << 255 | s);
    }


    // Tests

    function test_shouldFail_whenCallerIsNotActiveLoan() external {
        vm.expectRevert("Caller is not active loan");
        offerContract.createLOAN(borrower, abi.encode(offer), signature);
    }

    function test_shouldFail_whenPassingInvalidOfferData() external {
        vm.expectRevert();
        vm.prank(activeLoanContract);
        offerContract.createLOAN(borrower, abi.encode(uint16(1), uint256(3213), address(0x01320), false, "whaaaaat?"), signature);
    }

    function test_shouldFail_whenInvalidSignature_whenEOA() external {
        signature = _signOffer(1, offer);

        vm.expectRevert("Invalid offer signature");
        vm.prank(activeLoanContract);
        offerContract.createLOAN(borrower, abi.encode(offer), signature);
    }

    function test_shouldFail_whenInvalidSignature_whenContractAccount() external {
        vm.etch(lender, bytes("data"));

        vm.expectRevert("Invalid offer signature");
        vm.prank(activeLoanContract);
        offerContract.createLOAN(borrower, abi.encode(offer), signature);
    }

    function test_shouldPass_whenOfferHasBeenMadeOnchain() external {
        _mockMadeOffer(offer);

        vm.prank(activeLoanContract);
        offerContract.createLOAN(borrower, abi.encode(offer), signature);
    }

    function test_shouldPass_withValidSignature_whenEOA_whenStandardSignature() external {
        signature = _signOffer(lenderPK, offer);

        vm.prank(activeLoanContract);
        offerContract.createLOAN(borrower, abi.encode(offer), signature);
    }

    function test_shouldPass_withValidSignature_whenEOA_whenCompactEIP2098Signature() external {
        signature = _signOfferCompact(lenderPK, offer);

        vm.prank(activeLoanContract);
        offerContract.createLOAN(borrower, abi.encode(offer), signature);
    }

    function test_shouldPass_whenValidSignature_whenContractAccount() external {
        vm.etch(lender, bytes("data"));

        vm.mockCall(
            lender,
            abi.encodeWithSignature("isValidSignature(bytes32,bytes)"),
            abi.encode(bytes4(0x1626ba7e))
        );

        vm.prank(activeLoanContract);
        offerContract.createLOAN(borrower, abi.encode(offer), signature);
    }

    function test_shouldFail_whenOfferIsExpired() external {
        vm.warp(40303);
        offer.expiration = 30303;
        signature = _signOfferCompact(lenderPK, offer);

        vm.expectRevert("Offer is expired");
        vm.prank(activeLoanContract);
        offerContract.createLOAN(borrower, abi.encode(offer), signature);
    }

    function test_shouldPass_whenOfferHasNoExpiration() external {
        vm.warp(40303);
        offer.expiration = 0;
        signature = _signOfferCompact(lenderPK, offer);

        vm.prank(activeLoanContract);
        offerContract.createLOAN(borrower, abi.encode(offer), signature);
    }

    function test_shouldPass_whenOfferIsNotExpired() external {
        vm.warp(40303);
        offer.expiration = 50303;
        signature = _signOfferCompact(lenderPK, offer);

        vm.prank(activeLoanContract);
        offerContract.createLOAN(borrower, abi.encode(offer), signature);
    }

    function test_shouldFail_whenOfferIsRevoked() external {
        signature = _signOfferCompact(lenderPK, offer);

        vm.mockCall(
            revokedOfferNonce,
            abi.encodeWithSignature("revokedOfferNonces(address,bytes32)"),
            abi.encode(true)
        );
        vm.expectCall(
            revokedOfferNonce,
            abi.encodeWithSignature("revokedOfferNonces(address,bytes32)", offer.lender, offer.nonce)
        );

        vm.expectRevert("Offer is revoked or has been accepted");
        vm.prank(activeLoanContract);
        offerContract.createLOAN(borrower, abi.encode(offer), signature);
    }

    function test_shouldFail_whenCallerIsNotBorrower_whenSetBorrower() external {
        offer.borrower = address(0x50303);
        signature = _signOfferCompact(lenderPK, offer);

        vm.expectRevert("Caller is not offer borrower");
        vm.prank(activeLoanContract);
        offerContract.createLOAN(borrower, abi.encode(offer), signature);
    }

    function test_shouldRevokeOffer_whenIsNotPersistent() external {
        offer.isPersistent = false;
        signature = _signOfferCompact(lenderPK, offer);

        vm.expectCall(
            revokedOfferNonce,
            abi.encodeWithSignature("revokeOfferNonce(address,bytes32)", offer.lender, offer.nonce)
        );

        vm.prank(activeLoanContract);
        offerContract.createLOAN(borrower, abi.encode(offer), signature);
    }

    // This test should fail because `revokeOfferNonce` is not called for persistent offer
    function testFail_shouldNotRevokeOffer_whenIsPersistent() external {
        offer.isPersistent = true;
        signature = _signOfferCompact(lenderPK, offer);

        vm.expectCall(
            revokedOfferNonce,
            abi.encodeWithSignature("revokeOfferNonce(address,bytes32)", offer.lender, offer.nonce)
        );

        vm.prank(activeLoanContract);
        offerContract.createLOAN(borrower, abi.encode(offer), signature);
    }

    function test_shouldReturnCorrectValues() external {
        uint256 currentTimestamp = 40303;
        vm.warp(currentTimestamp);
        signature = _signOfferCompact(lenderPK, offer);

        vm.prank(activeLoanContract);
        (PWNSimpleLoan.LOAN memory loan, address _lender, address _borrower) = offerContract.createLOAN(borrower, abi.encode(offer), signature);

        // LOAN
        assertTrue(loan.status == 2);
        assertTrue(loan.borrower == borrower);
        assertTrue(loan.duration == offer.duration);
        assertTrue(loan.expiration == currentTimestamp + offer.duration);
        assertTrue(loan.collateral.category == offer.collateralCategory);
        assertTrue(loan.collateral.assetAddress == offer.collateralAddress);
        assertTrue(loan.collateral.id == offer.collateralId);
        assertTrue(loan.collateral.amount == offer.collateralAmount);
        assertTrue(loan.asset.category == MultiToken.Category.ERC20);
        assertTrue(loan.asset.assetAddress == offer.loanAssetAddress);
        assertTrue(loan.asset.id == 0);
        assertTrue(loan.asset.amount == offer.loanAmount);
        assertTrue(loan.loanRepayAmount ==offer.loanAmount + offer.loanYield);
        // Lender
        assertTrue(_lender == offer.lender);
        // Borrower
        assertTrue(_borrower == borrower);
    }

}


/*----------------------------------------------------------*|
|*  # GET OFFER HASH                                        *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanSimpleOffer_GetOfferHash_Test is PWNSimpleLoanSimpleOfferTest {

    function test_shouldReturnOfferHash() external {
        assertEq(_offerHash(offer), offerContract.getOfferHash(offer));
    }

}
