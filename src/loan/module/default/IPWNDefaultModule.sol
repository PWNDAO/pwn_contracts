// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { IPWNModuleInitializationHook } from "pwn/loan/module/IPWNModuleInitializationHook.sol";


bytes32 constant DEFAULT_MODULE_INIT_HOOK_RETURN_VALUE = keccak256("PWNDefaultModule.onLoanCreated");

/** @dev Init hook must return keccak of "PWNDefaultModule.onLoanCreated".*/
interface IPWNDefaultModule is IPWNModuleInitializationHook {
    function isDefaulted(address loanContract, uint256 loanId) external view returns (bool);
}
