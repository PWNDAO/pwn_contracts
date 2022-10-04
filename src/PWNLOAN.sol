// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

import "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

import "./hub/PWNLoanManagerAccesible.sol";


contract PWNLOAN is PWNLoanManagerAccesible, ERC721 {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    uint256 public id;

    mapping (uint256 => address) public loanManagerContract;


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(address pwnHub) PWNLoanManagerAccesible(pwnHub) ERC721("PWN LOAN", "LOAN") {

    }


    /*----------------------------------------------------------*|
    |*  # TOKEN LIFECYCLE                                       *|
    |*----------------------------------------------------------*/

    function mint(address owner) external onlyActiveLoanManager returns (uint256 loanId) {
        loanId = ++id;
        loanManagerContract[loanId] = msg.sender;
        _mint(owner, loanId);
    }

    function burn(uint256 loanId) external onlyLoanManager {
        require(loanManagerContract[loanId] == msg.sender, "Loan manager did not mint given loan id");
        delete loanManagerContract[loanId];
        _burn(loanId);
    }

}
