// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import { PWNSimpleLoan } from "@pwn/loan/terms/simple/loan/PWNSimpleLoan.sol";
import { PWNSimpleLoanProposal } from "@pwn/loan/terms/simple/proposal/PWNSimpleLoanProposal.sol";
import { Permit } from "@pwn/loan/vault/Permit.sol";
import "@pwn/PWNErrors.sol";

/**
 * @title PWN Simple Loan Fungible Offer
 * @notice Contract for creating and accepting fungible loan offers.
 *         Offers are fungible, which means that they are not tied to a specific collateral or credit amount.
 *         The amount of collateral and credit is specified during the offer acceptance.
 */
contract PWNSimpleLoanFungibleOffer is PWNSimpleLoanProposal {

    string public constant VERSION = "1.2";

    /**
     * @notice Credit per collateral unit denominator. It is used to calculate credit amount from collateral amount.
     */
    uint256 public constant CREDIT_PER_COLLATERAL_UNIT_DENOMINATOR = 1e38;

    /**
     * @dev EIP-712 simple offer struct type hash.
     */
    bytes32 public constant OFFER_TYPEHASH = keccak256(
        "Offer(uint8 collateralCategory,address collateralAddress,uint256 collateralId,uint256 minCollateralAmount,bool checkCollateralStateFingerprint,bytes32 collateralStateFingerprint,address creditAddress,uint256 creditPerCollateralUnit,uint256 availableCreditLimit,uint256 fixedInterestAmount,uint40 accruingInterestAPR,uint32 duration,uint40 expiration,address allowedBorrower,address lender,uint256 refinancingLoanId,uint256 nonceSpace,uint256 nonce,address loanContract)"
    );

    /**
     * @notice Construct defining a fungible offer.
     * @param collateralCategory Category of an asset used as a collateral (0 == ERC20, 2 == ERC1155).
     * @param collateralAddress Address of an asset used as a collateral.
     * @param collateralId Token id of an asset used as a collateral, in case of ERC20 should be 0.
     * @param minCollateralAmount Minimal amount of tokens used as a collateral.
     * @param checkCollateralStateFingerprint If true, collateral state fingerprint will be checked on loan terms creation.
     * @param collateralStateFingerprint Fingerprint of a collateral state. It is used to check if a collateral is in a valid state.
     * @param creditAddress Address of an asset which is lender to a borrower.
     * @param creditPerCollateralUnit Amount of tokens which are offered per collateral unit with 38 decimals.
     * @param availableCreditLimit Available credit limit for the offer. It is the maximum amount of tokens which can be borrowed using the offer.
     * @param fixedInterestAmount Fixed interest amount in credit tokens. It is the minimum amount of interest which has to be paid by a borrower.
     * @param accruingInterestAPR Accruing interest APR.
     * @param duration Loan duration in seconds.
     * @param expiration Offer expiration timestamp in seconds.
     * @param allowedBorrower Address of an allowed borrower. Only this address can accept an offer. If the address is zero address, anybody with a collateral can accept the offer.
     * @param lender Address of a lender. This address has to sign an offer to be valid.
     * @param refinancingLoanId Id of a loan which is refinanced by this offer. If the id is 0, the offer can refinance any loan.
     * @param nonceSpace Nonce space of an offer nonce. All nonces in the same space can be revoked at once.
     * @param nonce Additional value to enable identical offers in time. Without it, it would be impossible to make again offer, which was once revoked.
     *              Can be used to create a group of offers, where accepting one offer will make other offers in the group revoked.
     * @param loanContract Address of a loan contract that will create a loan from the offer.
     */
    struct Offer {
        MultiToken.Category collateralCategory;
        address collateralAddress;
        uint256 collateralId;
        uint256 minCollateralAmount;
        bool checkCollateralStateFingerprint;
        bytes32 collateralStateFingerprint;
        address creditAddress;
        uint256 creditPerCollateralUnit;
        uint256 availableCreditLimit;
        uint256 fixedInterestAmount;
        uint40 accruingInterestAPR;
        uint32 duration;
        uint40 expiration;
        address allowedBorrower;
        address lender;
        uint256 refinancingLoanId;
        uint256 nonceSpace;
        uint256 nonce;
        address loanContract;
    }

    /**
     * @notice Construct defining an Offer concrete values
     * @param collateralAmount Amount of collateral to be used in the loan.
     */
    struct OfferValues {
        uint256 collateralAmount;
    }

    /**
     * @dev Emitted when a proposal is made via an on-chain transaction.
     */
    event OfferMade(bytes32 indexed proposalHash, address indexed proposer, Offer offer);

    constructor(
        address _hub,
        address _revokedNonce,
        address _stateFingerprintComputerRegistry
    ) PWNSimpleLoanProposal(
        _hub, _revokedNonce, _stateFingerprintComputerRegistry, "PWNSimpleLoanFungibleOffer", VERSION
    ) {}

    /**
     * @notice Get an offer hash according to EIP-712
     * @param offer Offer struct to be hashed.
     * @return Offer struct hash.
     */
    function getOfferHash(Offer calldata offer) public view returns (bytes32) {
        return _getProposalHash(OFFER_TYPEHASH, abi.encode(offer));
    }

    /**
     * @notice Make an on-chain offer.
     * @dev Function will mark an offer hash as proposed.
     * @param offer Offer struct containing all needed offer data.
     * @return proposalHash Offer hash.
     */
    function makeOffer(Offer calldata offer) external returns (bytes32 proposalHash) {
        proposalHash = getOfferHash(offer);
        _makeProposal(proposalHash, offer.lender);
        emit OfferMade(proposalHash, offer.lender, offer);
    }

    /**
     * @notice Accept an offer.
     * @param offer Offer struct containing all offer data.
     * @param offerValues OfferValues struct specifying all flexible offer values.
     * @param signature Lender signature of an offer.
     * @param permit Callers permit data.
     * @param extra Auxiliary data that are emitted in the loan creation event. They are not used in the contract logic.
     * @return loanId Id of a created loan.
     */
    function acceptOffer(
        Offer calldata offer,
        OfferValues calldata offerValues,
        bytes calldata signature,
        Permit calldata permit,
        bytes calldata extra
    ) public returns (uint256 loanId) {
        // Check if the offer is refinancing offer
        if (offer.refinancingLoanId != 0) {
            revert InvalidRefinancingLoanId({ refinancingLoanId: offer.refinancingLoanId });
        }

        // Check permit
        _checkPermit(msg.sender, offer.creditAddress, permit);

        // Accept offer
        (bytes32 offerHash, PWNSimpleLoan.Terms memory loanTerms) = _acceptOffer(offer, offerValues, signature);

        // Create loan
        return PWNSimpleLoan(offer.loanContract).createLOAN({
            proposalHash: offerHash,
            loanTerms: loanTerms,
            permit: permit,
            extra: extra
        });
    }

    /**
     * @notice Accept a refinancing offer.
     * @param loanId Id of a loan to be refinanced.
     * @param offer Offer struct containing all offer data.
     * @param offerValues OfferValues struct specifying all flexible offer values.
     * @param signature Lender signature of an offer.
     * @param permit Callers permit data.
     * @param extra Auxiliary data that are emitted in the loan creation event. They are not used in the contract logic.
     * @return refinancedLoanId Id of a created refinanced loan.
     */
    function acceptRefinanceOffer(
        uint256 loanId,
        Offer calldata offer,
        OfferValues calldata offerValues,
        bytes calldata signature,
        Permit calldata permit,
        bytes calldata extra
    ) public returns (uint256 refinancedLoanId) {
        // Check if the offer is refinancing offer
        if (offer.refinancingLoanId != 0 && offer.refinancingLoanId != loanId) {
            revert InvalidRefinancingLoanId({ refinancingLoanId: offer.refinancingLoanId });
        }

        // Check permit
        _checkPermit(msg.sender, offer.creditAddress, permit);

        // Accept offer
        (bytes32 offerHash, PWNSimpleLoan.Terms memory loanTerms) = _acceptOffer(offer, offerValues, signature);

        // Refinance loan
        return PWNSimpleLoan(offer.loanContract).refinanceLOAN({
            loanId: loanId,
            proposalHash: offerHash,
            loanTerms: loanTerms,
            permit: permit,
            extra: extra
        });
    }

    /**
     * @notice Accept an offer with a callers nonce revocation.
     * @dev Function will mark an offer hash and callers nonce as revoked.
     * @param offer Offer struct containing all offer data.
     * @param offerValues OfferValues struct specifying all flexible offer values.
     * @param signature Lender signature of an offer.
     * @param permit Callers permit data.
     * @param extra Auxiliary data that are emitted in the loan creation event. They are not used in the contract logic.
     * @param callersNonceSpace Nonce space of a callers nonce.
     * @param callersNonceToRevoke Nonce to revoke.
     * @return loanId Id of a created loan.
     */
    function acceptOffer(
        Offer calldata offer,
        OfferValues calldata offerValues,
        bytes calldata signature,
        Permit calldata permit,
        bytes calldata extra,
        uint256 callersNonceSpace,
        uint256 callersNonceToRevoke
    ) external returns (uint256 loanId) {
        _revokeCallersNonce(msg.sender, callersNonceSpace, callersNonceToRevoke);
        return acceptOffer(offer, offerValues, signature, permit, extra);
    }

    /**
     * @notice Accept a refinancing offer with a callers nonce revocation.
     * @dev Function will mark an offer hash and callers nonce as revoked.
     * @param loanId Id of a loan to be refinanced.
     * @param offer Offer struct containing all offer data.
     * @param offerValues OfferValues struct specifying all flexible offer values.
     * @param signature Lender signature of an offer.
     * @param permit Callers permit data.
     * @param extra Auxiliary data that are emitted in the loan creation event. They are not used in the contract logic.
     * @param callersNonceSpace Nonce space of a callers nonce.
     * @param callersNonceToRevoke Nonce to revoke.
     * @return refinancedLoanId Id of a created refinanced loan.
     */
    function acceptRefinanceOffer(
        uint256 loanId,
        Offer calldata offer,
        OfferValues calldata offerValues,
        bytes calldata signature,
        Permit calldata permit,
        bytes calldata extra,
        uint256 callersNonceSpace,
        uint256 callersNonceToRevoke
    ) external returns (uint256 refinancedLoanId) {
        _revokeCallersNonce(msg.sender, callersNonceSpace, callersNonceToRevoke);
        return acceptRefinanceOffer(loanId, offer, offerValues, signature, permit, extra);
    }


    /*----------------------------------------------------------*|
    |*  # INTERNALS                                             *|
    |*----------------------------------------------------------*/

    function _acceptOffer(
        Offer calldata offer,
        OfferValues calldata offerValues,
        bytes calldata signature
    )  private returns (bytes32 offerHash, PWNSimpleLoan.Terms memory loanTerms) {
        // Check if the loan contract has a tag
        _checkLoanContractTag(offer.loanContract);

        // Check min collateral amount
        if (offer.minCollateralAmount == 0) {
            revert MinCollateralAmountNotSet();
        }
        if (offerValues.collateralAmount < offer.minCollateralAmount) {
            revert InsufficientCollateralAmount({
                current: offerValues.collateralAmount,
                limit: offer.minCollateralAmount
            });
        }

        // Check collateral state fingerprint if needed
        if (offer.checkCollateralStateFingerprint) {
            _checkCollateralState({
                addr: offer.collateralAddress,
                id: offer.collateralId,
                stateFingerprint: offer.collateralStateFingerprint
            });
        }

        // Calculate credit amount
        uint256 creditAmount = _creditAmount(offerValues.collateralAmount, offer.creditPerCollateralUnit);

        // Try to accept offer
        offerHash = _tryAcceptOffer(offer, creditAmount, signature);

        // Create loan terms object
        loanTerms = _createLoanTerms(offer, offerValues.collateralAmount, creditAmount);
    }

    function _creditAmount(uint256 collateralAmount, uint256 creditPerCollateralUnit) private pure returns (uint256) {
        return Math.mulDiv(collateralAmount, creditPerCollateralUnit, CREDIT_PER_COLLATERAL_UNIT_DENOMINATOR);
    }

    function _tryAcceptOffer(
        Offer calldata offer,
        uint256 creditAmount,
        bytes calldata signature
    ) private returns (bytes32 offerHash) {
        offerHash = getOfferHash(offer);
        _tryAcceptProposal({
            proposalHash: offerHash,
            creditAmount: creditAmount,
            availableCreditLimit: offer.availableCreditLimit,
            apr: offer.accruingInterestAPR,
            duration: offer.duration,
            expiration: offer.expiration,
            nonceSpace: offer.nonceSpace,
            nonce: offer.nonce,
            allowedAcceptor: offer.allowedBorrower,
            acceptor: msg.sender,
            signer: offer.lender,
            signature: signature
        });
    }

    function _createLoanTerms(
        Offer calldata offer,
        uint256 collateralAmount,
        uint256 creditAmount
    ) private view returns (PWNSimpleLoan.Terms memory) {
        return PWNSimpleLoan.Terms({
            lender: offer.lender,
            borrower: msg.sender,
            duration: offer.duration,
            collateral: MultiToken.Asset({
                category: offer.collateralCategory,
                assetAddress: offer.collateralAddress,
                id: offer.collateralId,
                amount: collateralAmount
            }),
            credit: MultiToken.ERC20({
                assetAddress: offer.creditAddress,
                amount: creditAmount
            }),
            fixedInterestAmount: offer.fixedInterestAmount,
            accruingInterestAPR: offer.accruingInterestAPR
        });
    }

}
