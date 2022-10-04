// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

import "MultiToken/MultiToken.sol";

import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/contracts/interfaces/IERC1271.sol";

import "../PWNConfig.sol";
import "../PWNLOAN.sol";
import "../PWNRevokedOfferNonce.sol";
import "../PWNVault.sol";


contract PWNSimpleOfferSimpleLoanManager is PWNVault {

    /**
     * EIP-1271 valid signature magic value
     */
    bytes4 constant internal EIP1271_VALID_SIGNATURE = 0x1626ba7e;

    /**
     * EIP-712 offer struct type hash
     */
    bytes32 constant internal OFFER_TYPEHASH = keccak256(
        "Offer(uint8 collateralCategory,address collateralAddress,uint256 collateralId,uint256 collateralAmount,address loanAssetAddress,uint256 loanAmount,uint256 loanYield,uint32 duration,uint40 expiration,address borrower,address lender,bool isPersistent,bytes32 nonce)"
    );

    // TODO: Doc
    PWNLOAN immutable internal loanToken;
    // TODO: Doc
    PWNRevokedOfferNonce immutable internal revokedOfferNonce;
    // TODO: Doc
    PWNConfig immutable internal config;

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

    /**
     * Construct defining a LOAN which is an acronym for: ... (TODO)
     * @param status 0 == none/dead || 2 == running/accepted offer || 3 == paid back || 4 == expired
     * @param borrower Address of the borrower - stays the same for entire lifespan of the token
     * @param duration Loan duration in seconds
     * @param expiration Unix timestamp (in seconds) setting up the default deadline
     * @param collateral Asset used as a loan collateral. Consisting of another `Asset` struct defined in the MultiToken library
     * @param asset Asset to be borrowed by lender to borrower. Consisting of another `Asset` struct defined in the MultiToken library
     * @param loanRepayAmount Amount of LOAN asset to be repaid
     */
    struct LOAN {
        uint8 status;
        address borrower;
        uint32 duration;
        uint40 expiration;
        MultiToken.Asset collateral;
        MultiToken.Asset asset;
        uint256 loanRepayAmount;
    }

    // TODO: Doc
    mapping (bytes32 => bool) public offersMade;

    /**
     * Mapping of all LOAN data by loan id
     */
    mapping (uint256 => LOAN) public LOANs;


    constructor(address _loanToken, address _revokedOfferNonce, address _config) {
        loanToken = PWNLOAN(_loanToken);
        revokedOfferNonce = PWNRevokedOfferNonce(_revokedOfferNonce);
        config = PWNConfig(_config);
    }


    // TODO: Doc
    function makeOffer(Offer calldata offer) external {
        // Check that caller is a lender
        require(msg.sender == offer.lender, "Caller has to be stated as a lender");

        bytes32 offerStructHash = offerTypeStructHash(offer);

        // Check that permission is not have been granted
        require(offersMade[offerStructHash] == false, "Offer already exists");

        // Check that permission is not have been revoked
        require(revokedOfferNonce.revokedOfferNonces(msg.sender, offer.nonce) == false, "Offer nonce is revoked");

        // Grant permission
        offersMade[offerStructHash] = true;

        // TODO: emit OfferMade(...);
    }

    // TODO: Doc
    function revokeOffer(bytes32 offerNonce) external {
        revokedOfferNonce.revokeOfferNonce(msg.sender, offerNonce);
    }

    // TODO: Doc
    function createLoan(
        Offer calldata offer,
        bytes calldata signature,
        bytes calldata loanAssetPermit,
        bytes calldata collateralPermit
    ) external {
        bytes32 offerStructHash = offerTypeStructHash(offer);

        // Check that offer has been made via on-chain tx, EIP-1271 or off-chain signature
        if (offersMade[offerStructHash] == true) {
            // Offer has been made on-chain, no need to check signature
        } else if (offer.lender.code.length > 0) {
            // Check that offer signature is valid for contract account lender
            require(IERC1271(offer.lender).isValidSignature(offerStructHash, signature) == EIP1271_VALID_SIGNATURE, "Signature on behalf of contract is invalid");
        } else {
            // Check that offer signature is valid for EOA lender
            // TODO: Check that support EIP-2098
            require(ECDSA.recover(offerStructHash, signature) == offer.lender, "Lender address didn't sign the offer");
        }

        // Check valid offer
        require(offer.expiration == 0 || block.timestamp < offer.expiration, "Offer is expired");
        require(revokedOfferNonce.revokedOfferNonces(msg.sender, offer.nonce) == false, "Offer is revoked or has been accepted");
        if (offer.borrower != address(0)) {
            require(msg.sender == offer.borrower, "Sender is not offer borrower");
        }

        // Revoke offer if not persistent
        if (!offer.isPersistent)
            revokedOfferNonce.revokeOfferNonce(msg.sender, offer.nonce);

        // TODO: Potential reentrancy vulnerability
        // Mint LOAN token for lender
        uint256 loanId = loanToken.mint(offer.lender);

        // Prepare collateral and loan asset
        MultiToken.Asset memory collateral = MultiToken.Asset(
            offer.collateralCategory,
            offer.collateralAddress,
            offer.collateralId,
            offer.collateralAmount
        );
        MultiToken.Asset memory loanAsset = MultiToken.Asset(
            MultiToken.Category.ERC20,
            offer.loanAssetAddress,
            0,
            offer.loanAmount
        );

        // Store loan data under loan id
        LOAN storage loan = LOANs[loanId];
        loan.status = 2;
        loan.borrower = msg.sender;
        loan.duration = offer.duration;
        loan.expiration = uint40(block.timestamp) + offer.duration;
        loan.collateral = collateral;
        loan.asset = loanAsset;
        loan.loanRepayAmount = offer.loanAmount + offer.loanYield;

        // Transfer collateral to Vault
        _pull(collateral, msg.sender, collateralPermit);
        // Transfer loan asset to borrower
        _pushFrom(loanAsset, offer.lender, msg.sender, loanAssetPermit);

        // TODO: Work with fee

        // TODO: emit LOANCreated(...);
    }

    // TODO: Doc
    function repayLoan(
        uint256 loanId,
        bytes calldata loanAssetPermit
    ) external {
        LOAN memory loan = LOANs[loanId];

        // Check that loan is not from a different manager
        require(loan.status != 0, "Loan is not from current manager");

        // Check that loan running
        require(loan.status == 2, "Loan is not running");

        // Check that loan is not expired
        require(loan.expiration < block.timestamp, "Loan is expired");

        // Move loan to repaid state
        loan.status = 3;

        // Transfer repaid amount of loan asset to Vault
        MultiToken.Asset memory repayLoanAsset = loan.asset;
        repayLoanAsset.amount = loan.loanRepayAmount;
        _pull(repayLoanAsset, msg.sender, loanAssetPermit);

        // Transfer collateral back to borrower
        _push(loan.collateral, loan.borrower);

        // TODO: emit PaidBack(loanId);
    }

    // TODO: Doc
    function claimLoan(uint256 loanId) external {
        LOAN memory loan = LOANs[loanId];

        // Check that caller is LOAN token holder
        require(loanToken.ownerOf(loanId) == msg.sender, "Caller is not a LOAN token holder");
        // Check that loan can be claimed
        require(loan.status == 3 || loan.expiration >= block.timestamp, "Loan can't be claimed yet");

        // Delete loan data and burn loan token
        delete LOANs[loanId];
        loanToken.burn(loanId);

        if (loan.status == 3) { // Loan has been paid back
            // Transfer repaid loan to lender
            MultiToken.Asset memory repayLoanAsset = loan.asset;
            repayLoanAsset.amount = loan.loanRepayAmount;

            _push(repayLoanAsset, msg.sender);
        } else { // Loan expired
             // Transfer collateral to lender
            _push(loan.collateral, msg.sender);
        }

        // TODO: emit LOANClaimed(loanId);
    }


    function offerTypeStructHash(Offer calldata offer) public view returns (bytes32) {
        return keccak256(abi.encodePacked(
            "\x19\x01",
            keccak256(abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("PWNSimpleLoanManager")),
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
