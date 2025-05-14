// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { IPWNLenderRepaymentHook, LENDER_REPAYMENT_HOOK_RETURN_VALUE } from "pwn/loan/hook/lender/repayment/IPWNLenderRepaymentHook.sol";


contract PWNLenderDirectRepaymentHook is IPWNLenderRepaymentHook {
    using MultiToken for address;
    using MultiToken for MultiToken.Asset;

    error DataMustBeEmpty();

    function onLoanRepaid(
        address lender,
        address creditAddress,
        uint256 repayment,
        bytes calldata lenderData
    ) external returns (bytes32) {
        if (lenderData.length != 0) revert DataMustBeEmpty();
        creditAddress.ERC20(repayment).transferAssetFrom(address(this), lender);
        return LENDER_REPAYMENT_HOOK_RETURN_VALUE;
    }

}
