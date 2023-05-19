// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;


library PWNContractDeployerSalt {

    string internal constant VERSION = "1.0";

    // Singletons
    bytes32 constant internal CONFIG_V1 = keccak256("PWNConfigV1");
    bytes32 constant internal CONFIG_PROXY = keccak256("PWNConfigProxy");
    bytes32 constant internal HUB = keccak256("PWNHub");
    bytes32 constant internal LOAN = keccak256("PWNLOAN");
    bytes32 constant internal REVOKED_OFFER_NONCE = keccak256("PWNRevokedOfferNonce");
    bytes32 constant internal REVOKED_REQUEST_NONCE = keccak256("PWNRevokedRequestNonce");

    // Loan types
    bytes32 constant internal SIMPLE_LOAN_V1 = keccak256("PWNSimpleLoanV1");

    // Offer types
    bytes32 constant internal SIMPLE_LOAN_SIMPLE_OFFER_V1 = keccak256("PWNSimpleLoanSimpleOfferV1");
    bytes32 constant internal SIMPLE_LOAN_LIST_OFFER_V1 = keccak256("PWNSimpleLoanListOfferV1");

    // Request types
    bytes32 constant internal SIMPLE_LOAN_SIMPLE_REQUEST_V1 = keccak256("PWNSimpleLoanSimpleRequestV1");

}
