// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

library PWNHubTags {

    string internal constant VERSION = "1.2";

    /// @dev Address can mint LOAN tokens and create LOANs via loan factory contracts.
    bytes32 internal constant ACTIVE_LOAN = keccak256("PWN_ACTIVE_LOAN");
    /// @dev Address can call loan contracts to create and/or refinance a loan.
    bytes32 internal constant LOAN_PROPOSAL = keccak256("PWN_LOAN_PROPOSAL");
    /// @dev Address can revoke nonces on other addresses behalf.
    bytes32 internal constant NONCE_MANAGER = keccak256("PWN_NONCE_MANAGER");

}
