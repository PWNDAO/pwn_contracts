// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

interface IPWNInterestModule {
    function interest(address loanContract, uint256 loanId) external view returns (uint256);
    function debt(address loanContract, uint256 loanId) external view returns (uint256);

    /** @dev Must return keccak of "PWNInterestModule.onLoanCreated"*/
    function onLoanCreated(uint256 loanId, bytes calldata proposerData) external returns (bytes32);
}
