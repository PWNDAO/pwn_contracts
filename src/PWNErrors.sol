// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;


// Access control
error CallerMissingHubTag(bytes32);

// Loan contract
error LoanDefaulted(uint40);
error InvalidLoanStatus(uint256);
error NonExistingLoan();
error CallerNotLOANTokenHolder();

// LOAN token
error InvalidLoanContractCaller();

// Vault
error UnsupportedTransferFunction();

// Nonce
error NonceRevoked();

// Signature checks
error InvalidSignatureLength(uint256);
error InvalidSignature();

// Offer
error CallerIsNotStatedLender(address);
error CallerIsNotStatedBorrower(address);
error OfferAlreadyExists();
error OfferExpired();
error CollateralIdIsNotWhitelisted();

// Request
error RequestAlreadyExists();
error RequestExpired();
