// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

import "./PWNVault.sol";
import "./PWNLoan.sol";
import "@pwnfinance/multitoken/contracts/MultiToken.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PWN is Ownable {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    PWNLoan public loan;
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
     * @dev For the set up to work both PWNLoan & PWNVault contracts have to called via `.setPWN(PWN.address)`
     * @param _PWNL Address of the PWNLoan contract - defines LOAN tokens
     * @param _PWNV Address of the PWNVault contract - holds assets
     */
    constructor(
        address _PWNL,
        address _PWNV
    ) Ownable() {
        loan = PWNLoan(_PWNL);
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
        loan.revokeOffer(_offerHash, _signature, msg.sender);

        return true;
    }

    /**
     * createLoan
     * @notice Borrower can accept existing signed off-chain offer
     * @dev A UI should do an off-chain balance check on the lender side to make sure the call won't throw
     * @dev Loan asset has to be an ERC20 token, otherwise will transaction fail
     * @param _offer Offer struct with plain offer data. See { PWNLoan.sol }
     * @param _signature Offer typed struct signed by lender
     * @return True if successful
     */
    function createLoan(
        PWNLoan.Offer memory _offer,
        bytes memory _signature
    ) external returns (bool) {
        loan.create(_offer, _signature, msg.sender);

        MultiToken.Asset memory collateral = MultiToken.Asset(
            _offer.collateralAddress,
            _offer.collateralCategory,
            _offer.collateralAmount,
            _offer.collateralId
        );

        MultiToken.Asset memory loanAsset = MultiToken.Asset(
            _offer.loanAssetAddress,
            MultiToken.Category.ERC20,
            _offer.loanAmount,
            0
        );

        vault.pull(collateral, msg.sender);
        vault.pushFrom(loanAsset, _offer.lender, msg.sender);

        return true;
    }

    /**
     * createLoanFlexible
     * @notice Borrower can accept existing signed off-chain flexible offer
     * @dev A UI should do an off-chain balance check on the lender side to make sure the call won't throw
     * @dev Loan asset has to be an ERC20 token, otherwise will transaction fail
     * @param _offer Flexible offer struct with plain flexible offer data. See { PWNLoan.sol }
     * @param _offerValues Concrete values of a flexible offer set by borrower. See { PWNLoan.sol }
     * @param _signature Flexible offer typed struct signed by lender
     * @return True if successful
     */
    function createLoanFlexible(
        PWNLoan.FlexibleOffer memory _offer,
        PWNLoan.FlexibleOfferValues memory _offerValues,
        bytes memory _signature
    ) external returns (bool) {
        loan.createFlexible(_offer, _offerValues, _signature, msg.sender);

        MultiToken.Asset memory collateral = MultiToken.Asset(
            _offer.collateralAddress,
            _offer.collateralCategory,
            _offer.collateralAmount,
            _offerValues.collateralId
        );

        MultiToken.Asset memory loanAsset = MultiToken.Asset(
            _offer.loanAssetAddress,
            MultiToken.Category.ERC20,
            _offerValues.loanAmount,
            0
        );

        vault.pull(collateral, msg.sender);
        vault.pushFrom(loanAsset, _offer.lender, msg.sender);

        return true;
    }

    /**
     * repayLoan
     * @notice The borrower can pay back the loan through this function
     * @dev The function assumes the asset (and amount to be paid back) to be returned is approved for PWNVault
     * @dev The function assumes the borrower has the full amount to be paid back in their account
     * @param _loanId LOAN ID of the loan being paid back
     * @return True if successful
     */
    function repayLoan(uint256 _loanId) external returns (bool) {
        loan.repayLoan(_loanId);

        MultiToken.Asset memory loanAsset = loan.getLoan(_loanId);
        loanAsset.amount = loan.getLoanRepayAmount(_loanId);

        vault.pull(loanAsset, msg.sender);
        vault.push(loan.getCollateral(_loanId), loan.getBorrower(_loanId));

        return true;
    }

    /**
     * claimLoan
     * @dev The current LOAN owner can call this function if the loan is expired or paied back
     * @param _loanId LOAN ID of the loan to be claimed
     * @return True if successful
     */
    function claimLoan(uint256 _loanId) external returns (bool) {
        uint8 status = loan.getStatus(_loanId);

        loan.claim(_loanId, msg.sender);

        if (status == 3) {
            MultiToken.Asset memory loanAsset = loan.getLoan(_loanId);
            loanAsset.amount = loan.getLoanRepayAmount(_loanId);

            vault.push(loanAsset, msg.sender);
        } else if (status == 4) {
            vault.push(loan.getCollateral(_loanId), msg.sender);
        }

        loan.burn(_loanId, msg.sender);

        return true;
    }

}
