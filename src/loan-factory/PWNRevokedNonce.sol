// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "@pwn/hub/PWNHubAccessControl.sol";
import "@pwn/PWNErrors.sol";


/**
 * @title PWN Revoked Nonce
 * @notice Contract holding revoked nonces.
 */
contract PWNRevokedNonce is PWNHubAccessControl {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    bytes32 immutable internal accessTag;

    /**
     * @dev Mapping of revoked nonces by an address.
     *      Every address has its own nonce space.
     *      (owner => nonce => is revoked)
     */
    mapping (address => mapping (bytes32 => bool)) private revokedNonces;


    /*----------------------------------------------------------*|
    |*  # EVENTS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /**
     * @dev Emitted when an nonce is revoked.
     */
    event NonceRevoked(address indexed owner, bytes32 indexed nonce);


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(address hub, bytes32 _accessTag) PWNHubAccessControl(hub) {
        accessTag = _accessTag;
    }


    /*----------------------------------------------------------*|
    |*  # REVOKE NONCE                                          *|
    |*----------------------------------------------------------*/

    /**
     * @notice Revoke a nonce.
     * @dev Caller is used as a nonce owner.
     * @param nonce Nonce to be revoked.
     */
    function revokeNonce(bytes32 nonce) external {
        _revokeNonce(msg.sender, nonce);
    }

    /**
     * @notice Revoke a nonce on behalf of an owner.
     * @dev Only an address with associated access tag in PWN Hub can call this function.
     * @param owner Owner address of a revoking nonce.
     * @param nonce Nonce to be revoked.
     */
    function revokeNonce(address owner, bytes32 nonce) external onlyWithTag(accessTag) {
        _revokeNonce(owner, nonce);
    }

    function _revokeNonce(address owner, bytes32 nonce) private {
        // Check that nonce is not have been revoked
        if (revokedNonces[owner][nonce] == true)
            revert NonceAlreadyRevoked();

        // Revoke nonce
        revokedNonces[owner][nonce] = true;

        // Emit event
        emit NonceRevoked(owner, nonce);
    }


    /*----------------------------------------------------------*|
    |*  # IS NONCE REVOKED                                      *|
    |*----------------------------------------------------------*/

    function isNonceRevoked(address owner, bytes32 nonce) external view returns (bool) {
        return revokedNonces[owner][nonce];
    }

}
