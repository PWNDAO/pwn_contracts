// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";


interface IPWNBorrowerCreateHook {
    /** @dev Must return keccak of "PWNBorrowerCreateHook.onLoanCreated"*/
    function onLoanCreated(
        address borrower,
        MultiToken.Asset calldata collateral,
        address creditAddress,
        uint256 principal,
        bytes calldata borrowerData
    ) external returns (bytes32);
}
