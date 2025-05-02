// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";


/**
 * @notice Struct defining loan terms.
 * @dev This struct is created by proposal contracts and never stored.
 * @param lender Address of a lender.
 * @param borrower Address of a borrower.
 * @param duration Loan duration in seconds.
 * @param collateral Asset used as a loan collateral. For a definition see { MultiToken dependency lib }.
 * @param credit Asset used as a loan credit. For a definition see { MultiToken dependency lib }.
 * @param fixedInterestAmount Fixed interest amount in credit asset tokens. It is the minimum amount of interest which has to be paid by a borrower.
 * @param accruingInterestAPR Accruing interest APR with 2 decimals.
 * @param lenderSpecHash Hash of a lender specification.
 * @param borrowerSpecHash Hash of a borrower specification.
 */
struct LoanTerms {
    address lender;
    address borrower;
    uint32 duration;
    MultiToken.Asset collateral;
    MultiToken.Asset credit;
    uint256 fixedInterestAmount;
    uint24 accruingInterestAPR;
    bytes32 lenderSpecHash;
    bytes32 borrowerSpecHash;
}
