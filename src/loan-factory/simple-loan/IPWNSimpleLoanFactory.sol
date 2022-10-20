// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "@pwn/loan/type/PWNSimpleLoan.sol";


/**
 * @title PWN Simple Loan Factory Interface
 * @notice Interface of a loan factory contract that creates a simple loan.
 */
interface IPWNSimpleLoanFactory {

    /**
     * @notice Create and return a new simple loan struct.
     * @dev This function should be called only by a simple loan contract.
     * @param caller Caller of a create loan function on a loan contract.
     * @param loanFactoryData Encoded data for a loan factory.
     * @param signature Signed loan factory data.
     * @return loan Simple loan struct created from a loan factory data.
     * @return lender Address of a lender for a created loan.
     * @return borrower Address of a borrower for a created loan.
     */
    function createLOAN(
        address caller,
        bytes calldata loanFactoryData,
        bytes calldata signature
    ) external returns (PWNSimpleLoan.LOAN memory loan, address lender, address borrower);

}
