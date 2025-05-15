// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { ICometLike } from "pwn/interfaces/ICometLike.sol";
import { IPWNLenderRepaymentHook, LENDER_REPAYMENT_HOOK_RETURN_VALUE } from "pwn/loan/hook/lender/repayment/IPWNLenderRepaymentHook.sol";


contract PWNCompoundLenderRepaymentHook is IPWNLenderRepaymentHook {
    using MultiToken for address;
    using MultiToken for MultiToken.Asset;

    ICometLike public immutable pool;

    error PoolZeroAddress();
    error LenderZeroAddress();
    error CreditZeroAddress();
    error RepaymentZero();
    error DataNotEmpty();


    constructor(ICometLike _pool) {
        if (address(_pool) == address(0)) revert PoolZeroAddress();
        pool = _pool;
    }


    function onLoanRepaid(
        address lender,
        address creditAddress,
        uint256 repayment,
        bytes calldata lenderData
    ) external returns (bytes32) {
        if (lender == address(0)) revert LenderZeroAddress();
        if (creditAddress == address(0)) revert CreditZeroAddress();
        if (repayment == 0) revert RepaymentZero();
        if (lenderData.length == 0) revert DataNotEmpty();

        // Supply to the pool on behalf of the owner
        creditAddress.ERC20(repayment).approveAsset(address(pool));
        pool.supplyFrom(address(this), lender, creditAddress, repayment);

        return LENDER_REPAYMENT_HOOK_RETURN_VALUE;
    }

}
