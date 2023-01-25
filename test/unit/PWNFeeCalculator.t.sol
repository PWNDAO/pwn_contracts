// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "@pwn/loan/lib/PWNFeeCalculator.sol";


contract PWNFeeCalculator_CalculateFeeAmount_Test is Test {

    function test_shouldReturnCorrectValue_forZeroFee() external {
        (uint256 feeAmount, uint256 newLoanAmount) = PWNFeeCalculator.calculateFeeAmount(0, 5400);

        assertEq(feeAmount, 0);
        assertEq(newLoanAmount, 5400);
    }

    function test_shouldReturnCorrectValue_forNonZeroFee() external {
        (uint256 feeAmount, uint256 newLoanAmount) = PWNFeeCalculator.calculateFeeAmount(100, 5400);

        assertEq(feeAmount, 54);
        assertEq(newLoanAmount, 5346);
    }

    function test_shouldHandleZeroAmount() external {
        (uint256 feeAmount, uint256 newLoanAmount) = PWNFeeCalculator.calculateFeeAmount(0, 0);

        assertEq(feeAmount, 0);
        assertEq(newLoanAmount, 0);
    }

    function test_shouldHandleSmallAmount() external {
        (uint256 feeAmount, uint256 newLoanAmount) = PWNFeeCalculator.calculateFeeAmount(100, 10);

        assertEq(feeAmount, 0);
        assertEq(newLoanAmount, 10);
    }

}
