// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "@pwn/hub/PWNHub.sol";
import "@pwn/hub/PWNHubTags.sol";


/**
 * @title PWN Hub Access Control
 * @notice Implement modifiers for PWN Hub access control.
 */
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
