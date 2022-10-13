// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

library PWNHubTags {

    string internal constant VERSION = "0.1.0";

    /// @dev Address can mint LOAN tokens and create LOANs via loan factory contracts.
    bytes32 internal constant ACTIVE_LOAN = keccak256("PWN_ACTIVE_LOAN");

    /// @dev Address can revoke loan offer nonces.
    bytes32 internal constant LOAN_OFFER = keccak256("PWN_LOAN_OFFER");
    /// @dev Address can be used as a loan factory for creating loans.
    bytes32 internal constant LOAN_FACTORY = keccak256("PWN_LOAN_FACTORY");

}
