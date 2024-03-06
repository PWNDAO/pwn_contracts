// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "MultiToken/MultiToken.sol";

import "@pwn/hub/PWNHubTags.sol";
import "@pwn/loan/terms/simple/factory/offer/PWNSimpleLoanListOffer.sol";
import "@pwn/loan/terms/PWNLOANTerms.sol";
import "@pwn/PWNErrors.sol";


abstract contract PWNSimpleLoanListOfferTest is Test {

    bytes32 internal constant OFFERS_MADE_SLOT = bytes32(uint256(0)); // `offersMade` mapping position

    PWNSimpleLoanListOffer offerContract;
    address hub = address(0x80b);
    address revokedOfferNonce = address(0x80c);
    address stateFingerprintComputerRegistry = makeAddr("stateFingerprintComputerRegistry");
    address activeLoanContract = address(0x80d);
    PWNSimpleLoanListOffer.Offer offer;
    PWNSimpleLoanListOffer.OfferValues offerValues;
    address token = address(0x070ce2);
    uint256 lenderPK = uint256(73661723);
    address lender = vm.addr(lenderPK);

    event OfferMade(bytes32 indexed offerHash, address indexed lender, PWNSimpleLoanListOffer.Offer offer);

    function setUp() virtual public {
        vm.etch(hub, bytes("data"));
        vm.etch(revokedOfferNonce, bytes("data"));
        vm.etch(token, bytes("data"));

        offerContract = new PWNSimpleLoanListOffer(hub, revokedOfferNonce, stateFingerprintComputerRegistry);

        offer = PWNSimpleLoanListOffer.Offer({
            collateralCategory: MultiToken.Category.ERC721,
            collateralAddress: token,
            collateralIdsWhitelistMerkleRoot: bytes32(0),
            collateralAmount: 1032,
            checkCollateralStateFingerprint: true,
            collateralStateFingerprint: keccak256("some state fingerprint"),
            loanAssetAddress: token,
            loanAmount: 1101001,
            fixedInterestAmount: 1,
            accruingInterestAPR: 0,
            duration: 1000,
            expiration: 60303,
            allowedBorrower: address(0),
            lender: lender,
            isPersistent: false,
            nonceSpace: 1,
            nonce: uint256(keccak256("nonce_1"))
        });

        offerValues = PWNSimpleLoanListOffer.OfferValues({
            collateralId: 32,
            merkleInclusionProof: new bytes32[](0)
        });

        vm.mockCall(
            revokedOfferNonce,
            abi.encodeWithSignature("isNonceRevoked(address,uint256,uint256)"),
            abi.encode(false)
        );
    }


    function _offerHash(PWNSimpleLoanListOffer.Offer memory _offer) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            "\x19\x01",
            keccak256(abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("PWNSimpleLoanListOffer"),
                keccak256("1.2"),
                block.chainid,
                address(offerContract)
            )),
            keccak256(abi.encodePacked(
                keccak256("Offer(uint8 collateralCategory,address collateralAddress,bytes32 collateralIdsWhitelistMerkleRoot,uint256 collateralAmount,bool checkCollateralStateFingerprint,bytes32 collateralStateFingerprint,address loanAssetAddress,uint256 loanAmount,uint256 fixedInterestAmount,uint40 accruingInterestAPR,uint32 duration,uint40 expiration,address allowedBorrower,address lender,bool isPersistent,uint256 nonceSpace,uint256 nonce)"),
                abi.encode(_offer)
            ))
        ));
    }

}


