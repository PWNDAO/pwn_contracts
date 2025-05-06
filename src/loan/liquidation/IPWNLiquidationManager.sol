// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

interface IPWNLiquidationManager {
    /** @dev Must return keccak of "PWNLiquidationManager.onLoanCreated"*/
    function onLoanCreated(uint256 loanId, bytes calldata proposerData) external returns (bytes32);
}
