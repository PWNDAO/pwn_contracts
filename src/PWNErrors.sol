// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;


// Access control
error CallerMissingHubTag(bytes32);

// Loan contract
error LoanDefaulted(uint40);
error InvalidLoanStatus(uint256);
error NonExistingLoan();
error CallerNotLOANTokenHolder();
error InvalidExtendedExpirationDate();
error BorrowerMismatch(address currentBorrower, address newBorrower);

// Invalid asset
error InvalidLoanAsset();
error InvalidCollateralAsset();

// LOAN token
error InvalidLoanContractCaller();

// Vault
error UnsupportedTransferFunction();
error IncompleteTransfer();

// Nonce
error NonceAlreadyRevoked();
error InvalidMinNonce();

// Signature checks
error InvalidSignatureLength(uint256);
error InvalidSignature();

// Offer
error CallerIsNotStatedBorrower(address);
error OfferExpired();
error CollateralIdIsNotWhitelisted();

// Request
error CallerIsNotStatedLender(address);
error RequestExpired();

// Request & Offer
error InvalidDuration();
error InvalidCreateTerms();
error InvalidRefinanceTerms();
error InvalidRefinancingLoanId(uint256 refinancingLoanId);
error AccruingInterestAPROutOfBounds(uint40 providedAPR, uint40 maxAPR);

// Input data
error InvalidInputData();

// Config
error InvalidFeeValue();
error InvalidFeeCollector();
error ZeroLoanContract();
