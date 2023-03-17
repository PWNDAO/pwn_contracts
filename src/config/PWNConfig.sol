// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";

import "@pwn/PWNErrors.sol";


/**
 * @title PWN Config
 * @notice Contract holding configurable values of PWN protocol.
 * @dev Is intendet to be used as a proxy via `TransparentUpgradeableProxy`.
 */
contract PWNConfig is Ownable2Step, Initializable {

    string internal constant VERSION = "1.0";

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    uint16 public constant MAX_FEE = 1000; // 10%

    /**
     * @notice Protocol fee value in basis points.
     * @dev Value of 100 is 1% fee.
     */
    uint16 public fee;

    /**
     * @notice Address that collects protocol fees.
     */
    address public feeCollector;

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
     * @dev Emitted when new fee collector address is set.
     */
    event FeeCollectorUpdated(address oldFeeCollector, address newFeeCollector);

    /**
     * @dev Emitted when new LOAN token metadata uri is set.
     */
    event LoanMetadataUriUpdated(address indexed loanContract, string newUri);


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor() Ownable2Step() {

    }

    function initialize(address _owner) initializer external {
        require(_owner != address(0), "Owner is zero address");
        _transferOwnership(_owner);
    }

    function reinitialize(address _owner, uint16 _fee, address _feeCollector) reinitializer(2) onlyOwner external {
        require(_owner != address(0), "Owner is zero address");
        _transferOwnership(_owner);

        require(_feeCollector != address(0), "Fee collector is zero address");
        _setFeeCollector(_feeCollector);

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
        if (_fee > MAX_FEE)
            revert InvalidFeeValue();

        uint16 oldFee = fee;
        fee = _fee;
        emit FeeUpdated(oldFee, _fee);
    }

    /**
     * @notice Set new fee collector address.
     * @dev Only contract owner can call this function.
     * @param _feeCollector New fee collector address.
     */
    function setFeeCollector(address _feeCollector) external onlyOwner {
        _setFeeCollector(_feeCollector);
    }

    function _setFeeCollector(address _feeCollector) private {
        address oldFeeCollector = feeCollector;
        feeCollector = _feeCollector;
        emit FeeCollectorUpdated(oldFeeCollector, _feeCollector);
    }


    /*----------------------------------------------------------*|
    |*  # LOAN METADATA MANAGEMENT                              *|
    |*----------------------------------------------------------*/

    /**
     * @notice Set a LOAN token metadata uri for a specific loan contract.
     * @param loanContract Address of a loan contract.
     * @param metadataUri New value of LOAN token metadata uri for given `loanContract`.
     */
    function setLoanMetadataUri(address loanContract, string memory metadataUri) external onlyOwner {
        loanMetadataUri[loanContract] = metadataUri;
        emit LoanMetadataUriUpdated(loanContract, metadataUri);
    }

}