/*----------------------------------------------------------*|
|*  # MAKE OFFER                                            *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanListOffer_MakeOffer_Test is PWNSimpleLoanListOfferTest {

    function testFuzz_shouldFail_whenCallerIsNotLender(address caller) external {
        vm.assume(caller != offer.lender);

        vm.expectRevert(abi.encodeWithSelector(CallerIsNotStatedLender.selector, lender));
        offerContract.makeOffer(offer);
    }

    function test_shouldEmit_OfferMade() external {
        vm.expectEmit();
        emit OfferMade(_offerHash(offer), offer.lender, offer);

        vm.prank(offer.lender);
        offerContract.makeOffer(offer);
    }

    function test_shouldMakeOffer() external {
        vm.prank(offer.lender);
        offerContract.makeOffer(offer);

        assertTrue(offerContract.offersMade(_offerHash(offer)));
    }

}


/*----------------------------------------------------------*|
|*  # REVOKE OFFER NONCE                                    *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanOffer_RevokeOfferNonce_Test is PWNSimpleLoanListOfferTest {

    function testFuzz_shouldCallRevokeOfferNonce(uint256 nonceSpace, uint256 nonce) external {
        vm.expectCall(
            revokedOfferNonce,
            abi.encodeWithSignature("revokeNonce(address,uint256,uint256)", lender, nonceSpace, nonce)
        );

        vm.prank(lender);
        offerContract.revokeOfferNonce(nonceSpace, nonce);
    }

}


/*----------------------------------------------------------*|
|*  # CREATE LOAN TERMS                                     *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanListOffer_CreateLOANTerms_Test is PWNSimpleLoanListOfferTest {

    bytes signature;
    address borrower = makeAddr("borrower");
    address stateFingerprintComputer = makeAddr("stateFingerprintComputer");

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

        vm.mockCall(
            stateFingerprintComputerRegistry,
            abi.encodeWithSignature("getStateFingerprintComputer(address)", offer.collateralAddress),
            abi.encode(stateFingerprintComputer)
        );
        vm.mockCall(
            stateFingerprintComputer,
            abi.encodeWithSignature("getStateFingerprint(uint256)" /* any collateral id */ ),
            abi.encode(offer.collateralStateFingerprint)
        );
    }

    // Helpers

    function _signOffer(uint256 pk, PWNSimpleLoanListOffer.Offer memory _offer) private view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _offerHash(_offer));
        return abi.encodePacked(r, s, v);
    }

    function _signOfferCompact(uint256 pk, PWNSimpleLoanListOffer.Offer memory _offer) private view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _offerHash(_offer));
        return abi.encodePacked(r, bytes32(uint256(v) - 27) << 255 | s);
    }


    // Tests

    function test_shouldFail_whenCallerIsNotActiveLoan() external {
        vm.expectRevert(abi.encodeWithSelector(CallerMissingHubTag.selector, PWNHubTags.ACTIVE_LOAN));
        offerContract.createLOANTerms(borrower, abi.encode(offer, offerValues), signature);
    }

    function test_shouldFail_whenPassingInvalidOfferData() external {
        vm.expectRevert();
        vm.prank(activeLoanContract);
        offerContract.createLOANTerms(borrower, abi.encode(uint16(1), uint256(3213), address(0x01320), false, "whaaaaat?"), signature);
    }

    function test_shouldFail_whenInvalidSignature_whenEOA() external {
        signature = _signOffer(1, offer);

        vm.expectRevert(abi.encodeWithSelector(InvalidSignature.selector));
        vm.prank(activeLoanContract);
        offerContract.createLOANTerms(borrower, abi.encode(offer, offerValues), signature);
    }

    function test_shouldFail_whenInvalidSignature_whenContractAccount() external {
        vm.etch(lender, bytes("data"));

        vm.expectRevert(abi.encodeWithSelector(InvalidSignature.selector));
        vm.prank(activeLoanContract);
        offerContract.createLOANTerms(borrower, abi.encode(offer, offerValues), signature);
    }

    function test_shouldPass_whenOfferHasBeenMadeOnchain() external {
        vm.store(
            address(offerContract),
            keccak256(abi.encode(_offerHash(offer), OFFERS_MADE_SLOT)),
            bytes32(uint256(1))
        );

        vm.prank(activeLoanContract);
        offerContract.createLOANTerms(borrower, abi.encode(offer, offerValues), signature);
    }

    function test_shouldPass_withValidSignature_whenEOA_whenStandardSignature() external {
        signature = _signOffer(lenderPK, offer);

        vm.prank(activeLoanContract);
        offerContract.createLOANTerms(borrower, abi.encode(offer, offerValues), signature);
    }

    function test_shouldPass_withValidSignature_whenEOA_whenCompactEIP2098Signature() external {
        signature = _signOfferCompact(lenderPK, offer);

        vm.prank(activeLoanContract);
        offerContract.createLOANTerms(borrower, abi.encode(offer, offerValues), signature);
    }

    function test_shouldPass_whenValidSignature_whenContractAccount() external {
        vm.etch(lender, bytes("data"));

        vm.mockCall(
            lender,
            abi.encodeWithSignature("isValidSignature(bytes32,bytes)"),
            abi.encode(bytes4(0x1626ba7e))
        );

        vm.prank(activeLoanContract);
        offerContract.createLOANTerms(borrower, abi.encode(offer, offerValues), signature);
    }

    function test_shouldFail_whenOfferIsExpired() external {
        vm.warp(40303);
        offer.expiration = 30303;
        signature = _signOfferCompact(lenderPK, offer);

        vm.expectRevert(abi.encodeWithSelector(OfferExpired.selector));
        vm.prank(activeLoanContract);
        offerContract.createLOANTerms(borrower, abi.encode(offer, offerValues), signature);
    }

    function test_shouldPass_whenOfferIsNotExpired() external {
        vm.warp(40303);
        offer.expiration = 50303;
        signature = _signOfferCompact(lenderPK, offer);

        vm.prank(activeLoanContract);
        offerContract.createLOANTerms(borrower, abi.encode(offer, offerValues), signature);
    }

    function test_shouldFail_whenOfferIsRevoked() external {
        signature = _signOfferCompact(lenderPK, offer);

        vm.mockCall(
            revokedOfferNonce,
            abi.encodeWithSignature("isNonceRevoked(address,uint256,uint256)"),
            abi.encode(true)
        );
        vm.expectCall(
            revokedOfferNonce,
            abi.encodeWithSignature("isNonceRevoked(address,uint256,uint256)", offer.lender, offer.nonceSpace, offer.nonce)
        );

        vm.expectRevert(abi.encodeWithSelector(NonceAlreadyRevoked.selector));
        vm.prank(activeLoanContract);
        offerContract.createLOANTerms(borrower, abi.encode(offer, offerValues), signature);
    }

    function test_shouldFail_whenCallerIsNotAllowedBorrower() external {
        offer.allowedBorrower = address(0x50303);
        signature = _signOfferCompact(lenderPK, offer);

        vm.expectRevert(abi.encodeWithSelector(CallerIsNotStatedBorrower.selector, offer.allowedBorrower));
        vm.prank(activeLoanContract);
        offerContract.createLOANTerms(borrower, abi.encode(offer, offerValues), signature);
    }

    function testFuzz_shouldFail_whenLessThanMinDuration(uint32 duration) external {
        vm.assume(duration < offerContract.MIN_LOAN_DURATION());

        offer.duration = duration;
        signature = _signOfferCompact(lenderPK, offer);

        vm.expectRevert(abi.encodeWithSelector(InvalidDuration.selector));
        vm.prank(activeLoanContract);
        offerContract.createLOANTerms(borrower, abi.encode(offer, offerValues), signature);
    }

    function testFuzz_shouldFail_whenAccruingInterestAPROutOfBounds(uint40 interestAPR) external {
        uint40 maxInterest = offerContract.MAX_ACCRUING_INTEREST_APR();
        interestAPR = uint40(bound(interestAPR, maxInterest + 1, type(uint40).max));

        offer.accruingInterestAPR = interestAPR;
        signature = _signOfferCompact(lenderPK, offer);

        vm.expectRevert(abi.encodeWithSelector(AccruingInterestAPROutOfBounds.selector, interestAPR, maxInterest));
        vm.prank(activeLoanContract);
        offerContract.createLOANTerms(borrower, abi.encode(offer, offerValues), signature);
    }

    function test_shouldNotCallComputerRegistry_whenShouldNotCheckStateFingerprint() external {
        offer.checkCollateralStateFingerprint = false;
        signature = _signOfferCompact(lenderPK, offer);

        vm.expectCall({
            callee: stateFingerprintComputerRegistry,
            data: abi.encodeWithSignature("getStateFingerprintComputer(address)", offer.collateralAddress),
            count: 0
        });

        vm.prank(activeLoanContract);
        offerContract.createLOANTerms(borrower, abi.encode(offer, offerValues), signature);
    }

    function test_shouldFail_whenComputerRegistryReturnsZeroAddress_whenShouldCheckStateFingerprint() external {
        signature = _signOfferCompact(lenderPK, offer);

        vm.mockCall(
            stateFingerprintComputerRegistry,
            abi.encodeWithSignature("getStateFingerprintComputer(address)", offer.collateralAddress),
            abi.encode(address(0))
        );

        vm.expectCall(
            stateFingerprintComputerRegistry,
            abi.encodeWithSignature("getStateFingerprintComputer(address)", offer.collateralAddress)
        );

        vm.expectRevert(abi.encodeWithSelector(MissingStateFingerprintComputer.selector));
        vm.prank(activeLoanContract);
        offerContract.createLOANTerms(borrower, abi.encode(offer, offerValues), signature);
    }

    function testFuzz_shouldFail_whenComputerReturnsDifferentStateFingerprint_whenShouldCheckStateFingerprint(
        bytes32 stateFingerprint
    ) external {
        vm.assume(stateFingerprint != offer.collateralStateFingerprint);

        signature = _signOfferCompact(lenderPK, offer);

        vm.mockCall(
            stateFingerprintComputer,
            abi.encodeWithSignature("getStateFingerprint(uint256)", offerValues.collateralId),
            abi.encode(stateFingerprint)
        );

        vm.expectCall(
            stateFingerprintComputer,
            abi.encodeWithSignature("getStateFingerprint(uint256)", offerValues.collateralId)
        );

        vm.expectRevert(abi.encodeWithSelector(
            InvalidCollateralStateFingerprint.selector, offer.collateralStateFingerprint, stateFingerprint
        ));
        vm.prank(activeLoanContract);
        offerContract.createLOANTerms(borrower, abi.encode(offer, offerValues), signature);
    }

    function test_shouldRevokeOffer_whenIsNotPersistent() external {
        offer.isPersistent = false;
        signature = _signOfferCompact(lenderPK, offer);

        vm.expectCall(
            revokedOfferNonce,
            abi.encodeWithSignature("revokeNonce(address,uint256,uint256)", offer.lender, offer.nonceSpace, offer.nonce)
        );

        vm.prank(activeLoanContract);
        offerContract.createLOANTerms(borrower, abi.encode(offer, offerValues), signature);
    }

    function test_shouldNotRevokeOffer_whenIsPersistent() external {
        offer.isPersistent = true;
        signature = _signOfferCompact(lenderPK, offer);

        vm.expectCall({
            callee: revokedOfferNonce,
            data: abi.encodeWithSignature("revokeNonce(address,uint256,uint256)", offer.lender, offer.nonceSpace, offer.nonce),
            count: 0
        });

        vm.prank(activeLoanContract);
        offerContract.createLOANTerms(borrower, abi.encode(offer, offerValues), signature);
    }

    function test_shouldAcceptAnyCollateralId_whenMerkleRootIsZero() external {
        offerValues.collateralId = 331;
        offer.collateralIdsWhitelistMerkleRoot = bytes32(0);
        signature = _signOfferCompact(lenderPK, offer);

        vm.prank(activeLoanContract);
        offerContract.createLOANTerms(borrower, abi.encode(offer, offerValues), signature);
    }

    function test_shouldPass_whenGivenCollateralIdIsWhitelisted() external {
        bytes32 id1Hash = keccak256(abi.encodePacked(uint256(331)));
        bytes32 id2Hash = keccak256(abi.encodePacked(uint256(133)));
        offer.collateralIdsWhitelistMerkleRoot = keccak256(abi.encodePacked(id1Hash, id2Hash));
        signature = _signOfferCompact(lenderPK, offer);

        offerValues.collateralId = 331;
        offerValues.merkleInclusionProof = new bytes32[](1);
        offerValues.merkleInclusionProof[0] = id2Hash;

        vm.prank(activeLoanContract);
        offerContract.createLOANTerms(borrower, abi.encode(offer, offerValues), signature);
    }

    function test_shouldFail_whenGivenCollateralIdIsNotWhitelisted() external {
        bytes32 id1Hash = keccak256(abi.encodePacked(uint256(331)));
        bytes32 id2Hash = keccak256(abi.encodePacked(uint256(133)));
        offer.collateralIdsWhitelistMerkleRoot = keccak256(abi.encodePacked(id1Hash, id2Hash));
        signature = _signOfferCompact(lenderPK, offer);

        offerValues.collateralId = 333;
        offerValues.merkleInclusionProof = new bytes32[](1);
        offerValues.merkleInclusionProof[0] = id2Hash;

        vm.expectRevert(abi.encodeWithSelector(CollateralIdIsNotWhitelisted.selector));
        vm.prank(activeLoanContract);
        offerContract.createLOANTerms(borrower, abi.encode(offer, offerValues), signature);
    }

    function test_shouldReturnCorrectValues() external {
        uint256 currentTimestamp = 40303;
        vm.warp(currentTimestamp);
        signature = _signOfferCompact(lenderPK, offer);

        vm.prank(activeLoanContract);
        (PWNLOANTerms.Simple memory loanTerms, bytes32 offerHash)
            = offerContract.createLOANTerms(borrower, abi.encode(offer, offerValues), signature);

        assertTrue(loanTerms.lender == offer.lender);
        assertTrue(loanTerms.borrower == borrower);
        assertTrue(loanTerms.defaultTimestamp == currentTimestamp + offer.duration);
        assertTrue(loanTerms.collateral.category == offer.collateralCategory);
        assertTrue(loanTerms.collateral.assetAddress == offer.collateralAddress);
        assertTrue(loanTerms.collateral.id == offerValues.collateralId);
        assertTrue(loanTerms.collateral.amount == offer.collateralAmount);
        assertTrue(loanTerms.asset.category == MultiToken.Category.ERC20);
        assertTrue(loanTerms.asset.assetAddress == offer.loanAssetAddress);
        assertTrue(loanTerms.asset.id == 0);
        assertTrue(loanTerms.asset.amount == offer.loanAmount);
        assertTrue(loanTerms.fixedInterestAmount == offer.fixedInterestAmount);
        assertTrue(loanTerms.accruingInterestAPR == offer.accruingInterestAPR);
        assertTrue(loanTerms.canCreate == true);
        assertTrue(loanTerms.canRefinance == true);
        assertTrue(loanTerms.refinancingLoanId == 0);

        assertTrue(offerHash == _offerHash(offer));
    }

}


/*----------------------------------------------------------*|
|*  # GET OFFER HASH                                        *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanListOffer_GetOfferHash_Test is PWNSimpleLoanListOfferTest {

    function test_shouldReturnOfferHash() external {
        assertEq(_offerHash(offer), offerContract.getOfferHash(offer));
    }

}


/*----------------------------------------------------------*|
|*  # LOAN TERMS FACTORY DATA ENCODING                      *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanListOffer_EncodeLoanTermsFactoryData_Test is PWNSimpleLoanListOfferTest {

    function test_shouldReturnEncodedLoanTermsFactoryData() external {
        assertEq(abi.encode(offer, offerValues), offerContract.encodeLoanTermsFactoryData(offer, offerValues));
    }

}
