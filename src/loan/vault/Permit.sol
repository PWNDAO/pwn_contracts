// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

/**
 * @notice Struct to hold the permit data.
 * @param asset The address of the ERC20 token.
 * @param owner The owner of the tokens.
 * @param amount The amount of tokens.
 * @param deadline The deadline for the permit.
 * @param v The v value of the signature.
 * @param r The r value of the signature.
 * @param s The s value of the signature.
 */
struct Permit {
    address asset;
    address owner;
    uint256 amount;
    uint256 deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;
}

/**
 * @notice Thrown when the permit owner is not matching.
 */
error InvalidPermitOwner(address current, address expected);

/**
 * @notice Thrown when the permit asset is not matching.
 */
error InvalidPermitAsset(address current, address expected);
