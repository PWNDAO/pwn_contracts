// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;


library PWNContractDeployerSalt {

    string internal constant VERSION = "0.1.0";

    // Singletons
    bytes32 constant internal config = keccak256("PWNConfig");
    bytes32 constant internal hub = keccak256("PWNHub");
    bytes32 constant internal LOAN = keccak256("PWNLOAN");
    bytes32 constant internal revokedOfferNonce = keccak256("PWNRevokedOfferNonce");
    bytes32 constant internal revokedRequestNonce = keccak256("PWNRevokedRequestNonce");

    // Loan types
    bytes32 constant internal simpleLoanV1 = keccak256("PWNSimpleLoanV1");

    // Offer types
    bytes32 constant internal simpleLoanSimpleOfferV1 = keccak256("PWNSimpleLoanSimpleOfferV1");
    bytes32 constant internal simpleLoanListOfferV1 = keccak256("PWNSimpleLoanListOfferV1");

    // Request types
    bytes32 constant internal simpleLoanSimpleRequestV1 = keccak256("PWNSimpleLoanSimpleRequestV1");

}
