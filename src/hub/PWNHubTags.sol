// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

library PWNHubTags {

    string internal constant VERSION = "1.0";

    /// @dev Address can mint LOAN tokens and create LOANs via loan factory contracts.
    /// 0x9e56ea094d7a53440eef11fa42b63159fbf703b4ee579494a6ae85afc5603594
    bytes32 internal constant ACTIVE_LOAN = keccak256("PWN_ACTIVE_LOAN");

    /// @dev Address can be used as a loan terms factory for creating simple loans.
    /// 0xad7661817597136ce476ebc3173f62ce62c618f21c1809bd506e6dee26b217be
    bytes32 internal constant SIMPLE_LOAN_TERMS_FACTORY = keccak256("PWN_SIMPLE_LOAN_TERMS_FACTORY");

    /// @dev Address can revoke loan request nonces.
    /// 0xcc3e8039ebc82cf2dfc85f5e6f3b220fb59b5b4077418e8b935c7113f42bd229
    bytes32 internal constant LOAN_REQUEST = keccak256("PWN_LOAN_REQUEST");
    /// @dev Address can revoke loan offer nonces.
    /// 0xe28f844deb305d6f42bccd9495572366ffc5df5d7ae8aca8b455248373c4ecfb
    bytes32 internal constant LOAN_OFFER = keccak256("PWN_LOAN_OFFER");

}
