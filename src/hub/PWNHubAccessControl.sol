// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "./PWNHub.sol";
import "./PWNHubTags.sol";


abstract contract PWNHubAccessControl {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    PWNHub immutable internal hub;


    /*----------------------------------------------------------*|
    |*  # MODIFIERS                                             *|
    |*----------------------------------------------------------*/

    modifier onlyActiveLoan() {
        require(hub.hasTag(msg.sender, PWNHubTags.ACTIVE_LOAN), "Caller is not active loan");
        _;
    }

    modifier onlyLoan() {
        require(hub.hasTag(msg.sender, PWNHubTags.LOAN), "Caller is not loan contract");
        _;
    }

    modifier onlyLoanOffer() {
        require(hub.hasTag(msg.sender, PWNHubTags.LOAN_OFFER), "Caller is not loan offer");
        _;
    }


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(address pwnHub) {
        hub = PWNHub(pwnHub);
    }

}
