// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";


/**
 * @title PWN Config
 * @notice Contract holding configurable values of PWN protocol.
 * @dev Is intendet to be used as a proxy via `TransparentUpgradeableProxy`.
 */
contract PWNConfig is Ownable, Initializable {

    string internal constant VERSION = "0.1.0";

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

    function initialize(uint16 _fee, address _owner) initializer public {
        _transferOwnership(_owner);
        _setFee(_fee);
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
        _setFee(_fee);
    }

    function _setFee(uint16 _fee) private {
        uint16 oldFee = fee;
        fee = _fee;
        emit FeeUpdated(oldFee, _fee);
    }

}
