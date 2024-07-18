// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;


/**
 * @notice Thrown when an address is missing a PWN Hub tag.
 */
error AddressMissingHubTag(address addr, bytes32 tag);

/**
 * @notice Thrown when a proposal is expired.
 */
error Expired(uint256 current, uint256 expiration);
