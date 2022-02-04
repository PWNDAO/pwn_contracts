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
     * @dev Establishes a connection with other pre-deployed components
     * @dev For the set up to work both PWNDeed & PWNVault contracts have to called via `.setPWN(PWN.address)`
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
     * revokeOffer
     * @notice Lender can use this function to revoke their off-chain offers
     * @dev Can be called only from address that signed the offer
     * @param _offerHash Offer typed struct hash
     * @param _signature Offer typed struct signature
     * @return True if successful
     */
    function revokeOffer(
        bytes32 _offerHash,
        bytes calldata _signature
    ) external returns (bool) {
        deed.revokeOffer(_offerHash, _signature, msg.sender);

        return true;
    }

    // TODO: Doc
    function createDeed(
        PWNDeed.Offer memory _offer,
        bytes memory _signature
    ) external returns (bool) {
        deed.create(_offer, _signature, msg.sender);

        MultiToken.Asset memory collateral = MultiToken.Asset(
            _offer.collateralAddress,
            _offer.collateralCategory,
            _offer.collateralAmount,
            _offer.collateralId
        );

        MultiToken.Asset memory loan = MultiToken.Asset(
            _offer.loanAssetAddress,
            MultiToken.Category.ERC20,
            _offer.loanAmount,
            0
        );

        vault.pull(collateral, msg.sender);
        vault.pushFrom(loan, _offer.lender, msg.sender);

        return true;
    }

    // TODO: Doc
    function createDeedFlexible(
        PWNDeed.FlexibleOffer memory _offer,
        PWNDeed.OfferInstance memory _offerInstance,
        bytes memory _signature
    ) external returns (bool) {
        deed.createFlexible(_offer, _offerInstance, _signature, msg.sender);

        MultiToken.Asset memory collateral = MultiToken.Asset(
            _offer.collateralAddress,
            _offer.collateralCategory,
            _offer.collateralAmount,
            _offerInstance.collateralId
        );

        MultiToken.Asset memory loan = MultiToken.Asset(
            _offer.loanAssetAddress,
            MultiToken.Category.ERC20,
            _offerInstance.loanAmount,
            0
        );

        vault.pull(collateral, msg.sender);
        vault.pushFrom(loan, _offer.lender, msg.sender);

        return true;
    }

    /**
     * repayLoan
     * @notice The borrower can pay back the loan through this function
     * @dev The function assumes the asset (and amount to be paid back) to be returned is approved for PWNVault
     * @dev The function assumes the borrower has the full amount to be paid back in their account
     * @param _did Deed ID of the deed being paid back
     * @return True if successful
     */
    function repayLoan(uint256 _did) external returns (bool) {
        deed.repayLoan(_did);

        MultiToken.Asset memory loan = deed.getLoan(_did);
        loan.amount = deed.getLoanRepayAmount(_did);

        vault.pull(loan, msg.sender);
        vault.push(deed.getCollateral(_did), deed.getBorrower(_did));

        return true;
    }

    /**
     * claimDeed
     * @dev The current Deed owner can call this function if the Deed is expired or paied back
     * @param _did Deed ID of the deed to be claimed
     * @return True if successful
     */
    function claimDeed(uint256 _did) external returns (bool) {
        uint8 status = deed.getStatus(_did);

        deed.claim(_did, msg.sender);

        if (status == 3) {
            MultiToken.Asset memory loan = deed.getLoan(_did);
            loan.amount = deed.getLoanRepayAmount(_did);

            vault.push(loan, msg.sender);
        } else if (status == 4) {
            vault.push(deed.getCollateral(_did), msg.sender);
        }

        deed.burn(_did, msg.sender);

        return true;
    }

}
