// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

library PWNHubTags {

    string internal constant VERSION = "1.0.0";

    bytes32 internal constant ACTIVE_LOAN_MANAGER = keccak256("PWN_ACTIVE_LOAN_MANAGER");
    bytes32 internal constant LOAN_MANAGER = keccak256("PWN_LOAN_MANAGER");

}
