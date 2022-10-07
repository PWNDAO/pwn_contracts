// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

import "../hub/PWNHubAccessControl.sol";


contract PWNLOAN is PWNHubAccessControl, ERC721 {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    uint256 public lastLoanId;

    mapping (uint256 => address) public loanContract;


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
        loanContract[loanId] = msg.sender;
        _mint(owner, loanId);
        // TODO: Emit
    }

    function burn(uint256 loanId) external onlyLoan {
        require(loanContract[loanId] == msg.sender, "Loan contract did not mint given loan id");
        delete loanContract[loanId];
        _burn(loanId);
        // TODO: Emit
    }

}
