// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "MultiToken/MultiToken.sol";

import "../../../hub/PWNHubAccessControl.sol";
import "../../../loan/type/PWNSimpleLoan.sol";
import "../../PWNRevokedOfferNonce.sol";
import "../../lib/PWNSignatureChecker.sol";
import "../IPWNSimpleLoanFactory.sol";


/**
 * @title PWN Simple Loan Simple Offer
 * @notice Loan factory contract creating a simple loan from a simple offer.
 */
contract PWNSimpleLoanSimpleOffer is IPWNSimpleLoanFactory, PWNHubAccessControl {

    string internal constant VERSION = "0.1.0";

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    /**
     * @dev EIP-712 simple offer struct type hash.
     */
    bytes32 constant internal OFFER_TYPEHASH = keccak256(
        "Offer(uint8 collateralCategory,address collateralAddress,uint256 collateralId,uint256 collateralAmount,address loanAssetAddress,uint256 loanAmount,uint256 loanYield,uint32 duration,uint40 expiration,address borrower,address lender,bool isPersistent,bytes32 nonce)"
    );

    PWNRevokedOfferNonce immutable internal revokedOfferNonce;

    /**
     * @notice Construct defining an simple offer.
     * @param collateralCategory Category of an asset used as a collateral (0 == ERC20, 1 == ERC721, 2 == ERC1155).
     * @param collateralAddress Address of an asset used as a collateral.
     * @param collateralId Token id of an asset used as a collateral, in case of ERC20 should be 0.
     * @param collateralAmount Amount of tokens used as a collateral, in case of ERC721 should be 1.
     * @param loanAssetAddress Address of an asset which is lended to a borrower.
     * @param loanAmount Amount of tokens which is offered as a loan to a borrower
     * @param loanYield Amount of tokens which acts as a lenders loan interest. Borrower has to pay back a borrowed amount + yield.
     * @param duration Loan duration in seconds.
     * @param expiration Offer expiration timestamp in seconds.
     * @param borrower Address of a borrower. Only this address can accept an offer. If the address is zero address, anybody with a collateral can accept the offer.
     * @param lender Address of a lender. This address has to sign an offer to be valid.
     * @param isPersistent If true, offer will not be revoked on acceptance. Persistent offer can be revoked manually.
     * @param nonce Additional value to enable identical offers in time. Without it, it would be impossible to make again offer, which was once revoked.
     *              Can be used to create a group of offers, where accepting one offer will make other offers in the group revoked.
     */
    struct Offer {
        MultiToken.Category collateralCategory;
        address collateralAddress;
        uint256 collateralId;
        uint256 collateralAmount;
        address loanAssetAddress;
        uint256 loanAmount;
        uint256 loanYield;
        uint32 duration;
        uint40 expiration;
        address borrower;
        address lender;
        bool isPersistent;
        bytes32 nonce;
    }

    /**
     * @dev Mapping of offers made via on-chain transactions.
     *      Could be used by contract wallets instead of EIP-1271.
     *      (offer hash => is made)
     */
    mapping (bytes32 => bool) public offersMade;

    /*----------------------------------------------------------*|
    |*  # EVENTS & ERRORS DEFINITIONS                           *|
    |*----------------------------------------------------------*/

    /**
     * @dev Emitted when an offer is made via an on-chain transaction.
     */
    event OfferMade(bytes32 indexed offerHash);


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(address hub, address _revokedOfferNonce) PWNHubAccessControl(hub) {
        revokedOfferNonce = PWNRevokedOfferNonce(_revokedOfferNonce);
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
        require(msg.sender == offer.lender, "Caller is not stated as a lender");

        bytes32 offerStructHash = getOfferHash(offer);

        // Check that offer has not been made
        require(offersMade[offerStructHash] == false, "Offer already exists");

        // Check that offer has not been revoked
        require(revokedOfferNonce.revokedOfferNonces(msg.sender, offer.nonce) == false, "Offer nonce is revoked");

        // Mark offer as made
        offersMade[offerStructHash] = true;

        emit OfferMade(offerStructHash);
    }

    /**
     * @notice Helper function for revoking an offer nonce on behalf of a caller.
     * @param offerNonce Offer nonce to be revoked.
     */
    function revokeOfferNonce(bytes32 offerNonce) external {
        revokedOfferNonce.revokeOfferNonce(msg.sender, offerNonce);
    }


    /*----------------------------------------------------------*|
    |*  # IPWNSimpleLoanFactory                                 *|
    |*----------------------------------------------------------*/

    /**
     * @notice See { IPWNSimpleLoanFactory.sol }.
     */
    function createLOAN(
        address caller,
        bytes calldata loanFactoryData,
        bytes calldata signature
    ) external override onlyActiveLoan returns (
        PWNSimpleLoan.LOAN memory loan,
        address lender,
        address borrower
    ) {
        Offer memory offer = abi.decode(loanFactoryData, (Offer));
        bytes32 offerHash = getOfferHash(offer);

        lender = offer.lender;
        borrower = caller;

        // Check that offer has been made via on-chain tx, EIP-1271 or signed off-chain
        if (offersMade[offerHash] == false)
            require(PWNSignatureChecker.isValidSignatureNow(lender, offerHash, signature) == true, "Invalid offer signature");

        // Check valid offer
        require(offer.expiration == 0 || block.timestamp < offer.expiration, "Offer is expired");
        require(revokedOfferNonce.revokedOfferNonces(lender, offer.nonce) == false, "Offer is revoked or has been accepted");
        if (offer.borrower != address(0))
            require(borrower == offer.borrower, "Caller is not offer borrower");

        // Prepare collateral and loan asset
        MultiToken.Asset memory collateral = MultiToken.Asset({
            category: offer.collateralCategory,
            assetAddress: offer.collateralAddress,
            id: offer.collateralId,
            amount: offer.collateralAmount
        });
        MultiToken.Asset memory loanAsset = MultiToken.Asset({
            category: MultiToken.Category.ERC20,
            assetAddress: offer.loanAssetAddress,
            id: 0,
            amount: offer.loanAmount
        });

        // Create loan object
        loan = PWNSimpleLoan.LOAN({
            status: 2,
            borrower: borrower,
            duration: offer.duration,
            expiration: uint40(block.timestamp) + offer.duration,
            collateral: collateral,
            asset: loanAsset,
            loanRepayAmount: offer.loanAmount + offer.loanYield
        });

        // Revoke offer if not persistent
        if (!offer.isPersistent)
            revokedOfferNonce.revokeOfferNonce(lender, offer.nonce);
    }

    // TODO: ??? function createLOAN(...) external view returns (...) for FE?

    // TODO: ??? function encodeOffer(Offer) external pure returns (bytes memory) for FE?


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
            "\x19\x01",
            keccak256(abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("PWNSimpleLoanSimpleOffer"),
                keccak256("1"),
                block.chainid,
                address(this)
            )),
            keccak256(abi.encodePacked(
                OFFER_TYPEHASH,
                abi.encode(
                    offer.collateralCategory,
                    offer.collateralAddress,
                    offer.collateralId,
                    offer.collateralAmount
                ), // Need to prevent `slot(s) too deep inside the stack` error
                abi.encode(
                    offer.loanAssetAddress,
                    offer.loanAmount,
                    offer.loanYield,
                    offer.duration,
                    offer.expiration,
                    offer.borrower,
                    offer.lender,
                    offer.isPersistent,
                    offer.nonce
                )
            ))
        ));
    }

}
