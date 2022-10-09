// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "openzeppelin-contracts/contracts/access/Ownable.sol";


/**
 * @title PWN Config
 * @notice Contract holding configurable values of PWN protocol.
 */
contract PWNConfig is Ownable {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    /**
     * @notice Protocol fee value in basis points.
     * @dev Value of 100 is 1% fee.
     */
    uint16 public fee;


    /*----------------------------------------------------------*|
    |*  # EVENTS & ERRORS DEFINITIONS                           *|
    |*----------------------------------------------------------*/

    /**
     * @dev Emitted when new fee value is set.
     */
    event FeeUpdated(uint16 oldFee, uint16 newFee);


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(uint16 _fee) Ownable() {
        fee = _fee;
        emit FeeUpdated(0, _fee);
    }


    /*----------------------------------------------------------*|
    |*  # CONFIG MANAGEMENT                                     *|
    |*----------------------------------------------------------*/

    /**
     * @notice Set new protocol fee value.
     * @dev Only contract owner can call this function.
     * @param _fee New fee value in basis points. Value of 100 is 1% fee.
     */
    function setFee(uint16 _fee) external onlyOwner {
        uint16 oldFee = fee;
        fee = _fee;
        emit FeeUpdated(oldFee, _fee);
    }

}
