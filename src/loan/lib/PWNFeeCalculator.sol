// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;


// TODO: Doc
library PWNFeeCalculator {

    // TODO: Doc
    function calculateFeeAmount(uint16 fee, uint256 loanAmount) internal pure returns (uint256 feeAmount, uint256 newLoanAmount) {
        feeAmount = loanAmount * uint256(fee) / 10000;
        newLoanAmount = loanAmount - feeAmount;
    }

}
