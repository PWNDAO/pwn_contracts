// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "MultiToken/MultiToken.sol";

import "../../hub/PWNHub.sol";
import "../../hub/PWNHubTags.sol";
import "../../loan-factory/simple-loan/IPWNSimpleLoanFactory.sol";
import "../../PWNConfig.sol";
import "../PWNVault.sol";
import "../PWNLOAN.sol";


contract PWNSimpleLoan is PWNVault {

    string internal constant VERSION = "0.1.0";

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    // TODO: Doc
    PWNHub immutable internal hub;
    // TODO: Doc
    PWNLOAN immutable internal loanToken;
    // TODO: Doc
    PWNConfig immutable internal config;

    /**
     * Struct defining a LOAN
     * @param status 0 == none/dead || 2 == running/accepted offer || 3 == paid back || 4 == expired
     * @param borrower Address of the borrower - stays the same for entire lifespan of the token
     * @param duration Loan duration in seconds
     * @param expiration Unix timestamp (in seconds) setting up the default deadline
     * @param collateral Asset used as a loan collateral. Consisting of another `Asset` struct defined in the MultiToken library
     * @param asset Asset to be borrowed by lender to borrower. Consisting of another `Asset` struct defined in the MultiToken library
     * @param loanRepayAmount Amount of LOAN asset to be repaid
     */
    struct LOAN {
        uint8 status;
        address borrower;
        uint32 duration;
        uint40 expiration;
        MultiToken.Asset collateral;
        MultiToken.Asset asset;
        uint256 loanRepayAmount;
    }

    /**
     * Mapping of all LOAN data by loan id
     */
    mapping (uint256 => LOAN) public LOANs;


    /*----------------------------------------------------------*|
    |*  # EVENTS & ERRORS DEFINITIONS                           *|
    |*----------------------------------------------------------*/

    // TODO: Update for Dune
    event LOANCreated(uint256 indexed loanId, address indexed lender);
    event LOANPaidBack(uint256 loanId);
    event LOANClaimed(uint256 loanId);


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(address _hub, address _loanToken, address _config) {
        hub = PWNHub(_hub);
        loanToken = PWNLOAN(_loanToken);
        config = PWNConfig(_config);
    }


    /*----------------------------------------------------------*|
    |*  # CREATE LOAN                                           *|
    |*----------------------------------------------------------*/

    // TODO: Doc
    function createLOAN(
        address loanFactoryContract,
        bytes calldata loanFactoryData,
        bytes calldata signature,
        bytes calldata loanAssetPermit,
        bytes calldata collateralPermit
    ) external returns (uint256 loanId) {
        // Check that loan factory contract is tagged in PWNHub
        require(hub.hasTag(loanFactoryContract, PWNHubTags.LOAN_FACTORY), "Given contract is not loan factory");

        // Build LOAN by loan factory
        (LOAN memory loan, address lender, address borrower) = IPWNSimpleLoanFactory(loanFactoryContract).createLOAN({
            caller: msg.sender,
            loanFactoryData: loanFactoryData,
            signature: signature
        });

        // Mint LOAN token for lender
        loanId = loanToken.mint(lender);

        // Store loan data under loan id
        LOANs[loanId] = loan;

        emit LOANCreated(loanId, lender);

        // TODO: Work with fee

        // Transfer collateral to Vault
        _pull(loan.collateral, borrower, collateralPermit);
        // Transfer loan asset to borrower
        _pushFrom(loan.asset, lender, borrower, loanAssetPermit);
    }


    /*----------------------------------------------------------*|
    |*  # REPAY LOAN                                            *|
    |*----------------------------------------------------------*/

    // TODO: Doc
    function repayLoan(
        uint256 loanId,
        bytes calldata loanAssetPermit
    ) external {
        LOAN storage loan = LOANs[loanId];
        uint8 status = loan.status;

        // Check that loan is not from a different loan contract
        require(status != 0, "Loan does not exist or is not from current loan contract");

        // Check that loan running
        require(status == 2, "Loan is not running");

        // Check that loan is not expired
        require(loan.expiration > block.timestamp, "Loan is expired");

        // Move loan to repaid state
        loan.status = 3;

        // Transfer repaid amount of loan asset to Vault
        MultiToken.Asset memory repayLoanAsset = loan.asset;
        repayLoanAsset.amount = loan.loanRepayAmount;
        _pull(repayLoanAsset, msg.sender, loanAssetPermit);

        // Transfer collateral back to borrower
        _push(loan.collateral, loan.borrower);

        emit LOANPaidBack(loanId);
    }


    /*----------------------------------------------------------*|
    |*  # CLAIM LOAN                                            *|
    |*----------------------------------------------------------*/

    // TODO: Doc
    function claimLoan(uint256 loanId) external {
        LOAN storage loan = LOANs[loanId];

        // Check that caller is LOAN token holder
        require(loanToken.ownerOf(loanId) == msg.sender, "Caller is not a LOAN token holder");

        // Loan has been paid back
        if (loan.status == 3) {
            MultiToken.Asset memory loanAsset = MultiToken.Asset({
                category: loan.asset.category,
                assetAddress: loan.asset.assetAddress,
                id: loan.asset.id,
                amount: loan.loanRepayAmount
            });

            // Delete loan data & burn LOAN token before calling safe transfer
            _deleteLoan(loanId);

            // Transfer repaid loan to lender
            _push(loanAsset, msg.sender);
        }
        // Loan is running but expired
        else if (loan.status == 2 && loan.expiration <= block.timestamp) {
             MultiToken.Asset memory collateral = loan.collateral;

            // Delete loan data & burn LOAN token before calling safe transfer
            _deleteLoan(loanId);

            // Transfer collateral to lender
            _push(collateral, msg.sender);
        }
        // Loan is in wrong state or from different loan contract
        else {
            revert("Loan can't be claimed yet or is not from current loan contract");
        }

        emit LOANClaimed(loanId);
    }

    function _deleteLoan(uint256 loanId) private {
        loanToken.burn(loanId);
        delete LOANs[loanId];
    }

}
