// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { PWNInstallmentsLoan } from "pwn/loan/terms/simple/loan/PWNInstallmentsLoan.sol";


contract PWNInstallmentsLoanHarness is PWNInstallmentsLoan {

    constructor(
        address _hub,
        address _loanToken,
        address _config,
        address _categoryRegistry
    ) PWNInstallmentsLoan(_hub, _loanToken, _config, _categoryRegistry) {}


    function exposed_debtLimitTangent(uint256 principalAmount, uint256 fixedInterestAmount, uint256 duration) external pure returns (uint256) {
        return _debtLimitTangent(principalAmount, fixedInterestAmount, duration);
    }

}
