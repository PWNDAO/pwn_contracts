// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;


library PWNContractDeployerSalt {

    string internal constant VERSION = "1.1";

    // Singletons
    bytes32 constant internal CONFIG = keccak256("PWNConfig");
    bytes32 constant internal CONFIG_PROXY = keccak256("PWNConfigProxy");
    bytes32 constant internal HUB = keccak256("PWNHub");
    bytes32 constant internal LOAN = keccak256("PWNLOAN");
    bytes32 constant internal REVOKED_OFFER_NONCE = keccak256("PWNRevokedOfferNonce");
    bytes32 constant internal REVOKED_REQUEST_NONCE = keccak256("PWNRevokedRequestNonce");

    // Loan types
    bytes32 constant internal SIMPLE_LOAN = keccak256("PWNSimpleLoan");

    // Offer types
    bytes32 constant internal SIMPLE_LOAN_SIMPLE_OFFER = keccak256("PWNSimpleLoanSimpleOffer");
    bytes32 constant internal SIMPLE_LOAN_LIST_OFFER = keccak256("PWNSimpleLoanListOffer");

    // Request types
    bytes32 constant internal SIMPLE_LOAN_SIMPLE_REQUEST = keccak256("PWNSimpleLoanSimpleRequest");

    // Timelock controllers
    bytes32 constant internal PROTOCOL_TEAM_TIMELOCK_CONTROLLER = keccak256("PWNProtocolTeamTimelockController");
    bytes32 constant internal PRODUCT_TEAM_TIMELOCK_CONTROLLER = keccak256("PWNProductTeamTimelockController");

}
