// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "../../hub/PWNHubAccessControl.sol";
import "../../loan/type/PWNSimpleLoan.sol";
import "../PWNRevokedOfferNonce.sol";
import "./IPWNSimpleLoanFactory.sol";


abstract contract PWNSimpleLoanOffer is IPWNSimpleLoanFactory, PWNHubAccessControl {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    PWNRevokedOfferNonce immutable internal revokedOfferNonce;

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
     * @param offerStructHash TODO
     * @param lender TODO
     * @param nonce TODO
     */
    function _makeOffer(bytes32 offerStructHash, address lender, bytes32 nonce) internal {
        // Check that caller is a lender
        require(msg.sender == lender, "Caller is not stated as a lender");

        // Check that offer has not been made
        require(offersMade[offerStructHash] == false, "Offer already exists");

        // Check that offer has not been revoked
        require(revokedOfferNonce.revokedOfferNonces(lender, nonce) == false, "Offer nonce is revoked");

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

}
