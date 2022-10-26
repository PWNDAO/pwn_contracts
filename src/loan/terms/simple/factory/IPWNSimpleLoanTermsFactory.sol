// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "@pwn/loan/terms/PWNLOANTerms.sol";


/**
 * @title PWN Simple Loan Terms Factory Interface
 * @notice Interface of a loan factory contract that builds a simple loan terms.
 */
interface IPWNSimpleLoanTermsFactory {

    /**
     * @notice Build a simple loan terms from given data.
     * @dev This function should be called only by contracts working with simple loan terms.
     * @param caller Caller of a create loan function on a loan contract.
     * @param factoryData Encoded data for a loan terms factory.
     * @param signature Signed loan factory data.
     * @return loanTerms Simple loan terms struct created from a loan factory data.
     */
    function getLOANTerms(
        address caller,
        bytes calldata factoryData,
        bytes calldata signature
    ) external returns (PWNLOANTerms.Simple memory loanTerms);

}
