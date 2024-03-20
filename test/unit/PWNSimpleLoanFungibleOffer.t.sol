// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import { MultiToken } from "MultiToken/MultiToken.sol";

import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import { PWNHubTags } from "@pwn/hub/PWNHubTags.sol";
import { PWNSimpleLoanFungibleOffer, PWNSimpleLoan, Permit }
    from "@pwn/loan/terms/simple/proposal/offer/PWNSimpleLoanFungibleOffer.sol";
import "@pwn/PWNErrors.sol";


abstract contract PWNSimpleLoanFungibleOfferTest is Test {

    bytes32 internal constant PROPOSALS_MADE_SLOT = bytes32(uint256(0)); // `proposalsMade` mapping position
    bytes32 internal constant CREDIT_USED_SLOT = bytes32(uint256(1)); // `creditUsed` mapping position

    PWNSimpleLoanFungibleOffer offerContract;
    address hub = makeAddr("hub");
    address revokedNonce = makeAddr("revokedNonce");
    address stateFingerprintComputerRegistry = makeAddr("stateFingerprintComputerRegistry");
    address activeLoanContract = makeAddr("activeLoanContract");
    PWNSimpleLoanFungibleOffer.Offer offer;
    PWNSimpleLoanFungibleOffer.OfferValues offerValues;
    address token = makeAddr("token");
    uint256 lenderPK = 73661723;
    address lender = vm.addr(lenderPK);
    address borrower = makeAddr("borrower");
    address stateFingerprintComputer = makeAddr("stateFingerprintComputer");
    uint256 loanId = 421;
    uint256 refinancedLoanId = 123;
    Permit permit;

    event OfferMade(bytes32 indexed proposalHash, address indexed proposer, PWNSimpleLoanFungibleOffer.Offer offer);

    function setUp() virtual public {
        vm.etch(hub, bytes("data"));
        vm.etch(revokedNonce, bytes("data"));
        vm.etch(token, bytes("data"));

        offerContract = new PWNSimpleLoanFungibleOffer(hub, revokedNonce, stateFingerprintComputerRegistry);

        offer = PWNSimpleLoanFungibleOffer.Offer({
            collateralCategory: MultiToken.Category.ERC1155,
            collateralAddress: token,
            collateralId: 0,
            minCollateralAmount: 100,
            checkCollateralStateFingerprint: true,
            collateralStateFingerprint: keccak256("some state fingerprint"),
            creditAddress: token,
            creditPerCollateralUnit: 10 * offerContract.CREDIT_PER_COLLATERAL_UNIT_DENOMINATOR(),
            availableCreditLimit: 0,
            fixedInterestAmount: 1,
            accruingInterestAPR: 0,
            duration: 1000,
            expiration: 60303,
            allowedBorrower: address(0),
            lender: lender,
            refinancingLoanId: 0,
            nonceSpace: 1,
            nonce: uint256(keccak256("nonce_1")),
            loanContract: activeLoanContract
        });

        offerValues = PWNSimpleLoanFungibleOffer.OfferValues({
            collateralAmount: 1000
        });

        vm.mockCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)"),
            abi.encode(true)
        );

        vm.mockCall(address(hub), abi.encodeWithSignature("hasTag(address,bytes32)"), abi.encode(false));
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
            abi.encodeWithSignature("getStateFingerprint(uint256)"),
            abi.encode(offer.collateralStateFingerprint)
        );

        vm.mockCall(
            activeLoanContract, abi.encodeWithSelector(PWNSimpleLoan.createLOAN.selector), abi.encode(loanId)
        );
        vm.mockCall(
            activeLoanContract, abi.encodeWithSelector(PWNSimpleLoan.refinanceLOAN.selector), abi.encode(refinancedLoanId)
        );
    }


    function _offerHash(PWNSimpleLoanFungibleOffer.Offer memory _offer) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            "\x19\x01",
            keccak256(abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("PWNSimpleLoanFungibleOffer"),
                keccak256("1.2"),
                block.chainid,
                address(offerContract)
            )),
            keccak256(abi.encodePacked(
                keccak256("Offer(uint8 collateralCategory,address collateralAddress,uint256 collateralId,uint256 minCollateralAmount,bool checkCollateralStateFingerprint,bytes32 collateralStateFingerprint,address creditAddress,uint256 creditPerCollateralUnit,uint256 availableCreditLimit,uint256 fixedInterestAmount,uint40 accruingInterestAPR,uint32 duration,uint40 expiration,address allowedBorrower,address lender,uint256 refinancingLoanId,uint256 nonceSpace,uint256 nonce,address loanContract)"),
                abi.encode(_offer)
            ))
        ));
    }

    function _signOffer(
        uint256 pk, PWNSimpleLoanFungibleOffer.Offer memory _offer
    ) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _offerHash(_offer));
        return abi.encodePacked(r, s, v);
    }

    function _signOfferCompact(
        uint256 pk, PWNSimpleLoanFungibleOffer.Offer memory _offer
    ) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _offerHash(_offer));
        return abi.encodePacked(r, bytes32(uint256(v) - 27) << 255 | s);
    }

    function _creditAmount(uint256 collateralAmount, uint256 creditPerCollateralUnit) internal view returns (uint256) {
        return Math.mulDiv(collateralAmount, creditPerCollateralUnit, offerContract.CREDIT_PER_COLLATERAL_UNIT_DENOMINATOR());
    }

}


