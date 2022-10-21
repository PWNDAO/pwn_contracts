// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "MultiToken/MultiToken.sol";

import "@pwn/hub/PWNHubTags.sol";
import "@pwn/loan/type/PWNSimpleLoan.sol";
import "@pwn/loan-factory/simple-loan/offer/PWNSimpleLoanSimpleOffer.sol";
import "@pwn/PWNErrors.sol";


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
            lateRepaymentEnabled: false,
            nonce: keccak256("nonce_1")
        });

        vm.mockCall(
            revokedOfferNonce,
            abi.encodeWithSignature("isNonceRevoked(address,bytes32)"),
            abi.encode(false)
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
                keccak256("Offer(uint8 collateralCategory,address collateralAddress,uint256 collateralId,uint256 collateralAmount,address loanAssetAddress,uint256 loanAmount,uint256 loanYield,uint32 duration,uint40 expiration,address borrower,address lender,bool isPersistent,bool lateRepaymentEnabled,bytes32 nonce)"),
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
                    _offer.lateRepaymentEnabled,
                    _offer.nonce
                )
            ))
        ));
    }

}


/*----------------------------------------------------------*|
|*  # MAKE OFFER                                            *|
|*----------------------------------------------------------*/

// Feature tested in PWNSimpleLoanOffer.t.sol
contract PWNSimpleLoanSimpleOffer_MakeOffer_Test is PWNSimpleLoanSimpleOfferTest {

    function test_shouldMakeOffer() external {
        vm.prank(lender);
        offerContract.makeOffer(offer);

        bytes32 isMadeValue = vm.load(
            address(offerContract),
            keccak256(abi.encode(_offerHash(offer), OFFERS_MADE_SLOT))
        );
        assertEq(isMadeValue, bytes32(uint256(1)));
    }

}


