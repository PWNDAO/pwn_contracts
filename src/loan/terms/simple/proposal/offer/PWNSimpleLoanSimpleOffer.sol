// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { PWNSimpleLoan } from "@pwn/loan/terms/simple/loan/PWNSimpleLoan.sol";
import { PWNSimpleLoanProposal } from "@pwn/loan/terms/simple/proposal/PWNSimpleLoanProposal.sol";
import "@pwn/PWNErrors.sol";


/**
 * @title PWN Simple Loan Simple Offer
 * @notice Loan terms factory contract creating a simple loan terms from a simple offer.
 */
contract PWNSimpleLoanSimpleOffer is PWNSimpleLoanProposal {

    string public constant VERSION = "1.2";

    /**
     * @dev EIP-712 simple offer struct type hash.
     */
    bytes32 public constant OFFER_TYPEHASH = keccak256(
        "Offer(uint8 collateralCategory,address collateralAddress,uint256 collateralId,uint256 collateralAmount,bool checkCollateralStateFingerprint,bytes32 collateralStateFingerprint,address loanAssetAddress,uint256 loanAmount,uint256 availableCreditLimit,uint256 fixedInterestAmount,uint40 accruingInterestAPR,uint32 duration,uint40 expiration,address allowedBorrower,address lender,uint256 refinancingLoanId,uint256 nonceSpace,uint256 nonce,address loanContract)"
    );

    /**
     * @notice Construct defining a simple offer.
     * @param collateralCategory Category of an asset used as a collateral (0 == ERC20, 1 == ERC721, 2 == ERC1155).
     * @param collateralAddress Address of an asset used as a collateral.
     * @param collateralId Token id of an asset used as a collateral, in case of ERC20 should be 0.
     * @param collateralAmount Amount of tokens used as a collateral, in case of ERC721 should be 0.
     * @param checkCollateralStateFingerprint If true, collateral state fingerprint will be checked on loan terms creation.
     * @param collateralStateFingerprint Fingerprint of a collateral state. It is used to check if a collateral is in a valid state.
     * @param loanAssetAddress Address of an asset which is lender to a borrower.
     * @param loanAmount Amount of tokens which is offered as a loan to a borrower.
     * @param availableCreditLimit Available credit limit for the offer. It is the maximum amount of tokens which can be borrowed using the offer.
     * @param fixedInterestAmount Fixed interest amount in loan asset tokens. It is the minimum amount of interest which has to be paid by a borrower.
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
        uint256 collateralAmount;
        bool checkCollateralStateFingerprint;
        bytes32 collateralStateFingerprint;
        address loanAssetAddress;
        uint256 loanAmount;
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

    constructor(
        address _hub,
        address _revokedNonce,
        address _stateFingerprintComputerRegistry
    ) PWNSimpleLoanProposal(
        _hub, _revokedNonce, _stateFingerprintComputerRegistry, "PWNSimpleLoanSimpleOffer", VERSION
    ) {}

    /**
     * @notice Get an offer hash according to EIP-712.
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
     */
    function makeOffer(Offer calldata offer) external {
        _makeProposal(getOfferHash(offer), offer.lender, abi.encode(offer));
    }

    function acceptOffer(
        Offer calldata offer,
        bytes calldata signature,
        bytes calldata loanAssetPermit,
        bytes calldata collateralPermit
    ) public returns (uint256 loanId) {
        // Check if the offer is refinancing offer
        if (offer.refinancingLoanId != 0) {
            revert InvalidRefinancingLoanId({ refinancingLoanId: offer.refinancingLoanId });
        }

        (bytes32 offerHash, PWNSimpleLoan.Terms memory loanTerms) = _acceptOffer(offer, signature);

        // Create loan
        return PWNSimpleLoan(offer.loanContract).createLOAN({
            proposalHash: offerHash,
            loanTerms: loanTerms,
            loanAssetPermit: loanAssetPermit,
            collateralPermit: collateralPermit
        });
    }

    function acceptRefinanceOffer(
        uint256 loanId,
        Offer calldata offer,
        bytes calldata signature,
        bytes calldata lenderLoanAssetPermit,
        bytes calldata borrowerLoanAssetPermit
    ) public returns (uint256 refinancedLoanId) {
        // Check if the offer is refinancing offer
        if (offer.refinancingLoanId != 0 && offer.refinancingLoanId != loanId) {
            revert InvalidRefinancingLoanId({ refinancingLoanId: offer.refinancingLoanId });
        }

        (bytes32 offerHash, PWNSimpleLoan.Terms memory loanTerms) = _acceptOffer(offer, signature);

        // Refinance loan
        return PWNSimpleLoan(offer.loanContract).refinanceLOAN({
            loanId: loanId,
            proposalHash: offerHash,
            loanTerms: loanTerms,
            lenderLoanAssetPermit: lenderLoanAssetPermit,
            borrowerLoanAssetPermit: borrowerLoanAssetPermit
        });
    }

    function acceptOffer(
        Offer calldata offer,
        bytes calldata signature,
        bytes calldata loanAssetPermit,
        bytes calldata collateralPermit,
        uint256 callersNonceSpace,
        uint256 callersNonceToRevoke
    ) external returns (uint256 loanId) {
        _revokeCallersNonce(msg.sender, callersNonceSpace, callersNonceToRevoke);
        return acceptOffer(offer, signature, loanAssetPermit, collateralPermit);
    }

    function acceptRefinanceOffer(
        uint256 loanId,
        Offer calldata offer,
        bytes calldata signature,
        bytes calldata lenderLoanAssetPermit,
        bytes calldata borrowerLoanAssetPermit,
        uint256 callersNonceSpace,
        uint256 callersNonceToRevoke
    ) external returns (uint256 refinancedLoanId) {
        _revokeCallersNonce(msg.sender, callersNonceSpace, callersNonceToRevoke);
        return acceptRefinanceOffer(loanId, offer, signature, lenderLoanAssetPermit, borrowerLoanAssetPermit);
    }


    function _acceptOffer(
        Offer calldata offer,
        bytes calldata signature
    )  private returns (bytes32 offerHash, PWNSimpleLoan.Terms memory loanTerms) {
        // Check if the loan contract has a tag
        _checkLoanContractTag(offer.loanContract);

        // Check collateral state fingerprint if needed
        if (offer.checkCollateralStateFingerprint) {
            _checkCollateralState({
                addr: offer.collateralAddress,
                id: offer.collateralId,
                stateFingerprint: offer.collateralStateFingerprint
            });
        }

        // Try to accept offer
        offerHash = _tryAcceptOffer(offer, signature);

        // Create loan terms object
        loanTerms = _createLoanTerms(offer);
    }

    function _tryAcceptOffer(Offer calldata offer, bytes calldata signature) private returns (bytes32 offerHash) {
        offerHash = getOfferHash(offer);
        _tryAcceptProposal({
            proposalHash: offerHash,
            creditAmount: offer.loanAmount,
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

    function _createLoanTerms(Offer calldata offer) private view returns (PWNSimpleLoan.Terms memory) {
        return PWNSimpleLoan.Terms({
            lender: offer.lender,
            borrower: msg.sender,
            duration: offer.duration,
            collateral: MultiToken.Asset({
                category: offer.collateralCategory,
                assetAddress: offer.collateralAddress,
                id: offer.collateralId,
                amount: offer.collateralAmount
            }),
            asset: MultiToken.ERC20({
                assetAddress: offer.loanAssetAddress,
                amount: offer.loanAmount
            }),
            fixedInterestAmount: offer.fixedInterestAmount,
            accruingInterestAPR: offer.accruingInterestAPR
        });
    }

    function decodeProposal(bytes calldata proposal) external pure returns (Offer memory offer) {
        return abi.decode(proposal, (Offer));
    }

}
