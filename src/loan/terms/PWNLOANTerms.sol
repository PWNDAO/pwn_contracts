// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "MultiToken/MultiToken.sol";


library PWNLOANTerms {

    /**
     * @notice Struct defining a simple loan terms.
     * @dev This struct is created by loan factories and never stored.
     * @param lender Address of a lender.
     * @param borrower Address of a borrower.
     * @param defaultTimestamp Unix timestamp (in seconds) setting up a default date.
     * @param collateral Asset used as a loan collateral. For a definition see { MultiToken dependency lib }.
     * @param asset Asset used as a loan credit. For a definition see { MultiToken dependency lib }.
     * @param fixedInterestAmount Fixed interest amount in loan asset tokens. It is the minimum amount of interest which has to be paid by a borrower.
     * @param accruingInterestAPR Accruing interest APR.
     * @param canCreate If true, the terms can be used to create a new loan.
     * @param canRefinance If true, the terms can be used to refinance a running loan.
     * @param refinancingLoanId Id of a loan which is refinanced by this terms. If the id is 0, any loan can be refinanced.
     */
    struct Simple {
        address lender;
        address borrower;
        uint40 defaultTimestamp;
        MultiToken.Asset collateral;
        MultiToken.Asset asset;
        uint256 fixedInterestAmount;
        uint40 accruingInterestAPR;
        bool canCreate;
        bool canRefinance;
        uint256 refinancingLoanId;
    }

}
