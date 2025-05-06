// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

interface IPWNDefaultModule {
    function isDefaulted(address loanContract, uint256 loanId) external view returns (bool);

    /** @dev Must return keccak of "PWNDefaultModule.onLoanCreated"*/
    function onLoanCreated(uint256 loanId, bytes calldata proposerData) external returns (bytes32);
}
