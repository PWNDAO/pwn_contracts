// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;


/**
 * @notice Thrown when caller is missing a PWN Hub tag.
 */
error CallerMissingHubTag(bytes32);

/**
 * @notice Thrown when an address is missing a PWN Hub tag.
 */
error AddressMissingHubTag(address addr, bytes32 tag);

/**
 * @notice Thrown when `PWNLOAN.burn` caller is not a loan contract that minted the LOAN token.
 */
error InvalidLoanContractCaller();

/**
 * @notice Thrown when `PWNHub.setTags` inputs lengths are not equal.
 */
error InvalidInputData();

/**
 * @notice Thrown when a proposal is expired.
 */
error Expired(uint256 current, uint256 expiration);
