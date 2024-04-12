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
error InvalidLenderSpecHash(bytes32 current, bytes32 expected);
error InvalidDuration(uint256 current, uint256 limit);
error AccruingInterestAPROutOfBounds(uint256 current, uint256 limit);
error CallerNotVault();
error InvalidSourceOfFunds(address sourceOfFunds);

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
error NonceAlreadyRevoked(address addr, uint256 nonceSpace, uint256 nonce);
error NonceNotUsable(address addr, uint256 nonceSpace, uint256 nonce);

// Signature checks
error InvalidSignatureLength(uint256);
error InvalidSignature(address signer, bytes32 digest);

// Proposal
error CallerIsNotStatedProposer(address);
error AcceptorIsProposer(address addr);
error InvalidRefinancingLoanId(uint256 refinancingLoanId);
error AvailableCreditLimitExceeded(uint256 used, uint256 limit);
error Expired(uint256 current, uint256 expiration);
error CallerNotAllowedAcceptor(address current, address allowed);
error InvalidPermitOwner(address current, address expected);
error InvalidPermitAsset(address current, address expected);
error CollateralIdNotWhitelisted(uint256 id);
error MinCollateralAmountNotSet();
error InsufficientCollateralAmount(uint256 current, uint256 limit);
error InvalidAuctionDuration(uint256 current, uint256 limit);
error AuctionDurationNotInFullMinutes(uint256 current);
error InvalidCreditAmountRange(uint256 minCreditAmount, uint256 maxCreditAmount);
error InvalidCreditAmount(uint256 auctionCreditAmount, uint256 intendedCreditAmount, uint256 slippage);
error AuctionNotInProgress(uint256 currentTimestamp, uint256 auctionStart);
error CallerNotLoanContract(address caller, address loanContract);

// Input data
error InvalidInputData();

// Config
error InvalidFeeValue();
error InvalidFeeCollector();
error ZeroLoanContract();
