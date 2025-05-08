// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { IPWNModuleInitializationHook } from "pwn/loan/hook/IPWNModuleInitializationHook.sol";


bytes32 constant LIQUIDATION_MODULE_INIT_HOOK_RETURN_VALUE = keccak256("PWNLiquidationModule.onLoanCreated");

/** @dev Init hook must return keccak of "PWNLiquidationModule.onLoanCreated".*/
interface IPWNLiquidationModule is IPWNModuleInitializationHook {}