/*----------------------------------------------------------*|
|*  # GET LOAN TERMS                                        *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanSimpleOffer_GetLOANTerms_Test is PWNSimpleLoanSimpleOfferTest {

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
        vm.expectRevert(abi.encodeWithSelector(CallerMissingHubTag.selector, PWNHubTags.ACTIVE_LOAN));
        offerContract.getLOANTerms(borrower, abi.encode(offer), signature);
    }

    function test_shouldFail_whenPassingInvalidOfferData() external {
        vm.expectRevert();
        vm.prank(activeLoanContract);
        offerContract.getLOANTerms(borrower, abi.encode(uint16(1), uint256(3213), address(0x01320), false, "whaaaaat?"), signature);
    }

    function test_shouldFail_whenInvalidSignature_whenEOA() external {
        signature = _signOffer(1, offer);

        vm.expectRevert(abi.encodeWithSelector(InvalidSignature.selector));
        vm.prank(activeLoanContract);
        offerContract.getLOANTerms(borrower, abi.encode(offer), signature);
    }

    function test_shouldFail_whenInvalidSignature_whenContractAccount() external {
        vm.etch(lender, bytes("data"));

        vm.expectRevert(abi.encodeWithSelector(InvalidSignature.selector));
        vm.prank(activeLoanContract);
        offerContract.getLOANTerms(borrower, abi.encode(offer), signature);
    }

    function test_shouldPass_whenOfferHasBeenMadeOnchain() external {
        vm.store(
            address(offerContract),
            keccak256(abi.encode(_offerHash(offer), OFFERS_MADE_SLOT)),
            bytes32(uint256(1))
        );

        vm.prank(activeLoanContract);
        offerContract.getLOANTerms(borrower, abi.encode(offer), signature);
    }

    function test_shouldPass_withValidSignature_whenEOA_whenStandardSignature() external {
        signature = _signOffer(lenderPK, offer);

        vm.prank(activeLoanContract);
        offerContract.getLOANTerms(borrower, abi.encode(offer), signature);
    }

    function test_shouldPass_withValidSignature_whenEOA_whenCompactEIP2098Signature() external {
        signature = _signOfferCompact(lenderPK, offer);

        vm.prank(activeLoanContract);
        offerContract.getLOANTerms(borrower, abi.encode(offer), signature);
    }

    function test_shouldPass_whenValidSignature_whenContractAccount() external {
        vm.etch(lender, bytes("data"));

        vm.mockCall(
            lender,
            abi.encodeWithSignature("isValidSignature(bytes32,bytes)"),
            abi.encode(bytes4(0x1626ba7e))
        );

        vm.prank(activeLoanContract);
        offerContract.getLOANTerms(borrower, abi.encode(offer), signature);
    }

    function test_shouldFail_whenOfferIsExpired() external {
        vm.warp(40303);
        offer.expiration = 30303;
        signature = _signOfferCompact(lenderPK, offer);

        vm.expectRevert(abi.encodeWithSelector(OfferExpired.selector));
        vm.prank(activeLoanContract);
        offerContract.getLOANTerms(borrower, abi.encode(offer), signature);
    }

    function test_shouldPass_whenOfferHasNoExpiration() external {
        vm.warp(40303);
        offer.expiration = 0;
        signature = _signOfferCompact(lenderPK, offer);

        vm.prank(activeLoanContract);
        offerContract.getLOANTerms(borrower, abi.encode(offer), signature);
    }

    function test_shouldPass_whenOfferIsNotExpired() external {
        vm.warp(40303);
        offer.expiration = 50303;
        signature = _signOfferCompact(lenderPK, offer);

        vm.prank(activeLoanContract);
        offerContract.getLOANTerms(borrower, abi.encode(offer), signature);
    }

    function test_shouldFail_whenOfferIsRevoked() external {
        signature = _signOfferCompact(lenderPK, offer);

        vm.mockCall(
            revokedOfferNonce,
            abi.encodeWithSignature("isNonceRevoked(address,bytes32)"),
            abi.encode(true)
        );
        vm.expectCall(
            revokedOfferNonce,
            abi.encodeWithSignature("isNonceRevoked(address,bytes32)", offer.lender, offer.nonce)
        );

        vm.expectRevert(abi.encodeWithSelector(NonceAlreadyRevoked.selector));
        vm.prank(activeLoanContract);
        offerContract.getLOANTerms(borrower, abi.encode(offer), signature);
    }

    function test_shouldFail_whenCallerIsNotBorrower_whenSetBorrower() external {
        offer.borrower = address(0x50303);
        signature = _signOfferCompact(lenderPK, offer);

        vm.expectRevert(abi.encodeWithSelector(CallerIsNotStatedBorrower.selector, offer.borrower));
        vm.prank(activeLoanContract);
        offerContract.getLOANTerms(borrower, abi.encode(offer), signature);
    }

    function test_shouldRevokeOffer_whenIsNotPersistent() external {
        offer.isPersistent = false;
        signature = _signOfferCompact(lenderPK, offer);

        vm.expectCall(
            revokedOfferNonce,
            abi.encodeWithSignature("revokeNonce(address,bytes32)", offer.lender, offer.nonce)
        );

        vm.prank(activeLoanContract);
        offerContract.getLOANTerms(borrower, abi.encode(offer), signature);
    }

    // This test should fail because `revokeNonce` is not called for persistent offer
    function testFail_shouldNotRevokeOffer_whenIsPersistent() external {
        offer.isPersistent = true;
        signature = _signOfferCompact(lenderPK, offer);

        vm.expectCall(
            revokedOfferNonce,
            abi.encodeWithSignature("revokeNonce(address,bytes32)", offer.lender, offer.nonce)
        );

        vm.prank(activeLoanContract);
        offerContract.getLOANTerms(borrower, abi.encode(offer), signature);
    }

    function test_shouldReturnCorrectValues() external {
        uint256 currentTimestamp = 40303;
        vm.warp(currentTimestamp);
        signature = _signOfferCompact(lenderPK, offer);

        vm.prank(activeLoanContract);
        PWNSimpleLoan.LOANTerms memory loanTerms = offerContract.getLOANTerms(borrower, abi.encode(offer), signature);

        assertTrue(loanTerms.lender == offer.lender);
        assertTrue(loanTerms.borrower == borrower);
        assertTrue(loanTerms.expiration == currentTimestamp + offer.duration);
        assertTrue(loanTerms.lateRepaymentEnabled == offer.lateRepaymentEnabled);
        assertTrue(loanTerms.collateral.category == offer.collateralCategory);
        assertTrue(loanTerms.collateral.assetAddress == offer.collateralAddress);
        assertTrue(loanTerms.collateral.id == offer.collateralId);
        assertTrue(loanTerms.collateral.amount == offer.collateralAmount);
        assertTrue(loanTerms.asset.category == MultiToken.Category.ERC20);
        assertTrue(loanTerms.asset.assetAddress == offer.loanAssetAddress);
        assertTrue(loanTerms.asset.id == 0);
        assertTrue(loanTerms.asset.amount == offer.loanAmount);
        assertTrue(loanTerms.loanRepayAmount == offer.loanAmount + offer.loanYield);
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


/*----------------------------------------------------------*|
|*  # LOAN TERMS FACTORY DATA ENCODING                      *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanSimpleOffer_EncodeLoanTermsFactoryData_Test is PWNSimpleLoanSimpleOfferTest {

    function test_shouldReturnEncodedLoanTermsFactoryData() external {
        assertEq(abi.encode(offer), offerContract.encodeLoanTermsFactoryData(offer));
    }

}