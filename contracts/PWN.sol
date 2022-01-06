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
     * @param _offerHash Hash of an encoded offer
     * @param _signature Signature of the eth signed message hash
     * @return True if successful
     */
    function revokeOffer(
        bytes32 _offerHash,
        bytes memory _signature
    ) external returns (bool) {
        deed.revokeOffer(_offerHash, _signature, msg.sender);

        return true;
    }

    /**
     * createDeed
     * @notice Borrower can accept existing signed off-chain offer
     * @dev A UI should do an off-chain balance check on the lender side to make sure the call won't throw
     * @param _collateralAssetAddress Address of an asset used as a collateral
     * @param _collateralCategory Category of an asset used as a collateral (ERC20, ERC721, ERC1155)
     * @param _collateralAssetId Id of a ERC721 or ERC1155 asset
     * @param _collateralAssetAmount Amount of a ERC20 or ERC1155 asset
     * @param _loanAssetAddress Address of a loan asset
     * @param _loanAssetAmount Amount of a loan asset (can be only ERC20, so category and id are redundant)
     * @param _loanRepayAmount Amount of a loan asset, which borrower has to repay to get his collateral back
     * @param _duration Loan duration in seconds
     * @param _offerExpiration Offer expiration timestamp in seconds
     * @param _lender Address of an offer signer
     * @param _nonce Nonce to help distinguish between otherwise identical offers
     * @param _signature Offer signature signed by lender
     * @return True if successful
     */
    function createDeed(
        address _collateralAssetAddress,
        MultiToken.Category _collateralCategory,
        uint256 _collateralAssetAmount,
        uint256 _collateralAssetId,
        address _loanAssetAddress,
        uint256 _loanAssetAmount,
        uint256 _loanRepayAmount,
        uint32 _duration,
        uint40 _offerExpiration,
        address _lender,
        uint256 _nonce,
        bytes memory _signature
    ) external returns (bool) {
        MultiToken.Asset memory collateral = MultiToken.Asset(
            _collateralAssetAddress,
            _collateralCategory,
            _collateralAssetAmount,
            _collateralAssetId
        );

        MultiToken.Asset memory loan = MultiToken.Asset(
            _loanAssetAddress,
            MultiToken.Category.ERC20,
            _loanAssetAmount,
            0
        );

        PWNDeed.Offer memory offer = PWNDeed.Offer(
            collateral,
            loan,
            _loanRepayAmount,
            _duration,
            _offerExpiration,
            _lender,
            _nonce,
            block.chainid
        );

        deed.create(offer, _signature, msg.sender);

        vault.push(offer.collateral, msg.sender);

        vault.pullProxy(offer.loan, offer.lender, msg.sender);

        return true;
    }

    /**
     * repayLoan
     * @notice The borrower can pay back the funds through this function
     * @dev The function assumes the asset (and amount to be paid back) to be returned is approved for PWNVault
     * @dev The function assumes the borrower has the full amount to be paid back in their account
     * @param _did Deed ID of the deed being paid back
     * @return True if successful
     */
    function repayLoan(uint256 _did) external returns (bool) {
        deed.repayLoan(_did);

        MultiToken.Asset memory loan = deed.getLoan(_did);
        loan.amount = deed.getLoanRepayAmount(_did);

        vault.pull(deed.getCollateral(_did), deed.getBorrower(_did));
        vault.push(loan, msg.sender);

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

            vault.pull(loan, msg.sender);
        } else if (status == 4) {
            vault.pull(deed.getCollateral(_did), msg.sender);
        }

        deed.burn(_did, msg.sender);

        return true;
    }

}
