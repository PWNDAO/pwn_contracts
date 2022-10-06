// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

import "MultiToken/MultiToken.sol";

import "../../../hub/PWNHubAccessControl.sol";
import "../../../loan/type/PWNSimpleLoan.sol";
import "../../PWNRevokedOfferNonce.sol";
import "../../PWNSignatureChecker.sol";
import "../IPWNSimpleLoanFactory.sol";


contract PWNSimpleLoanSimpleOffer is IPWNSimpleLoanFactory, PWNHubAccessControl {

    string internal constant VERSION = "0.1.0";

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    /**
     * EIP-712 offer struct type hash
     */
    bytes32 constant internal OFFER_TYPEHASH = keccak256(
        "Offer(uint8 collateralCategory,address collateralAddress,uint256 collateralId,uint256 collateralAmount,address loanAssetAddress,uint256 loanAmount,uint256 loanYield,uint32 duration,uint40 expiration,address borrower,address lender,bool isPersistent,bytes32 nonce)"
    );

    // TODO: Doc
    PWNRevokedOfferNonce immutable internal revokedOfferNonce;

    /**
     * Construct defining an Offer
     * @param collateralCategory Category of an asset used as a collateral (0 == ERC20, 1 == ERC721, 2 == ERC1155)
     * @param collateralAddress Address of an asset used as a collateral
     * @param collateralId Token id of an asset used as a collateral, in case of ERC20 should be 0
     * @param collateralAmount Amount of tokens used as a collateral, in case of ERC721 should be 1
     * @param loanAssetAddress Address of an asset which is lended to borrower
     * @param loanAmount Amount of tokens which is offered as a loan to borrower
     * @param loanYield Amount of tokens which acts as a lenders loan interest. Borrower has to pay back borrowed amount + yield.
     * @param duration Loan duration in seconds
     * @param expiration Offer expiration timestamp in seconds
     * @param borrower Address of a borrower. Only this address can accept an offer. If address is zero address, anybody with a collateral can accept an offer.
     * @param lender Address of a lender. This address has to sign an offer to be valid.
     * @param isPersistent If true, offer will not be revoked after acceptance. Persistent offer can be revoked manually.
     * @param nonce Additional value to enable identical offers in time. Without it, it would be impossible to make again offer, which was once revoked.
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

    // TODO: Doc
    mapping (bytes32 => bool) public offersMade;

    /*----------------------------------------------------------*|
    |*  # EVENTS & ERRORS DEFINITIONS                           *|
    |*----------------------------------------------------------*/

    // TODO: Update for Dune
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

    // TODO: Doc
    function makeOffer(Offer calldata offer) external {
        // Check that caller is a lender
        require(msg.sender == offer.lender, "Caller has to be stated as a lender");

        bytes32 offerStructHash = offerTypedDataHash(offer);

        // Check that permission is not have been granted
        require(offersMade[offerStructHash] == false, "Offer already exists");

        // Check that permission is not have been revoked
        require(revokedOfferNonce.revokedOfferNonces(msg.sender, offer.nonce) == false, "Offer nonce is revoked");

        // Grant permission
        offersMade[offerStructHash] = true;

        emit OfferMade(offerStructHash);
    }

    // TODO: Doc
    function revokeOffer(bytes32 offerNonce) external {
        revokedOfferNonce.revokeOfferNonce(msg.sender, offerNonce);
    }


    /*----------------------------------------------------------*|
    |*  # IPWNSimpleLoanFactory                                 *|
    |*----------------------------------------------------------*/

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
        bytes32 offerHash = offerTypedDataHash(offer);

        lender = offer.lender;
        borrower = caller;

        // Check that offer has been made via on-chain tx, EIP-1271 or signed off-chain
        if (offersMade[offerHash] == false)
            require(PWNSignatureChecker.isValidSignatureNow(lender, offerHash, signature) == true, "Invalid offer signature");

        // Check valid offer
        require(offer.expiration == 0 || block.timestamp < offer.expiration, "Offer is expired");
        require(revokedOfferNonce.revokedOfferNonces(borrower, offer.nonce) == false, "Offer is revoked or has been accepted");
        if (offer.borrower != address(0)) {
            require(borrower == offer.borrower, "Caller is not offer borrower");
        }

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
            borrower: caller,
            duration: offer.duration,
            expiration: uint40(block.timestamp) + offer.duration,
            collateral: collateral,
            asset: loanAsset,
            loanRepayAmount: offer.loanAmount + offer.loanYield
        });

        // Revoke offer if not persistent
        if (!offer.isPersistent)
            revokedOfferNonce.revokeOfferNonce(borrower, offer.nonce);
    }

    // TODO: ??? function createLOAN(...) external view returns (...) for FE?

    // TODO: ??? function encodeOffer(Offer) external pure returns (bytes memory) for FE?


    /*----------------------------------------------------------*|
    |*  # OFFER TYPED STRUCT HASH                               *|
    |*----------------------------------------------------------*/

    function offerTypedDataHash(Offer memory offer) public view returns (bytes32) {
        return keccak256(abi.encodePacked(
            "\x19\x01",
            keccak256(abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("PWNSimpleLoanSimpleOffer")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )),
            _offerHash(offer)
        ));
    }

    /**
     * hash offer
     * @notice Hash offer struct according to EIP-712
     * @param offer Offer struct to be hashed
     * @return Offer struct hash
     */
    function _offerHash(Offer memory offer) private pure returns (bytes32) {
        // Need to divide encoding into smaller parts because of "Stack to deep" error

        bytes memory encodedOfferCollateralData = abi.encode(
            offer.collateralCategory,
            offer.collateralAddress,
            offer.collateralId,
            offer.collateralAmount
        );

        bytes memory encodedOfferOtherData = abi.encode(
            offer.loanAssetAddress,
            offer.loanAmount,
            offer.loanYield,
            offer.duration,
            offer.expiration,
            offer.borrower,
            offer.lender,
            offer.isPersistent,
            offer.nonce
        );

        return keccak256(abi.encodePacked(
            OFFER_TYPEHASH,
            encodedOfferCollateralData,
            encodedOfferOtherData
        ));
    }

}
