// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { IPWNInterestModule } from "pwn/core/interfaces/IPWNInterestModule.sol";
import { IPWNDefaultModule } from "pwn/core/interfaces/IPWNDefaultModule.sol";


/**
 * @notice Struct defining loan terms.
 * @dev This struct is created by proposal contracts and never stored.
 * @param proposalHash Hash of a proposal that created this loan terms.
 * @param lender Address of a lender.
 * @param borrower Address of a borrower.
 * @param duration Loan duration in seconds.
 * @param collateral Asset used as a loan collateral. For a definition see { MultiToken dependency lib }.
 * @param credit Asset used as a loan credit. For a definition see { MultiToken dependency lib }.
 * @param fixedInterestAmount Fixed interest amount in credit asset tokens. It is the minimum amount of interest which has to be paid by a borrower.
 * @param accruingInterestAPR Accruing interest APR with 2 decimals.
 * @param defaultModule Address of a default module. It is a contract which defines the default conditions.
 * @param defaultModuleProposerData Data passed to a default module when a loan is created.
 * @param lenderSpecHash Hash of a lender specification.
 * @param borrowerSpecHash Hash of a borrower specification.
 */
struct LoanTerms {
    bytes32 proposalHash;
    address lender;
    address borrower;
    MultiToken.Asset collateral;
    MultiToken.Asset credit;
    IPWNInterestModule interestModule;
    bytes interestModuleProposerData;
    IPWNDefaultModule defaultModule;
    bytes defaultModuleProposerData;
    bytes32 lenderSpecHash;
    bytes32 borrowerSpecHash;
}
