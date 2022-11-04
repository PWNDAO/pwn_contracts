// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "@pwn/hub/PWNHubAccessControl.sol";
import "@pwn/loan/terms/simple/factory/IPWNSimpleLoanTermsFactory.sol";
import "@pwn/nonce/PWNRevokedNonce.sol";
import "@pwn/PWNErrors.sol";


abstract contract PWNSimpleLoanOffer is IPWNSimpleLoanTermsFactory, PWNHubAccessControl {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    PWNRevokedNonce immutable internal revokedOfferNonce;

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
    event OfferMade(bytes32 indexed offerHash, address indexed lender);


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(address hub, address _revokedOfferNonce) PWNHubAccessControl(hub) {
        revokedOfferNonce = PWNRevokedNonce(_revokedOfferNonce);
    }


    /*----------------------------------------------------------*|
    |*  # OFFER MANAGEMENT                                      *|
    |*----------------------------------------------------------*/

    /**
     * @notice Make an on-chain offer.
     * @dev Function will mark an offer hash as proposed. Offer will become acceptable by a borrower without an offer signature.
     * @param offerStructHash Hash of a proposed offer.
     * @param lender Address of an offer proposer (lender).
     * @param nonce Nonce used in an offer.
     */
    function _makeOffer(bytes32 offerStructHash, address lender, uint256 nonce) internal {
        // Check that caller is a lender
        if (msg.sender != lender)
            revert CallerIsNotStatedLender(lender);

        // Check that offer has not been made
        if (offersMade[offerStructHash] == true)
            revert OfferAlreadyExists();

        // Check that offer has not been revoked
        if (revokedOfferNonce.isNonceRevoked(lender, nonce) == true)
            revert NonceAlreadyRevoked();

        // Mark offer as made
        offersMade[offerStructHash] = true;

        emit OfferMade(offerStructHash, lender);
    }

    /**
     * @notice Helper function for revoking an offer nonce on behalf of a caller.
     * @param offerNonce Offer nonce to be revoked.
     */
    function revokeOfferNonce(uint256 offerNonce) external {
        revokedOfferNonce.revokeNonce(msg.sender, offerNonce);
    }

}
