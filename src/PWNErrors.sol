// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;


// Access control
error CallerMissingHubTag(bytes32);
error AddressMissingHubTag(address addr, bytes32 tag);

// Loan contract
error LoanDefaulted(uint40);
error InvalidLoanStatus(uint256);
error NonExistingLoan();
error CallerNotLOANTokenHolder();
error RefinanceBorrowerMismatch(address currentBorrower, address newBorrower);
error RefinanceCreditMismatch();
error RefinanceCollateralMismatch();

// Loan extension
error InvalidExtensionDuration(uint256 duration, uint256 limit);
error InvalidExtensionSigner(address allowed, address current);
error InvalidExtensionCaller();

// Invalid asset
error InvalidMultiTokenAsset(uint8 category, address addr, uint256 id, uint256 amount);
error InvalidCollateralStateFingerprint(bytes32 current, bytes32 proposed);

// State fingerprint computer registry
error MissingStateFingerprintComputer();

// LOAN token
error InvalidLoanContractCaller();

// Vault
error UnsupportedTransferFunction();
error IncompleteTransfer();

// Nonce
error NonceNotUsable(address addr, uint256 nonceSpace, uint256 nonce);

// Signature checks
error InvalidSignatureLength(uint256);
error InvalidSignature(address signer, bytes32 digest);

// Offer
error CollateralIdNotWhitelisted(uint256 id);
error MinCollateralAmountNotSet();
error InsufficientCollateralAmount(uint256 current, uint256 limit);

// Proposal
error CallerIsNotStatedProposer(address);
error InvalidDuration(uint256 current, uint256 limit);
error InvalidRefinancingLoanId(uint256 refinancingLoanId);
error AccruingInterestAPROutOfBounds(uint256 current, uint256 limit);
error AvailableCreditLimitExceeded(uint256 used, uint256 limit);
error Expired(uint256 current, uint256 expiration);
error CallerNotAllowedAcceptor(address current, address allowed);
error InvalidPermitOwner(address current, address expected);
error InvalidPermitAsset(address current, address expected);

// Input data
error InvalidInputData();

// Config
error InvalidFeeValue();
error InvalidFeeCollector();
error ZeroLoanContract();
