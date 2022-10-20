// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "@pwn/hub/PWNHubAccessControl.sol";
import "@pwn/PWNError.sol";


/**
 * @title PWN Revoked Request Nonce
 * @notice Contract holding revoked request nonces for loan request contracts to check.
 */
contract PWNRevokedRequestNonce is PWNHubAccessControl {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    /**
     * @dev Mapping of revoked request nonces by an address.
     *      Every address has its own nonce space.
     *      (owner => nonce => is revoked)
     */
    mapping (address => mapping (bytes32 => bool)) private revokedRequestNonces;


    /*----------------------------------------------------------*|
    |*  # EVENTS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /**
     * @dev Emitted when an request nonce is revoked.
     */
    event RequestNonceRevoked(address indexed owner, bytes32 indexed requestNonce);


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(address hub) PWNHubAccessControl(hub) {

    }


    /*----------------------------------------------------------*|
    |*  # REVOKE REQUEST NONCE                                  *|
    |*----------------------------------------------------------*/

    /**
     * @notice Revoke a request nonce.
     * @dev Caller is used as a request nonce owner.
     * @param requestNonce Nonce to be revoked.
     */
    function revokeRequestNonce(bytes32 requestNonce) external {
        _revokeRequestNonce(msg.sender, requestNonce);
    }

    /**
     * @notice Revoke a request nonce on behalf of an owner.
     * @dev Only an addresse with associated `LOAN_REQUEST` tag in PWN Hub can call this function.
     * @param owner Owner address of a revoking nonce.
     * @param requestNonce Nonce to be revoked.
     */
    function revokeRequestNonce(address owner, bytes32 requestNonce) external onlyLoanRequest {
        _revokeRequestNonce(owner, requestNonce);
    }

    function _revokeRequestNonce(address owner, bytes32 requestNonce) private {
        // Check that request nonce is not have been revoked
        if (revokedRequestNonces[owner][requestNonce] == true)
            revert PWNError.NonceRevoked();

        // Revoke nonce
        revokedRequestNonces[owner][requestNonce] = true;

        // Emit event
        emit RequestNonceRevoked(owner, requestNonce);
    }


    /*----------------------------------------------------------*|
    |*  # IS REQUEST NONCE REVOKED                              *|
    |*----------------------------------------------------------*/

    function isRequestNonceRevoked(address owner, bytes32 requestNonce) external view returns (bool) {
        return revokedRequestNonces[owner][requestNonce];
    }

}
