// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { ERC721 } from "openzeppelin/token/ERC721/ERC721.sol";

import { PWNHubAccessControl } from "pwn/hub/PWNHubAccessControl.sol";
import { IERC5646 } from "pwn/interfaces/IERC5646.sol";
import { IPWNLoanMetadataProvider } from "pwn/interfaces/IPWNLoanMetadataProvider.sol";
import { InvalidLoanContractCaller } from "pwn/PWNErrors.sol";


/**
 * @title PWN LOAN token
 * @notice A LOAN token representing a loan in PWN protocol.
 * @dev Token doesn't hold any loan logic, just an address of a loan contract that minted the LOAN token.
 *      PWN LOAN token is shared between all loan contracts.
 */
contract PWNLOAN is PWNHubAccessControl, IERC5646, ERC721 {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    /**
     * @dev Last used LOAN id. First LOAN id is 1. This value is incremental.
     */
    uint256 public lastLoanId;

    /**
     * @dev Mapping of a LOAN id to a loan contract that minted the LOAN token.
     */
    mapping (uint256 => address) public loanContract;


    /*----------------------------------------------------------*|
    |*  # EVENTS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /**
     * @notice Emitted when a new LOAN token is minted.
     */
    event LOANMinted(uint256 indexed loanId, address indexed loanContract, address indexed owner);

    /**
     * @notice Emitted when a LOAN token is burned.
     */
    event LOANBurned(uint256 indexed loanId);


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(address hub) PWNHubAccessControl(hub) ERC721("PWN LOAN", "LOAN") {

    }


    /*----------------------------------------------------------*|
    |*  # TOKEN LIFECYCLE                                       *|
    |*----------------------------------------------------------*/

    /**
     * @notice Mint a new LOAN token.
     * @dev Only an address with associated `ACTIVE_LOAN` tag in PWN Hub can call this function.
     * @param owner Address of a LOAN token receiver.
     * @return loanId Id of a newly minted LOAN token.
     */
    function mint(address owner) external onlyActiveLoan returns (uint256 loanId) {
        loanId = ++lastLoanId;
        loanContract[loanId] = msg.sender;
        _mint(owner, loanId);
        emit LOANMinted(loanId, msg.sender, owner);
    }

    /**
     * @notice Burn a LOAN token.
     * @dev Any address that is associated with given loan id can call this function.
     *      It is enabled to let deprecated loan contracts repay and claim existing loans.
     * @param loanId Id of a LOAN token to be burned.
     */
    function burn(uint256 loanId) external {
        if (loanContract[loanId] != msg.sender)
            revert InvalidLoanContractCaller();

        delete loanContract[loanId];
        _burn(loanId);
        emit LOANBurned(loanId);
    }


    /*----------------------------------------------------------*|
    |*  # METADATA                                              *|
    |*----------------------------------------------------------*/

    /**
     * @notice Return a LOAN token metadata uri base on a loan contract that minted the token.
     * @param tokenId Id of a LOAN token.
     * @return Metadata uri for given token id (loan id).
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireMinted(tokenId);

        return IPWNLoanMetadataProvider(loanContract[tokenId]).loanMetadataUri();
    }


    /*----------------------------------------------------------*|
    |*  # ERC5646                                               *|
    |*----------------------------------------------------------*/

    /**
     * @dev See {IERC5646-getStateFingerprint}.
     */
    function getStateFingerprint(uint256 tokenId) external view virtual override returns (bytes32) {
        address _loanContract = loanContract[tokenId];

        if (_loanContract == address(0))
            return bytes32(0);

        return IERC5646(_loanContract).getStateFingerprint(tokenId);
    }


    /*----------------------------------------------------------*|
    |*  # ERC165                                                *|
    |*----------------------------------------------------------*/

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId) ||
            interfaceId == type(IERC5646).interfaceId;
    }

}