/*----------------------------------------------------------*|
|*  # CREDIT USED                                           *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanFungibleOffer_CreditUsed_Test is PWNSimpleLoanFungibleOfferTest {

    function testFuzz_shouldReturnUsedCredit(uint256 used) external {
        vm.store(address(offerContract), keccak256(abi.encode(_offerHash(offer), CREDIT_USED_SLOT)), bytes32(used));

        assertEq(offerContract.creditUsed(_offerHash(offer)), used);
    }

}


/*----------------------------------------------------------*|
|*  # GET OFFER HASH                                        *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanFungibleOffer_GetOfferHash_Test is PWNSimpleLoanFungibleOfferTest {

    function test_shouldReturnOfferHash() external {
        assertEq(_offerHash(offer), offerContract.getOfferHash(offer));
    }

}


/*----------------------------------------------------------*|
|*  # MAKE OFFER                                            *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanFungibleOffer_MakeOffer_Test is PWNSimpleLoanFungibleOfferTest {

    function testFuzz_shouldFail_whenCallerIsNotLender(address caller) external {
        vm.assume(caller != offer.lender);

        vm.expectRevert(abi.encodeWithSelector(CallerIsNotStatedProposer.selector, lender));
        vm.prank(caller);
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

        assertTrue(offerContract.proposalsMade(_offerHash(offer)));
    }

    function test_shouldReturnOfferHash() external {
        vm.prank(offer.lender);
        assertEq(offerContract.makeOffer(offer), _offerHash(offer));
    }

}


/*----------------------------------------------------------*|
|*  # REVOKE NONCE                                          *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanFungibleOffer_RevokeNonce_Test is PWNSimpleLoanFungibleOfferTest {

    function testFuzz_shouldCallRevokeNonce(address caller, uint256 nonceSpace, uint256 nonce) external {
        vm.expectCall(
            revokedNonce,
            abi.encodeWithSignature("revokeNonce(address,uint256,uint256)", caller, nonceSpace, nonce)
        );

        vm.prank(caller);
        offerContract.revokeNonce(nonceSpace, nonce);
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT OFFER                                          *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanFungibleOffer_AcceptOffer_Test is PWNSimpleLoanFungibleOfferTest {

    function testFuzz_shouldFail_whenRefinancingLoanIdNotZero(uint256 refinancingLoanId) external {
        vm.assume(refinancingLoanId != 0);
        offer.refinancingLoanId = refinancingLoanId;

        vm.expectRevert(abi.encodeWithSelector(InvalidRefinancingLoanId.selector, refinancingLoanId));
        offerContract.acceptOffer(offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function testFuzz_shouldFail_whenLoanContractNotTagged_ACTIVE_LOAN(address loanContract) external {
        vm.assume(loanContract != activeLoanContract);
        offer.loanContract = loanContract;

        vm.expectRevert(abi.encodeWithSelector(AddressMissingHubTag.selector, loanContract, PWNHubTags.ACTIVE_LOAN));
        offerContract.acceptOffer(offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function test_shouldFail_whenZeroMinCollateralAmount() external {
        offer.minCollateralAmount = 0;

        vm.expectRevert(abi.encodeWithSelector(MinCollateralAmountNotSet.selector));
        offerContract.acceptOffer(offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function testFuzz_shouldFail_whenCollateralAmountLessThanMinCollateralAmount(uint256 collateralAmount) external {
        collateralAmount = bound(collateralAmount, 0, offer.minCollateralAmount - 1);
        offerValues.collateralAmount = collateralAmount;

        vm.expectRevert(abi.encodeWithSelector(
            InsufficientCollateralAmount.selector, collateralAmount, offer.minCollateralAmount
        ));
        offerContract.acceptOffer(offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function test_shouldNotCallComputerRegistry_whenShouldNotCheckStateFingerprint() external {
        offer.checkCollateralStateFingerprint = false;

        vm.expectCall({
            callee: stateFingerprintComputerRegistry,
            data: abi.encodeWithSignature("getStateFingerprintComputer(address)", offer.collateralAddress),
            count: 0
        });

        offerContract.acceptOffer(offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function test_shouldFail_whenComputerRegistryReturnsZeroAddress_whenShouldCheckStateFingerprint() external {
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
        offerContract.acceptOffer(offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function testFuzz_shouldFail_whenComputerReturnsDifferentStateFingerprint_whenShouldCheckStateFingerprint(
        bytes32 stateFingerprint
    ) external {
        vm.assume(stateFingerprint != offer.collateralStateFingerprint);

        vm.mockCall(
            stateFingerprintComputer,
            abi.encodeWithSignature("getStateFingerprint(uint256)", offer.collateralId),
            abi.encode(stateFingerprint)
        );

        vm.expectCall(
            stateFingerprintComputer,
            abi.encodeWithSignature("getStateFingerprint(uint256)", offer.collateralId)
        );

        vm.expectRevert(abi.encodeWithSelector(
            InvalidCollateralStateFingerprint.selector, stateFingerprint, offer.collateralStateFingerprint
        ));
        offerContract.acceptOffer(offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function test_shouldFail_whenInvalidSignature_whenEOA() external {
        vm.expectRevert(abi.encodeWithSelector(InvalidSignature.selector, offer.lender, _offerHash(offer)));
        offerContract.acceptOffer(offer, offerValues, _signOffer(1, offer), permit, "");
    }

    function test_shouldFail_whenInvalidSignature_whenContractAccount() external {
        vm.etch(lender, bytes("data"));

        vm.expectRevert(abi.encodeWithSelector(InvalidSignature.selector, offer.lender, _offerHash(offer)));
        offerContract.acceptOffer(offer, offerValues, "", permit, "");
    }

    function test_shouldPass_whenOfferHasBeenMadeOnchain() external {
        vm.store(
            address(offerContract),
            keccak256(abi.encode(_offerHash(offer), PROPOSALS_MADE_SLOT)),
            bytes32(uint256(1))
        );

        offerContract.acceptOffer(offer, offerValues, "", permit, "");
    }

    function test_shouldPass_withValidSignature_whenEOA_whenStandardSignature() external {
        offerContract.acceptOffer(offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function test_shouldPass_withValidSignature_whenEOA_whenCompactEIP2098Signature() external {
        offerContract.acceptOffer(offer, offerValues, _signOfferCompact(lenderPK, offer), permit, "");
    }

    function test_shouldPass_whenValidSignature_whenContractAccount() external {
        vm.etch(lender, bytes("data"));

        vm.mockCall(
            lender,
            abi.encodeWithSignature("isValidSignature(bytes32,bytes)"),
            abi.encode(bytes4(0x1626ba7e))
        );

        offerContract.acceptOffer(offer, offerValues, "", permit, "");
    }

    function testFuzz_shouldFail_whenOfferIsExpired(uint256 timestamp) external {
        timestamp = bound(timestamp, offer.expiration, type(uint256).max);
        vm.warp(timestamp);

        vm.expectRevert(abi.encodeWithSelector(Expired.selector, timestamp, offer.expiration));
        offerContract.acceptOffer(offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function test_shouldFail_whenOfferNonceNotUsable() external {
        vm.mockCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)"),
            abi.encode(false)
        );
        vm.expectCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)", offer.lender, offer.nonceSpace, offer.nonce)
        );

        vm.expectRevert(abi.encodeWithSelector(
            NonceNotUsable.selector, offer.lender, offer.nonceSpace, offer.nonce
        ));
        offerContract.acceptOffer(offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function testFuzz_shouldFail_whenCallerIsNotAllowedBorrower(address caller) external {
        address allowedBorrower = makeAddr("allowedBorrower");
        vm.assume(caller != allowedBorrower);
        offer.allowedBorrower = allowedBorrower;

        vm.expectRevert(abi.encodeWithSelector(CallerNotAllowedAcceptor.selector, caller, offer.allowedBorrower));
        vm.prank(caller);
        offerContract.acceptOffer(offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function testFuzz_shouldFail_whenLessThanMinDuration(uint256 duration) external {
        vm.assume(duration < offerContract.MIN_LOAN_DURATION());
        duration = bound(duration, 0, offerContract.MIN_LOAN_DURATION() - 1);
        offer.duration = uint32(duration);

        vm.expectRevert(abi.encodeWithSelector(InvalidDuration.selector, duration, offerContract.MIN_LOAN_DURATION()));
        offerContract.acceptOffer(offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function testFuzz_shouldFail_whenAccruingInterestAPROutOfBounds(uint256 interestAPR) external {
        uint256 maxInterest = offerContract.MAX_ACCRUING_INTEREST_APR();
        interestAPR = bound(interestAPR, maxInterest + 1, type(uint40).max);
        offer.accruingInterestAPR = uint40(interestAPR);

        vm.expectRevert(abi.encodeWithSelector(AccruingInterestAPROutOfBounds.selector, interestAPR, maxInterest));
        offerContract.acceptOffer(offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function test_shouldRevokeOffer_whenAvailableCreditLimitEqualToZero() external {
        offer.availableCreditLimit = 0;

        vm.expectCall(
            revokedNonce,
            abi.encodeWithSignature(
                "revokeNonce(address,uint256,uint256)", offer.lender, offer.nonceSpace, offer.nonce
            )
        );

        offerContract.acceptOffer(offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function testFuzz_shouldFail_whenUsedCreditExceedsAvailableCreditLimit(uint256 used, uint256 limit) external {
        uint256 creditAmount = _creditAmount(offerValues.collateralAmount, offer.creditPerCollateralUnit);
        used = bound(used, 1, type(uint256).max - creditAmount);
        limit = bound(limit, used, used + creditAmount - 1);
        offer.availableCreditLimit = limit;

        vm.store(address(offerContract), keccak256(abi.encode(_offerHash(offer), CREDIT_USED_SLOT)), bytes32(used));

        vm.expectRevert(abi.encodeWithSelector(AvailableCreditLimitExceeded.selector, used + creditAmount, limit));
        offerContract.acceptOffer(offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function testFuzz_shouldIncreaseUsedCredit_whenUsedCreditNotExceedsAvailableCreditLimit(uint256 used, uint256 limit) external {
        uint256 creditAmount = _creditAmount(offerValues.collateralAmount, offer.creditPerCollateralUnit);
        used = bound(used, 1, type(uint256).max - creditAmount);
        limit = bound(limit, used + creditAmount, type(uint256).max);
        offer.availableCreditLimit = limit;

        vm.store(address(offerContract), keccak256(abi.encode(_offerHash(offer), CREDIT_USED_SLOT)), bytes32(used));

        offerContract.acceptOffer(offer, offerValues, _signOffer(lenderPK, offer), permit, "");

        assertEq(offerContract.creditUsed(_offerHash(offer)), used + creditAmount);
    }

    function testFuzz_shouldFail_whenPermitOwnerNotCaller(address owner) external {
        vm.assume(owner != borrower);

        permit.owner = owner;
        permit.asset = offer.creditAddress;

        vm.expectRevert(abi.encodeWithSelector(InvalidPermitOwner.selector, owner, borrower));
        vm.prank(borrower);
        offerContract.acceptOffer(offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function testFuzz_shouldFail_whenPermitAssetNotCreditAsset(address asset) external {
        vm.assume(asset != offer.creditAddress && asset != address(0));

        permit.owner = borrower;
        permit.asset = asset;

        vm.expectRevert(abi.encodeWithSelector(InvalidPermitAsset.selector, asset, token));
        vm.prank(borrower);
        offerContract.acceptOffer(offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function testFuzz_shouldCallLoanContractWithLoanTerms(
        uint256 collateralAmount, uint256 creditPerCollateralUnit
    ) external {
        offerValues.collateralAmount = bound(collateralAmount, offer.minCollateralAmount, 1e40);
        offer.creditPerCollateralUnit = bound(creditPerCollateralUnit, 0, 1e40);
        uint256 creditAmount = _creditAmount(offerValues.collateralAmount, offer.creditPerCollateralUnit);

        permit = Permit({
            asset: token,
            owner: borrower,
            amount: 100,
            deadline: 1000,
            v: 27,
            r: bytes32(uint256(1)),
            s: bytes32(uint256(2))
        });
        bytes memory extra = "lil extra";

        PWNSimpleLoan.Terms memory loanTerms = PWNSimpleLoan.Terms({
            lender: offer.lender,
            borrower: borrower,
            duration: offer.duration,
            collateral: MultiToken.Asset({
                category: offer.collateralCategory,
                assetAddress: offer.collateralAddress,
                id: offer.collateralId,
                amount: offerValues.collateralAmount
            }),
            credit: MultiToken.Asset({
                category: MultiToken.Category.ERC20,
                assetAddress: offer.creditAddress,
                id: 0,
                amount: creditAmount
            }),
            fixedInterestAmount: offer.fixedInterestAmount,
            accruingInterestAPR: offer.accruingInterestAPR
        });

        vm.expectCall(
            activeLoanContract,
            abi.encodeWithSelector(
                PWNSimpleLoan.createLOAN.selector,
                _offerHash(offer), loanTerms, permit, extra
            )
        );

        vm.prank(borrower);
        offerContract.acceptOffer(offer, offerValues, _signOffer(lenderPK, offer), permit, extra);
    }

    function test_shouldReturnNewLoanId() external {
        assertEq(
            offerContract.acceptOffer(offer, offerValues, _signOffer(lenderPK, offer), permit, ""),
            loanId
        );
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT OFFER AND REVOKE CALLERS NONCE                 *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanFungibleOffer_AcceptOfferAndRevokeCallersNonce_Test is PWNSimpleLoanFungibleOfferTest {

    function testFuzz_shouldFail_whenNonceIsNotUsable(address caller, uint256 nonceSpace, uint256 nonce) external {
        vm.mockCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)", caller, nonceSpace, nonce),
            abi.encode(false)
        );

        vm.expectRevert(abi.encodeWithSelector(NonceNotUsable.selector, caller, nonceSpace, nonce));
        vm.prank(caller);
        offerContract.acceptOffer({
            offer: offer,
            offerValues: offerValues,
            signature: _signOffer(lenderPK, offer),
            permit: permit,
            extra: "",
            callersNonceSpace: nonceSpace,
            callersNonceToRevoke: nonce
        });
    }

    function testFuzz_shouldRevokeCallersNonce(address caller, uint256 nonceSpace, uint256 nonce) external {
        vm.expectCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)", caller, nonceSpace, nonce)
        );

        vm.prank(caller);
        offerContract.acceptOffer({
            offer: offer,
            offerValues: offerValues,
            signature: _signOffer(lenderPK, offer),
            permit: permit,
            extra: "",
            callersNonceSpace: nonceSpace,
            callersNonceToRevoke: nonce
        });
    }

    // function is calling `acceptOffer`, no need to test it again
    function test_shouldCallLoanContract() external {
        uint256 newLoanId = offerContract.acceptOffer({
            offer: offer,
            offerValues: offerValues,
            signature: _signOffer(lenderPK, offer),
            permit: permit,
            extra: "",
            callersNonceSpace: 1,
            callersNonceToRevoke: 2
        });

        assertEq(newLoanId, loanId);
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT REFINANCE OFFER                                *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanFungibleOffer_AcceptRefinanceOffer_Test is PWNSimpleLoanFungibleOfferTest {

    function testFuzz_shouldFail_whenRefinancingLoanIdIsNotEqualToLoanId_whenRefinanceingLoanIdNotZero(
        uint256 _loanId, uint256 _refinancingLoanId
    ) external {
        vm.assume(_refinancingLoanId != 0);
        vm.assume(_loanId != _refinancingLoanId);
        offer.refinancingLoanId = _refinancingLoanId;

        vm.expectRevert(abi.encodeWithSelector(InvalidRefinancingLoanId.selector, offer.refinancingLoanId));
        offerContract.acceptRefinanceOffer(_loanId, offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function testFuzz_shouldFail_whenLoanContractNotTagged_ACTIVE_LOAN(address loanContract) external {
        vm.assume(loanContract != activeLoanContract);
        offer.loanContract = loanContract;

        vm.expectRevert(abi.encodeWithSelector(AddressMissingHubTag.selector, loanContract, PWNHubTags.ACTIVE_LOAN));
        offerContract.acceptRefinanceOffer(loanId, offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function test_shouldFail_whenZeroMinCollateralAmount() external {
        offer.minCollateralAmount = 0;

        vm.expectRevert(abi.encodeWithSelector(MinCollateralAmountNotSet.selector));
        offerContract.acceptRefinanceOffer(loanId, offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function testFuzz_shouldFail_whenCollateralAmountLessThanMinCollateralAmount(uint256 collateralAmount) external {
        collateralAmount = bound(collateralAmount, 0, offer.minCollateralAmount - 1);
        offerValues.collateralAmount = collateralAmount;

        vm.expectRevert(abi.encodeWithSelector(
            InsufficientCollateralAmount.selector, collateralAmount, offer.minCollateralAmount
        ));
        offerContract.acceptRefinanceOffer(loanId, offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function test_shouldNotCallComputerRegistry_whenShouldNotCheckStateFingerprint() external {
        offer.checkCollateralStateFingerprint = false;

        vm.expectCall({
            callee: stateFingerprintComputerRegistry,
            data: abi.encodeWithSignature("getStateFingerprintComputer(address)", offer.collateralAddress),
            count: 0
        });

        offerContract.acceptRefinanceOffer(loanId, offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function test_shouldFail_whenComputerRegistryReturnsZeroAddress_whenShouldCheckStateFingerprint() external {
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
        offerContract.acceptRefinanceOffer(loanId, offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function testFuzz_shouldFail_whenComputerReturnsDifferentStateFingerprint_whenShouldCheckStateFingerprint(
        bytes32 stateFingerprint
    ) external {
        vm.assume(stateFingerprint != offer.collateralStateFingerprint);

        vm.mockCall(
            stateFingerprintComputer,
            abi.encodeWithSignature("getStateFingerprint(uint256)", offer.collateralId),
            abi.encode(stateFingerprint)
        );

        vm.expectCall(
            stateFingerprintComputer,
            abi.encodeWithSignature("getStateFingerprint(uint256)", offer.collateralId)
        );

        vm.expectRevert(abi.encodeWithSelector(
            InvalidCollateralStateFingerprint.selector, stateFingerprint, offer.collateralStateFingerprint
        ));
        offerContract.acceptRefinanceOffer(loanId, offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function test_shouldFail_whenInvalidSignature_whenEOA() external {
        vm.expectRevert(abi.encodeWithSelector(InvalidSignature.selector, offer.lender, _offerHash(offer)));
        offerContract.acceptRefinanceOffer(loanId, offer, offerValues, _signOffer(1, offer), permit, "");
    }

    function test_shouldFail_whenInvalidSignature_whenContractAccount() external {
        vm.etch(lender, bytes("data"));

        vm.expectRevert(abi.encodeWithSelector(InvalidSignature.selector, offer.lender, _offerHash(offer)));
        offerContract.acceptRefinanceOffer(loanId, offer, offerValues, "", permit, "");
    }

    function test_shouldPass_whenOfferHasBeenMadeOnchain() external {
        vm.store(
            address(offerContract),
            keccak256(abi.encode(_offerHash(offer), PROPOSALS_MADE_SLOT)),
            bytes32(uint256(1))
        );

        offerContract.acceptRefinanceOffer(loanId, offer, offerValues, "", permit, "");
    }

    function test_shouldPass_withValidSignature_whenEOA_whenStandardSignature() external {
        offerContract.acceptRefinanceOffer(loanId, offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function test_shouldPass_withValidSignature_whenEOA_whenCompactEIP2098Signature() external {
        offerContract.acceptRefinanceOffer(loanId, offer, offerValues, _signOfferCompact(lenderPK, offer), permit, "");
    }

    function test_shouldPass_whenValidSignature_whenContractAccount() external {
        vm.etch(lender, bytes("data"));

        vm.mockCall(
            lender,
            abi.encodeWithSignature("isValidSignature(bytes32,bytes)"),
            abi.encode(bytes4(0x1626ba7e))
        );

        offerContract.acceptRefinanceOffer(loanId, offer, offerValues, "", permit, "");
    }

    function testFuzz_shouldFail_whenOfferIsExpired(uint256 timestamp) external {
        timestamp = bound(timestamp, offer.expiration, type(uint256).max);
        vm.warp(timestamp);

        vm.expectRevert(abi.encodeWithSelector(Expired.selector, timestamp, offer.expiration));
        offerContract.acceptRefinanceOffer(loanId, offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function test_shouldFail_whenOfferNonceNotUsable() external {
        vm.mockCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)"),
            abi.encode(false)
        );
        vm.expectCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)", offer.lender, offer.nonceSpace, offer.nonce)
        );

        vm.expectRevert(abi.encodeWithSelector(
            NonceNotUsable.selector, offer.lender, offer.nonceSpace, offer.nonce
        ));
        offerContract.acceptRefinanceOffer(loanId, offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function testFuzz_shouldFail_whenCallerIsNotAllowedBorrower(address caller) external {
        address allowedBorrower = makeAddr("allowedBorrower");
        vm.assume(caller != allowedBorrower);
        offer.allowedBorrower = allowedBorrower;

        vm.expectRevert(abi.encodeWithSelector(CallerNotAllowedAcceptor.selector, caller, offer.allowedBorrower));
        vm.prank(caller);
        offerContract.acceptRefinanceOffer(loanId, offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function testFuzz_shouldFail_whenLessThanMinDuration(uint256 duration) external {
        vm.assume(duration < offerContract.MIN_LOAN_DURATION());
        duration = bound(duration, 0, offerContract.MIN_LOAN_DURATION() - 1);
        offer.duration = uint32(duration);

        vm.expectRevert(abi.encodeWithSelector(InvalidDuration.selector, duration, offerContract.MIN_LOAN_DURATION()));
        offerContract.acceptRefinanceOffer(loanId, offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function testFuzz_shouldFail_whenAccruingInterestAPROutOfBounds(uint256 interestAPR) external {
        uint256 maxInterest = offerContract.MAX_ACCRUING_INTEREST_APR();
        interestAPR = bound(interestAPR, maxInterest + 1, type(uint40).max);
        offer.accruingInterestAPR = uint40(interestAPR);

        vm.expectRevert(abi.encodeWithSelector(AccruingInterestAPROutOfBounds.selector, interestAPR, maxInterest));
        offerContract.acceptRefinanceOffer(loanId, offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function test_shouldRevokeOffer_whenAvailableCreditLimitEqualToZero() external {
        offer.availableCreditLimit = 0;

        vm.expectCall(
            revokedNonce,
            abi.encodeWithSignature(
                "revokeNonce(address,uint256,uint256)", offer.lender, offer.nonceSpace, offer.nonce
            )
        );

        offerContract.acceptRefinanceOffer(loanId, offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function testFuzz_shouldFail_whenUsedCreditExceedsAvailableCreditLimit(uint256 used, uint256 limit) external {
        uint256 creditAmount = _creditAmount(offerValues.collateralAmount, offer.creditPerCollateralUnit);
        used = bound(used, 1, type(uint256).max - creditAmount);
        limit = bound(limit, used, used + creditAmount - 1);
        offer.availableCreditLimit = limit;

        vm.store(address(offerContract), keccak256(abi.encode(_offerHash(offer), CREDIT_USED_SLOT)), bytes32(used));

        vm.expectRevert(abi.encodeWithSelector(AvailableCreditLimitExceeded.selector, used + creditAmount, limit));
        offerContract.acceptRefinanceOffer(loanId, offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function testFuzz_shouldIncreaseUsedCredit_whenUsedCreditNotExceedsAvailableCreditLimit(uint256 used, uint256 limit) external {
        uint256 creditAmount = _creditAmount(offerValues.collateralAmount, offer.creditPerCollateralUnit);
        used = bound(used, 1, type(uint256).max - creditAmount);
        limit = bound(limit, used + creditAmount, type(uint256).max);
        offer.availableCreditLimit = limit;

        vm.store(address(offerContract), keccak256(abi.encode(_offerHash(offer), CREDIT_USED_SLOT)), bytes32(used));

        offerContract.acceptRefinanceOffer(loanId, offer, offerValues, _signOffer(lenderPK, offer), permit, "");

        assertEq(offerContract.creditUsed(_offerHash(offer)), used + creditAmount);
    }

    function testFuzz_shouldFail_whenPermitOwnerNotCaller(address owner) external {
        vm.assume(owner != borrower);

        permit.owner = owner;
        permit.asset = offer.creditAddress;

        vm.expectRevert(abi.encodeWithSelector(InvalidPermitOwner.selector, owner, borrower));
        vm.prank(borrower);
        offerContract.acceptRefinanceOffer(loanId, offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function testFuzz_shouldFail_whenPermitAssetNotCreditAsset(address asset) external {
        vm.assume(asset != offer.creditAddress && asset != address(0));

        permit.owner = borrower;
        permit.asset = asset;

        vm.expectRevert(abi.encodeWithSelector(InvalidPermitAsset.selector, asset, token));
        vm.prank(borrower);
        offerContract.acceptRefinanceOffer(loanId, offer, offerValues, _signOffer(lenderPK, offer), permit, "");
    }

    function testFuzz_shouldCallLoanContractWithLoanTerms(
        uint256 collateralAmount, uint256 creditPerCollateralUnit
    ) external {
        offerValues.collateralAmount = bound(collateralAmount, offer.minCollateralAmount, 1e40);
        offer.creditPerCollateralUnit = bound(creditPerCollateralUnit, 0, 1e40);
        uint256 creditAmount = _creditAmount(offerValues.collateralAmount, offer.creditPerCollateralUnit);

        permit = Permit({
            asset: token,
            owner: borrower,
            amount: 100,
            deadline: 1000,
            v: 27,
            r: bytes32(uint256(1)),
            s: bytes32(uint256(2))
        });
        bytes memory extra = "lil extra";

        PWNSimpleLoan.Terms memory loanTerms = PWNSimpleLoan.Terms({
            lender: offer.lender,
            borrower: borrower,
            duration: offer.duration,
            collateral: MultiToken.Asset({
                category: offer.collateralCategory,
                assetAddress: offer.collateralAddress,
                id: offer.collateralId,
                amount: offerValues.collateralAmount
            }),
            credit: MultiToken.Asset({
                category: MultiToken.Category.ERC20,
                assetAddress: offer.creditAddress,
                id: 0,
                amount: creditAmount
            }),
            fixedInterestAmount: offer.fixedInterestAmount,
            accruingInterestAPR: offer.accruingInterestAPR
        });

        vm.expectCall(
            activeLoanContract,
            abi.encodeWithSelector(
                PWNSimpleLoan.refinanceLOAN.selector,
                loanId, _offerHash(offer), loanTerms, permit, extra
            )
        );

        vm.prank(borrower);
        offerContract.acceptRefinanceOffer(
            loanId, offer, offerValues, _signOffer(lenderPK, offer), permit, extra
        );
    }

    function test_shouldReturnRefinancedLoanId() external {
        assertEq(
            offerContract.acceptRefinanceOffer(loanId, offer, offerValues, _signOffer(lenderPK, offer), permit, ""),
            refinancedLoanId
        );
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT REFINANCE OFFER AND REVOKE CALLERS NONCE       *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanFungibleOffer_AcceptRefinanceOfferAndRevokeCallersNonce_Test is PWNSimpleLoanFungibleOfferTest {

    function testFuzz_shouldFail_whenNonceIsNotUsable(address caller, uint256 nonceSpace, uint256 nonce) external {
        vm.mockCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)", caller, nonceSpace, nonce),
            abi.encode(false)
        );

        vm.expectRevert(abi.encodeWithSelector(NonceNotUsable.selector, caller, nonceSpace, nonce));
        vm.prank(caller);
        offerContract.acceptRefinanceOffer({
            loanId: loanId,
            offer: offer,
            offerValues: offerValues,
            signature: _signOffer(lenderPK, offer),
            permit: permit,
            extra: "",
            callersNonceSpace: nonceSpace,
            callersNonceToRevoke: nonce
        });
    }

    function testFuzz_shouldRevokeCallersNonce(address caller, uint256 nonceSpace, uint256 nonce) external {
        vm.expectCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)", caller, nonceSpace, nonce)
        );

        vm.prank(caller);
        offerContract.acceptRefinanceOffer({
            loanId: loanId,
            offer: offer,
            offerValues: offerValues,
            signature: _signOffer(lenderPK, offer),
            permit: permit,
            extra: "",
            callersNonceSpace: nonceSpace,
            callersNonceToRevoke: nonce
        });
    }

    // function is calling `acceptRefinanceOffer`, no need to test it again
    function test_shouldCallLoanContract() external {
        uint256 newLoanId = offerContract.acceptRefinanceOffer({
            loanId: loanId,
            offer: offer,
            offerValues: offerValues,
            signature: _signOffer(lenderPK, offer),
            permit: permit,
            extra: "",
            callersNonceSpace: 1,
            callersNonceToRevoke: 2
        });

        assertEq(newLoanId, refinancedLoanId);
    }

}
