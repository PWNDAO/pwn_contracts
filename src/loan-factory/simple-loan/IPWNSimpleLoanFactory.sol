// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

import "../../loan/PWNSimpleLoan.sol";


interface IPWNSimpleLoanFactory {
    function createLOAN(
        address caller,
        bytes calldata loanFactoryData,
        bytes calldata signature
    ) external returns (PWNSimpleLoan.LOAN memory, address, address);
}
