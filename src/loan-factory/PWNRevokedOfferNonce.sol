// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "../hub/PWNHubAccessControl.sol";


contract PWNRevokedOfferNonce is PWNHubAccessControl {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    mapping (address => mapping (bytes32 => bool)) public revokedOfferNonces;


    /*----------------------------------------------------------*|
    |*  # EVENTS & ERRORS DEFINITIONS                           *|
    |*----------------------------------------------------------*/

    event OfferNonceRevoked(address indexed owner, bytes32 indexed offerNonce);


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(address hub) PWNHubAccessControl(hub) {

    }


    /*----------------------------------------------------------*|
    |*  # REVOKE OFFER NONCE                                    *|
    |*----------------------------------------------------------*/

    function revokeOfferNonce(bytes32 offerNonce) external {
        _revokeOfferNonce(msg.sender, offerNonce);
    }

    function revokeOfferNonce(address owner, bytes32 offerNonce) external onlyLoanOffer {
        _revokeOfferNonce(owner, offerNonce);
    }

    function _revokeOfferNonce(address owner, bytes32 offerNonce) private {
        // Check that offer nonce is not have been revoked
        require(revokedOfferNonces[owner][offerNonce] == false, "Nonce is already revoked");

        // Revoke nonce
        revokedOfferNonces[owner][offerNonce] = true;

        // Emit event
        emit OfferNonceRevoked(owner, offerNonce);
    }

}
