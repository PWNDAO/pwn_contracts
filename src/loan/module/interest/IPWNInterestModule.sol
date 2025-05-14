// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { IPWNModuleInitializationHook } from "pwn/loan/hook/module/IPWNModuleInitializationHook.sol";


bytes32 constant INTEREST_MODULE_INIT_HOOK_RETURN_VALUE = keccak256("PWNInterestModule.onLoanCreated");

/** @dev Init hook must return keccak of "PWNInterestModule.onLoanCreated".*/
interface IPWNInterestModule is IPWNModuleInitializationHook {
    function interest(address loanContract, uint256 loanId) external view returns (uint256);
}
