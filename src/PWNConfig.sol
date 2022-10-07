// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "openzeppelin-contracts/contracts/access/Ownable.sol";


contract PWNConfig is Ownable {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    /// Fee size in basis points
    /// 100 -> 1%
    uint16 public fee;


    /*----------------------------------------------------------*|
    |*  # EVENTS & ERRORS DEFINITIONS                           *|
    |*----------------------------------------------------------*/

    event FeeUpdated(uint16 indexed oldFee, uint16 indexed newFee);


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(uint16 _fee) Ownable() {
        fee = _fee;
        emit FeeUpdated(0, _fee);
    }


    /*----------------------------------------------------------*|
    |*  # SETTERS                                               *|
    |*----------------------------------------------------------*/

    function setFee(uint16 _fee) external onlyOwner {
        uint16 oldFee = fee;
        fee = _fee;
        emit FeeUpdated(oldFee, _fee);
    }

}
