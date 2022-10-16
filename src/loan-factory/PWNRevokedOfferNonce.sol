// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "@pwn/hub/PWNHubAccessControl.sol";
import "@pwn/PWNError.sol";


/**
 * @title PWN Revoked Offer Nonce
 * @notice Contract holding revoked offer nonces for loan offer contracts to check.
 */
contract PWNRevokedOfferNonce is PWNHubAccessControl {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    /**
     * @dev Mapping of revoked offer nonces by an address.
     *      Every address has its own nonce space.
     *      (owner => nonce => is revoked)
     */
    mapping (address => mapping (bytes32 => bool)) private revokedOfferNonces;


    /*----------------------------------------------------------*|
    |*  # EVENTS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /**
     * @dev Emitted when an offer nonce is revoked.
     */
    event OfferNonceRevoked(address indexed owner, bytes32 indexed offerNonce);


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(address hub) PWNHubAccessControl(hub) {

    }


    /*----------------------------------------------------------*|
    |*  # REVOKE OFFER NONCE                                    *|
    |*----------------------------------------------------------*/

    /**
     * @notice Revoke an offer nonce.
     * @dev Caller is used as an offer nonce owner.
     * @param offerNonce Nonce to be revoked.
     */
    function revokeOfferNonce(bytes32 offerNonce) external {
        _revokeOfferNonce(msg.sender, offerNonce);
    }

    /**
     * @notice Revoke an offer nonce on behalf of an owner.
     * @dev Only an addresse with associated `LOAN_OFFER` tag in PWN Hub can call this function.
     * @param owner Owner address of a revoking nonce.
     * @param offerNonce Nonce to be revoked.
     */
    function revokeOfferNonce(address owner, bytes32 offerNonce) external onlyLoanOffer {
        _revokeOfferNonce(owner, offerNonce);
    }

    function _revokeOfferNonce(address owner, bytes32 offerNonce) private {
        // Check that offer nonce is not have been revoked
        if (revokedOfferNonces[owner][offerNonce] == true)
            revert PWNError.NonceRevoked();

        // Revoke nonce
        revokedOfferNonces[owner][offerNonce] = true;

        // Emit event
        emit OfferNonceRevoked(owner, offerNonce);
    }


    /*----------------------------------------------------------*|
    |*  # IS OFFER NONCE REVOKED                                *|
    |*----------------------------------------------------------*/

    function isOfferNonceRevoked(address owner, bytes32 offerNonce) external view returns (bool) {
        return revokedOfferNonces[owner][offerNonce];
    }

}
