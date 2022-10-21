// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "@pwn/hub/PWNHubAccessControl.sol";
import "@pwn/loan/type/PWNSimpleLoan.sol";
import "@pwn/loan-factory/simple-loan/IPWNSimpleLoanTermsFactory.sol";
import "@pwn/loan-factory/PWNRevokedNonce.sol";
import "@pwn/PWNErrors.sol";


abstract contract PWNSimpleLoanRequest is IPWNSimpleLoanTermsFactory, PWNHubAccessControl {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    PWNRevokedNonce immutable internal revokedRequestNonce;

    /**
     * @dev Mapping of requests made via on-chain transactions.
     *      Could be used by contract wallets instead of EIP-1271.
     *      (request hash => is made)
     */
    mapping (bytes32 => bool) public requestsMade;

    /*----------------------------------------------------------*|
    |*  # EVENTS & ERRORS DEFINITIONS                           *|
    |*----------------------------------------------------------*/

    /**
     * @dev Emitted when a request is made via an on-chain transaction.
     */
    event RequestMade(bytes32 indexed requestHash, address indexed borrower);


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(address hub, address _revokedRequestNonce) PWNHubAccessControl(hub) {
        revokedRequestNonce = PWNRevokedNonce(_revokedRequestNonce);
    }


    /*----------------------------------------------------------*|
    |*  # REQUEST MANAGEMENT                                    *|
    |*----------------------------------------------------------*/

    /**
     * @notice Make an on-chain request.
     * @dev Function will mark a request hash as proposed. Request will become acceptable by a borrower without a request signature.
     * @param requestStructHash Hash of a proposed request.
     * @param borrower Address of a request proposer (borrower).
     * @param nonce Nonce used in a request.
     */
    function _makeRequest(bytes32 requestStructHash, address borrower, bytes32 nonce) internal {
        // Check that caller is a borrower
        if (msg.sender != borrower)
            revert CallerIsNotStatedBorrower(borrower);

        // Check that request has not been made
        if (requestsMade[requestStructHash] == true)
            revert RequestAlreadyExists();

        // Check that request has not been revoked
        if (revokedRequestNonce.isNonceRevoked(borrower, nonce) == true)
            revert NonceAlreadyRevoked();

        // Mark request as made
        requestsMade[requestStructHash] = true;

        emit RequestMade(requestStructHash, borrower);
    }

    /**
     * @notice Helper function for revoking a request nonce on behalf of a caller.
     * @param requestNonce Request nonce to be revoked.
     */
    function revokeRequestNonce(bytes32 requestNonce) external {
        revokedRequestNonce.revokeNonce(msg.sender, requestNonce);
    }

}