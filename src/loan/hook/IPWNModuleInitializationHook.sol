// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

interface IPWNModuleInitializationHook {
    /** @dev Hook must return keccak of a module name + ".onLoanCreated", e.g., "PWNDefaultModule.onLoanCreated".*/
    function onLoanCreated(uint256 loanId, bytes calldata proposerData) external returns (bytes32);
}
