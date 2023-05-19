// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "@pwn/hub/PWNHubAccessControl.sol";
import "@pwn/loan/terms/simple/factory/PWNSimpleLoanTermsFactory.sol";
import "@pwn/nonce/PWNRevokedNonce.sol";
import "@pwn/PWNErrors.sol";


abstract contract PWNSimpleLoanRequest is PWNSimpleLoanTermsFactory, PWNHubAccessControl {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    PWNRevokedNonce internal immutable revokedRequestNonce;

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
     */
    function _makeRequest(bytes32 requestStructHash, address borrower) internal {
        // Check that caller is a borrower
        if (msg.sender != borrower)
            revert CallerIsNotStatedBorrower(borrower);

        // Mark request as made
        requestsMade[requestStructHash] = true;

        emit RequestMade(requestStructHash, borrower);
    }

    /**
     * @notice Helper function for revoking a request nonce on behalf of a caller.
     * @param requestNonce Request nonce to be revoked.
     */
    function revokeRequestNonce(uint256 requestNonce) external {
        revokedRequestNonce.revokeNonce(msg.sender, requestNonce);
    }

}
