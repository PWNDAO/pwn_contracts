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

    /**
     * @notice Mapping of a loan contract address to LOAN token metadata uri.
     * @dev LOAN token minted by a loan contract will return metadata uri stored in this mapping.
     */
    mapping (address => string) public loanMetadataUri;


    /*----------------------------------------------------------*|
    |*  # EVENTS & ERRORS DEFINITIONS                           *|
    |*----------------------------------------------------------*/

    /**
     * @dev Emitted when new fee value is set.
     */
    event FeeUpdated(uint16 oldFee, uint16 newFee);

    /**
     * @dev Emitted when new LOAN token metadata uri is set.
     */
    event LoanMetadataUriUpdated(address indexed loanContract, string newUri);


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    function initialize(address _owner, uint16 _fee) initializer public {
        _transferOwnership(_owner);
        _setFee(_fee);
    }


    /*----------------------------------------------------------*|
    |*  # FEE MANAGEMENT                                        *|
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


    /*----------------------------------------------------------*|
    |*  # LOAN METADATA MANAGEMENT                              *|
    |*----------------------------------------------------------*/

    /**
     * @notice Set a LOAN token metadta uri for a specific loan contract.
     * @param loanContract Address of a loan contract.
     * @param metadataUri New value of LOAN token metadata uri for given `loanContract`.
     */
    function setLoanMetadataUri(address loanContract, string memory metadataUri) external onlyOwner {
        loanMetadataUri[loanContract] = metadataUri;
        emit LoanMetadataUriUpdated(loanContract, metadataUri);
    }

}
