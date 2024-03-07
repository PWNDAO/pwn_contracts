// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { MerkleProof } from "openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";

import { PWNHubAccessControl } from "@pwn/hub/PWNHubAccessControl.sol";
import { PWNSignatureChecker } from "@pwn/loan/lib/PWNSignatureChecker.sol";
import { PWNSimpleLoanTermsFactory } from "@pwn/loan/terms/simple/factory/PWNSimpleLoanTermsFactory.sol";
import { PWNLOANTerms } from "@pwn/loan/terms/PWNLOANTerms.sol";
import { PWNRevokedNonce } from "@pwn/nonce/PWNRevokedNonce.sol";
import { StateFingerprintComputerRegistry, IERC5646 } from "@pwn/state-fingerprint/StateFingerprintComputerRegistry.sol";
import "@pwn/PWNErrors.sol";


/**
 * @title PWN Simple Loan List Offer
 * @notice Loan terms factory contract creating a simple loan terms from a list offer.
 * @dev This offer can be used as a collection offer or define a list of acceptable ids from a collection.
 */
contract PWNSimpleLoanListOffer is PWNSimpleLoanTermsFactory, PWNHubAccessControl {

    string public constant VERSION = "1.2";

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    /**
     * @dev EIP-712 simple offer struct type hash.
     */
    bytes32 public constant OFFER_TYPEHASH = keccak256(
        "Offer(uint8 collateralCategory,address collateralAddress,bytes32 collateralIdsWhitelistMerkleRoot,uint256 collateralAmount,bool checkCollateralStateFingerprint,bytes32 collateralStateFingerprint,address loanAssetAddress,uint256 loanAmount,uint256 availableCreditLimit,uint256 fixedInterestAmount,uint40 accruingInterestAPR,uint32 duration,uint40 expiration,address allowedBorrower,address lender,uint256 nonceSpace,uint256 nonce)"
    );

    bytes32 public immutable DOMAIN_SEPARATOR;

    PWNRevokedNonce public immutable revokedOfferNonce;
    StateFingerprintComputerRegistry public immutable stateFingerprintComputerRegistry;

    /**
     * @dev Mapping of offers made via on-chain transactions.
     *      Could be used by contract wallets instead of EIP-1271.
     *      (offer hash => is made)
     */
    mapping (bytes32 => bool) public offersMade;

    /**
     * @dev Mapping of credit used by an offer.
     *      (offer hash => credit used)
     */
    mapping (bytes32 => uint256) private _creditUsed;

    /**
     * @notice Construct defining a list offer.
     * @param collateralCategory Category of an asset used as a collateral (0 == ERC20, 1 == ERC721, 2 == ERC1155).
     * @param collateralAddress Address of an asset used as a collateral.
     * @param collateralIdsWhitelistMerkleRoot Merkle tree root of a set of whitelisted collateral ids.
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
     * @param nonceSpace Nonce space of an offer nonce. All nonces in the same space can be revoked at once.
     * @param nonce Additional value to enable identical offers in time. Without it, it would be impossible to make again offer, which was once revoked.
     *              Can be used to create a group of offers, where accepting one offer will make other offers in the group revoked.
     */
    struct Offer {
        MultiToken.Category collateralCategory;
        address collateralAddress;
        bytes32 collateralIdsWhitelistMerkleRoot;
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
        uint256 nonceSpace;
        uint256 nonce;
    }

    /**
     * Construct defining an Offer concrete values
     * @param collateralId Selected collateral id to be used as a collateral.
     * @param merkleInclusionProof Proof of inclusion, that selected collateral id is whitelisted.
     *                             This proof should create same hash as the merkle tree root given in an Offer.
     *                             Can be empty for collection offers.
     */
    struct OfferValues {
        uint256 collateralId;
        bytes32[] merkleInclusionProof;
    }


    /*----------------------------------------------------------*|
    |*  # EVENTS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /**
     * @dev Emitted when an offer is made via an on-chain transaction.
     */
    event OfferMade(bytes32 indexed offerHash, address indexed lender, Offer offer);


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(
        address hub,
        address _revokedOfferNonce,
        address _stateFingerprintComputerRegistry
    ) PWNHubAccessControl(hub) {
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256("PWNSimpleLoanListOffer"),
            keccak256(abi.encodePacked(VERSION)),
            block.chainid,
            address(this)
        ));

        revokedOfferNonce = PWNRevokedNonce(_revokedOfferNonce);
        stateFingerprintComputerRegistry = StateFingerprintComputerRegistry(_stateFingerprintComputerRegistry);
    }


    /*----------------------------------------------------------*|
    |*  # OFFER MANAGEMENT                                      *|
    |*----------------------------------------------------------*/

    /**
     * @notice Make an on-chain offer.
     * @dev Function will mark an offer hash as proposed. Offer will become acceptable by a borrower without an offer signature.
     * @param offer Offer struct containing all needed offer data.
     */
    function makeOffer(Offer calldata offer) external {
        // Check that caller is a lender
        if (msg.sender != offer.lender)
            revert CallerIsNotStatedLender(offer.lender);

        bytes32 offerHash = getOfferHash(offer);
        emit OfferMade(offerHash, offer.lender, offer);

        // Mark offer as made
        offersMade[offerHash] = true;
    }

    /**
     * @notice Get available credit for an offer.
     * @param offer Offer struct containing all needed offer data.
     * @return Available credit for an offer.
     */
    function availableCredit(Offer calldata offer) external view returns (uint256) {
        return offer.availableCreditLimit - _creditUsed[getOfferHash(offer)];
    }

    /**
     * @notice Get credit used for an offer.
     * @param offer Offer struct containing all needed offer data.
     * @return Credit used for an offer.
     */
    function creditUsed(Offer calldata offer) external view returns (uint256) {
        return _creditUsed[getOfferHash(offer)];
    }

    /**
     * @notice Helper function for revoking an offer nonce on behalf of a caller.
     * @param offerNonceSpace Nonce space of an offer nonce to be revoked.
     * @param offerNonce Offer nonce to be revoked.
     */
    function revokeOfferNonce(uint256 offerNonceSpace, uint256 offerNonce) external {
        revokedOfferNonce.revokeNonce(msg.sender, offerNonceSpace, offerNonce);
    }


    /*----------------------------------------------------------*|
    |*  # PWNSimpleLoanTermsFactory                             *|
    |*----------------------------------------------------------*/

    /**
     * @inheritdoc PWNSimpleLoanTermsFactory
     */
    function createLOANTerms(
        address caller,
        bytes calldata factoryData,
        bytes calldata signature
    ) external override onlyActiveLoan returns (PWNLOANTerms.Simple memory loanTerms, bytes32 offerHash) {

        (Offer memory offer, OfferValues memory offerValues) = abi.decode(factoryData, (Offer, OfferValues));
        offerHash = getOfferHash(offer);

        address lender = offer.lender;
        address borrower = caller;

        // Check that offer has been made via on-chain tx, EIP-1271 or signed off-chain
        if (!offersMade[offerHash])
            if (!PWNSignatureChecker.isValidSignatureNow(lender, offerHash, signature))
                revert InvalidSignature();

        // Check valid offer
        if (block.timestamp >= offer.expiration)
            revert OfferExpired();

        if (!revokedOfferNonce.isNonceUsable(lender, offer.nonceSpace, offer.nonce))
            revert NonceNotUsable();

        if (offer.allowedBorrower != address(0))
            if (borrower != offer.allowedBorrower)
                revert CallerIsNotStatedBorrower(offer.allowedBorrower);

        if (offer.duration < MIN_LOAN_DURATION)
            revert InvalidDuration();

        // Check APR
        if (offer.accruingInterestAPR > MAX_ACCRUING_INTEREST_APR)
            revert AccruingInterestAPROutOfBounds({
                providedAPR: offer.accruingInterestAPR,
                maxAPR: MAX_ACCRUING_INTEREST_APR
            });

        // Collateral id list
        if (offer.collateralIdsWhitelistMerkleRoot != bytes32(0)) {
            // Verify whitelisted collateral id
            bool isVerifiedId = MerkleProof.verify(
                offerValues.merkleInclusionProof,
                offer.collateralIdsWhitelistMerkleRoot,
                keccak256(abi.encodePacked(offerValues.collateralId))
            );
            if (isVerifiedId == false)
                revert CollateralIdIsNotWhitelisted();
        } // else: Any collateral id - collection offer

        // Check that the collateral state fingerprint matches the current state
        if (offer.checkCollateralStateFingerprint) {
            IERC5646 computer = stateFingerprintComputerRegistry.getStateFingerprintComputer(offer.collateralAddress);
            if (address(computer) == address(0)) {
                // Asset is not implementing ERC5646 and no computer is registered
                revert MissingStateFingerprintComputer();
            }

            bytes32 currentFingerprint = computer.getStateFingerprint(offerValues.collateralId);
            if (offer.collateralStateFingerprint != currentFingerprint) {
                // Fingerprint mismatch
                revert InvalidCollateralStateFingerprint({
                    offered: offer.collateralStateFingerprint,
                    current: currentFingerprint
                });
            }
        }

        // Check that the available credit limit is not exceeded
        if (offer.availableCreditLimit == 0) {
            revokedOfferNonce.revokeNonce(lender, offer.nonceSpace, offer.nonce);
        } else if (_creditUsed[offerHash] + offer.loanAmount <= offer.availableCreditLimit) {
            _creditUsed[offerHash] += offer.loanAmount;
        } else {
            revert AvailableCreditLimitExceeded({
                usedCredit: _creditUsed[offerHash] + offer.loanAmount,
                availableCreditLimit: offer.availableCreditLimit
            });
        }

        // Create loan terms object
        loanTerms = PWNLOANTerms.Simple({
            lender: lender,
            borrower: borrower,
            defaultTimestamp: uint40(block.timestamp) + offer.duration,
            collateral: MultiToken.Asset({
                category: offer.collateralCategory,
                assetAddress: offer.collateralAddress,
                id: offerValues.collateralId,
                amount: offer.collateralAmount
            }),
            asset: MultiToken.ERC20({
                assetAddress: offer.loanAssetAddress,
                amount: offer.loanAmount
            }),
            fixedInterestAmount: offer.fixedInterestAmount,
            accruingInterestAPR: offer.accruingInterestAPR,
            canCreate: true,
            canRefinance: true,
            refinancingLoanId: 0
        });
    }


    /*----------------------------------------------------------*|
    |*  # GET OFFER HASH                                        *|
    |*----------------------------------------------------------*/

    /**
     * @notice Get an offer hash according to EIP-712
     * @param offer Offer struct to be hashed.
     * @return Offer struct hash.
     */
    function getOfferHash(Offer memory offer) public view returns (bytes32) {
        return keccak256(abi.encodePacked(
            hex"1901",
            DOMAIN_SEPARATOR,
            keccak256(abi.encodePacked(
                OFFER_TYPEHASH,
                abi.encode(offer)
            ))
        ));
    }


    /*----------------------------------------------------------*|
    |*  # LOAN TERMS FACTORY DATA ENCODING                      *|
    |*----------------------------------------------------------*/

    /**
     * @notice Return encoded input data for this loan terms factory.
     * @param offer Simple loan list offer struct to encode.
     * @param offerValues Simple loan list offer concrete values from borrower.
     * @return Encoded loan terms factory data that can be used as an input of `createLOANTerms` function with this factory.
     */
    function encodeLoanTermsFactoryData(Offer memory offer, OfferValues memory offerValues) external pure returns (bytes memory) {
        return abi.encode(offer, offerValues);
    }

}
