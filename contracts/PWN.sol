// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.4;

import "./PWNVault.sol";
import "./PWNDeed.sol";
import "@pwnfinance/multitoken/contracts/MultiToken.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PWN is Ownable {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    PWNDeed public deed;
    PWNVault public vault;

    /*----------------------------------------------------------*|
    |*  # EVENTS & ERRORS DEFINITIONS                           *|
    |*----------------------------------------------------------*/

    // No events nor error defined

    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR & FUNCTIONS                               *|
    |*----------------------------------------------------------*/

    /**
     * Constructor
     * @dev establishes a connection with other pre-deployed components
     * @dev for the set up to work both PWNDeed & PWNVault contracts have to called via `.setPWN(PWN.address)`
     * @param _PWND Address of the PWNDeed contract - defines Deed tokens
     * @param _PWNV Address of the PWNVault contract - holds assets
     */
    constructor(
        address _PWND,
        address _PWNV
    ) Ownable() {
        deed = PWNDeed(_PWND);
        vault = PWNVault(_PWNV);
    }

    /**
     * createDeed - sets & locks collateral
     * @dev for UI integrations is this the function enabling creation of a new Deed token
     * @param _assetAddress Address of the asset contract
     * @param _assetCategory Category of the asset - see { MultiToken.sol }
     * @param _duration Loan duration in seconds
     * @param _assetId ID of an ERC721 or ERC1155 token || 0 in case the token doesn't have IDs
     * @param _assetAmount Amount of an ERC20 or ERC1155 token || 0 in case of NFTs
     * @return a Deed ID of the newly created Deed
     */
    function createDeed(
        address _assetAddress,
        MultiToken.Category _assetCategory,
        uint32 _duration,
        uint256 _assetId,
        uint256 _assetAmount
    ) external returns (uint256) {
        uint256 did = deed.create(_assetAddress, _assetCategory, _duration, _assetId, _assetAmount, msg.sender);
        vault.push(deed.getDeedCollateral(did), msg.sender);

        return did;
    }

    /**
     * revokeDeed
     * @dev through this function the borrower can delete the Deed token given no offer was accepted
     * @param _did Deed ID specifying the concrete Deed
     */
    function revokeDeed(uint256 _did) external {
        deed.revoke(_did, msg.sender);
        vault.pull(deed.getDeedCollateral(_did), msg.sender);

        deed.burn(_did, msg.sender);
    }

    /**
     * makeOffer
     * @dev this is the function used by lenders to cast their offers
     * @dev this function doesn't assume the asset is approved yet for PWNVault
     * @dev this function requires lender to have a sufficient balance
     * @param _assetAddress Address of the asset contract
     * @param _assetAmount Amount of an ERC20 token to be offered as loan
     * @param _did ID of the Deed the offer should be bound to
     * @param _toBePaid Amount to be paid back by the borrower
     * @return a hash of the newly created offer
     */
    function makeOffer(
        address _assetAddress,
        uint256 _assetAmount,
        uint256 _did,
        uint256 _toBePaid
    ) external returns (bytes32) {
        return deed.makeOffer(_assetAddress, _assetAmount, msg.sender, _did, _toBePaid);
    }

    /**
     * revokeOffer
     * @dev this is the function lenders can use to remove their offers on Deeds they are in the stage of getting offers
     * @param _offer Identifier of the offer to be revoked
     */
    function revokeOffer(bytes32 _offer) external {
        deed.revokeOffer(_offer, msg.sender);
    }

    /**
     * acceptOffer
     * @dev through this function a borrower can accept an existing offer
     * @dev a UI should do an off-chain balance check on the lender side to make sure the call won't throw
     * @param _offer Identifier of the offer to be accepted
     * @return true if successful
     */
    function acceptOffer(bytes32 _offer) external returns (bool) {
        uint256 did = deed.getDeedID(_offer);
        deed.acceptOffer(did, _offer, msg.sender);

        address lender = deed.getLender(_offer);
        vault.pullProxy(deed.getOfferLoan(_offer), lender, msg.sender);

        MultiToken.Asset memory collateral;
        collateral.category = MultiToken.Category.ERC1155;
        collateral.id = did;
        collateral.assetAddress = address(deed);
        vault.pullProxy(collateral, msg.sender, lender);

        return true;
    }

    /**
     * repayLoan
     * @dev the borrower can pay back the funds through this function
     * @dev the function assumes the asset (and amount to be paid back) to be returned is approved for PWNVault
     * @dev the function assumes the borrower has the full amount to be paid back in their account
     * @param _did Deed ID of the deed being paid back
     * @return true if successful
     */
    function repayLoan(uint256 _did) external returns (bool) {
        deed.repayLoan(_did);

        bytes32 offer = deed.getAcceptedOffer(_did);
        MultiToken.Asset memory loan = deed.getOfferLoan(offer);
        loan.amount = deed.toBePaid(offer);  //override the num of loan given

        vault.pull(deed.getDeedCollateral(_did), deed.getBorrower(_did));
        vault.push(loan, msg.sender);

        return true;
    }

    /**
     * claim Deed
     * @dev The current Deed owner can call this function if the Deed is expired or payed back
     * @param _did Deed ID of the deed to be claimed
     * @return true if successful
     */
    function claimDeed(uint256 _did) external returns (bool) {
        uint8 status = deed.getDeedStatus(_did);

        deed.claim(_did, msg.sender);

        if (status == 3) {
            bytes32 offer = deed.getAcceptedOffer(_did);
            MultiToken.Asset memory loan = deed.getOfferLoan(offer);
            loan.amount = deed.toBePaid(offer);

            vault.pull(loan, msg.sender);

        } else if (status == 4) {
            vault.pull(deed.getDeedCollateral(_did), msg.sender);
        }

        deed.burn(_did, msg.sender);

        return true;
    }

}
