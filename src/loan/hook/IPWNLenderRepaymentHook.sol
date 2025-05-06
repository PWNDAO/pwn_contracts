// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

interface IPWNLenderRepaymentHook {
    /** @dev Must return keccak of "PWNLenderRepaymentHook.onLoanRepaid"*/
    function onLoanRepaid(
        address lender,
        address creditAddress,
        uint256 repayment,
        bytes calldata lenderData
    ) external returns (bytes32);
}
