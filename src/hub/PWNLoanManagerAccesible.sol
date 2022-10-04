// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

import "./PWNHub.sol";
import "./PWNHubTags.sol";


abstract contract PWNLoanManagerAccesible {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    PWNHub immutable internal hub;


    /*----------------------------------------------------------*|
    |*  # MODIFIERS                                             *|
    |*----------------------------------------------------------*/

    modifier onlyActiveLoanManager() {
        require(hub.hasTag(msg.sender, PWNHubTags.ACTIVE_LOAN_MANAGER), "Caller is not active loan manager");
        _;
    }

    modifier onlyLoanManager() {
        require(hub.hasTag(msg.sender, PWNHubTags.LOAN_MANAGER), "Caller is not loan manager");
        _;
    }


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(address pwnHub) {
        hub = PWNHub(pwnHub);
    }

}
