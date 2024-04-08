// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Ownable2Step } from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { Initializable } from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";

import { IStateFingerpringComputer } from "@pwn/state-fingerprint-computer/IStateFingerpringComputer.sol";
import "@pwn/PWNErrors.sol";


/**
 * @title PWN Config
 * @notice Contract holding configurable values of PWN protocol.
 * @dev Is intendet to be used as a proxy via `TransparentUpgradeableProxy`.
 */
contract PWNConfig is Ownable2Step, Initializable {

    string internal constant VERSION = "1.2";

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
     *      If there is no metadata uri for a loan contract, default metadata uri will be used stored under address(0).
     */
    mapping (address => string) private _loanMetadataUri;

    /**
     * @notice Mapping holding registered computer to an asset.
     * @dev Only owner can update the mapping.
     */
    mapping (address => address) private _computerRegistry;

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
    event LOANMetadataUriUpdated(address indexed loanContract, string newUri);

    /**
     * @dev Emitted when new default LOAN token metadata uri is set.
     */
    event DefaultLOANMetadataUriUpdated(string newUri);

    /**
     * @notice Error emitted when registering a computer which does not support the asset it is registered for.
     */
    error InvalidComputerContract();

    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor() Ownable2Step() {
        // PWNConfig is used as a proxy. Use initializer to setup initial properties.
        _disableInitializers();
        _transferOwnership(address(0));
    }

    function initialize(address _owner, uint16 _fee, address _feeCollector) external initializer {
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
        if (_feeCollector == address(0))
            revert InvalidFeeCollector();

        address oldFeeCollector = feeCollector;
        feeCollector = _feeCollector;
        emit FeeCollectorUpdated(oldFeeCollector, _feeCollector);
    }


    /*----------------------------------------------------------*|
    |*  # LOAN METADATA                                         *|
    |*----------------------------------------------------------*/

    /**
     * @notice Set a LOAN token metadata uri for a specific loan contract.
     * @param loanContract Address of a loan contract.
     * @param metadataUri New value of LOAN token metadata uri for given `loanContract`.
     */
    function setLOANMetadataUri(address loanContract, string memory metadataUri) external onlyOwner {
        if (loanContract == address(0))
            // address(0) is used as a default metadata uri. Use `setDefaultLOANMetadataUri` to set default metadata uri.
            revert ZeroLoanContract();

        _loanMetadataUri[loanContract] = metadataUri;
        emit LOANMetadataUriUpdated(loanContract, metadataUri);
    }

    /**
     * @notice Set a default LOAN token metadata uri.
     * @param metadataUri New value of default LOAN token metadata uri.
     */
    function setDefaultLOANMetadataUri(string memory metadataUri) external onlyOwner {
        _loanMetadataUri[address(0)] = metadataUri;
        emit DefaultLOANMetadataUriUpdated(metadataUri);
    }

    /**
     * @notice Return a LOAN token metadata uri base on a loan contract that minted the token.
     * @param loanContract Address of a loan contract.
     * @return uri Metadata uri for given loan contract.
     */
    function loanMetadataUri(address loanContract) external view returns (string memory uri) {
        uri = _loanMetadataUri[loanContract];
        // If there is no metadata uri for a loan contract, use default metadata uri.
        if (bytes(uri).length == 0)
            uri = _loanMetadataUri[address(0)];
    }


    /*----------------------------------------------------------*|
    |*  # STATE FINGERPRINT COMPUTER                            *|
    |*----------------------------------------------------------*/

    /**
     * @notice Returns the state fingerprint computer for a given asset.
     * @param asset The asset for which the computer is requested.
     * @return The computer for the given asset.
     */
    function getStateFingerprintComputer(address asset) external view returns (IStateFingerpringComputer) {
        return IStateFingerpringComputer(_computerRegistry[asset]);
    }

    /**
     * @notice Registers a state fingerprint computer for a given asset.
     * @param asset The asset for which the computer is registered.
     * @param computer The computer to be registered. Use address(0) to remove a computer.
     */
    function registerStateFingerprintComputer(address asset, address computer) external onlyOwner {
        if (computer != address(0))
            if (!IStateFingerpringComputer(computer).supportsToken(asset))
                revert InvalidComputerContract();

        _computerRegistry[asset] = computer;
    }

}
