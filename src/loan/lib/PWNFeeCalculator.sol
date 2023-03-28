// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;


/**
 * @title PWN Fee Calculator
 * @notice Library that calculates fee amount for given loan amount.
 */
library PWNFeeCalculator {

    string internal constant VERSION = "1.0";

    /**
     * @notice Compute fee amount.
     * @param fee Fee value in basis points. Value of 100 is 1% fee.
     * @param loanAmount Amount of an asset used as a loan credit.
     * @return feeAmount Amount of a loan asset that represents a protocol fee.
     * @return newLoanAmount New amount of a loan credit asset, after deducting protocol fee.
     */
    function calculateFeeAmount(uint16 fee, uint256 loanAmount) internal pure returns (uint256 feeAmount, uint256 newLoanAmount) {
        if (fee == 0)
            return (0, loanAmount);

        unchecked {
            if ((loanAmount * fee) / fee == loanAmount)
                feeAmount = loanAmount * uint256(fee) / 1e4;
            else
                feeAmount = loanAmount / 1e4 * uint256(fee);
        }
        newLoanAmount = loanAmount - feeAmount;
    }

}
