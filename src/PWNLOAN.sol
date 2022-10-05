// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

import "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

import "./hub/PWNHubAccessControl.sol";


contract PWNLOAN is PWNHubAccessControl, ERC721 {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    uint256 public lastLoanId;

    mapping (uint256 => address) public loanManagerContract;


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(address hub) PWNHubAccessControl(hub) ERC721("PWN LOAN", "LOAN") {

    }


    /*----------------------------------------------------------*|
    |*  # TOKEN LIFECYCLE                                       *|
    |*----------------------------------------------------------*/

    function mint(address owner) external onlyActiveLoan returns (uint256 loanId) {
        loanId = ++lastLoanId;
        loanManagerContract[loanId] = msg.sender;
        _mint(owner, loanId);
        // TODO: Emit
    }

    function burn(uint256 loanId) external onlyLoan {
        require(loanManagerContract[loanId] == msg.sender, "Loan manager did not mint given loan id");
        delete loanManagerContract[loanId];
        _burn(loanId);
        // TODO: Emit
    }

}
