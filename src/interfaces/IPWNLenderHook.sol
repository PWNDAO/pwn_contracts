// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

/**
 * @title IPWNLenderHook
 * @notice Interface for a hook that is called after loan creation and before credit transfer from a lender wallet.
 */
interface IPWNLenderHook {

    /**
     * @notice Hook that is called after loan creation and before credit transfer from a lender wallet.
     * @param loanId The ID of the new loan.
     * @param proposalHash The hash of the loan proposal used to create the loan.
     * @param lender The address of the lender.
     * @param creditAddress The address of the credit token.
     * @param creditAmount The amount of credit token that will be transferred to the borrower.
     * @param lenderParameters Additional parameters for the hook, from the lender.
     */
    function onLoanCreated(
        uint256 loanId,
        bytes32 proposalHash,
        address lender,
        address creditAddress,
        uint256 creditAmount,
        bytes calldata lenderParameters
    ) external;

}
