// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

library PWNHubTags {

    string internal constant VERSION = "0.1.0";

    bytes32 internal constant ACTIVE_LOAN = keccak256("PWN_ACTIVE_LOAN");
    bytes32 internal constant LOAN = keccak256("PWN_LOAN");

    bytes32 internal constant LOAN_OFFER = keccak256("PWN_LOAN_OFFER");
    bytes32 internal constant LOAN_FACTORY = keccak256("PWN_LOAN_FACTORY");

}
