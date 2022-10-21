// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "MultiToken/MultiToken.sol";

import "@pwn/config/PWNConfig.sol";
import "@pwn/hub/PWNHub.sol";
import "@pwn/hub/PWNHubTags.sol";
import "@pwn/loan/lib/PWNFeeCalculator.sol";
import "@pwn/loan/PWNVault.sol";
import "@pwn/loan/PWNLOAN.sol";
import "@pwn/loan-factory/simple-loan/IPWNSimpleLoanFactory.sol";
import "@pwn/PWNError.sol";


/**
 * @title PWN Simple Loan
 * @notice Contract managing a simple loan in PWN protocol.
 * @dev Acts as a vault for every loan created by this contract.
 */
contract PWNSimpleLoan is PWNVault, IPWNLoanMetadataProvider {

    string internal constant VERSION = "0.1.0";

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    PWNHub immutable internal hub;
    PWNLOAN immutable internal loanToken;
    PWNConfig immutable internal config;

    /**
     * @notice Struct defining a loan.
     * @param status 0 == none/dead || 2 == running/accepted offer || 3 == paid back || 4 == expired.
     * @param borrower Address of a borrower.
     * @param expiration Unix timestamp (in seconds) setting up a default date.
     * @param loanAssetAddress Address of an asset used as a loan credit.
     * @param loanRepayAmount Amount of a loan asset to be paid back.
     * @param collateral Asset used as a loan collateral. For a definition see { MultiToken dependency lib }.
     */
    struct LOAN {
        uint8 status;
        address borrower;
        uint40 expiration;
        address loanAssetAddress;
        uint256 loanRepayAmount;
        MultiToken.Asset collateral;
    }

    /**
     * @notice Struct defining a loan terms.
     * @dev This struct is created by loan factories and never stored.
     * @param lender Address of a lender.
     * @param borrower Address of a borrower.
     * @param expiration Unix timestamp (in seconds) setting up a default date.
     * @param collateral Asset used as a loan collateral. For a definition see { MultiToken dependency lib }.
     * @param asset Asset used as a loan credit. For a definition see { MultiToken dependency lib }.
     * @param loanRepayAmount Amount of a loan asset to be paid back.
     */
    struct LOANTerms {
        address lender;
        address borrower;
        uint40 expiration;
        MultiToken.Asset collateral;
        MultiToken.Asset asset;
        uint256 loanRepayAmount;
    }

    /**
     * Mapping of all LOAN data by loan id.
     */
    mapping (uint256 => LOAN) public LOANs;


    /*----------------------------------------------------------*|
    |*  # EVENTS & ERRORS DEFINITIONS                           *|
    |*----------------------------------------------------------*/

    /**
     * @dev Emitted when a new loan in created.
     */
    event LOANCreated(uint256 indexed loanId, LOANTerms terms);

    /**
     * @dev Emitted when a loan in paid back.
     */
    event LOANPaidBack(uint256 indexed loanId);

    /**
     * @dev Emitted when a repaid or defaulted loan in claimed.
     */
    event LOANClaimed(uint256 indexed loanId, bool indexed defaulted);


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

    /**
     * @notice Create a new loan by minting LOAN token for lender, transferring loan asset to borrower and collateral to a vault.
     * @dev The function assumes a prior token approval to a vault address or permits.
     * @param loanFactoryContract Address of a loan factory contract. Need to have `SIMPLE_LOAN_FACTORY` tag in PWN Hub.
     * @param loanFactoryData Encoded data for a loan factory.
     * @param signature Signed loan factory data. Could be empty if an offer / request has been made via on-chain transaction.
     * @param loanAssetPermit Permit data for a loan asset signed by a lender.
     * @param collateralPermit Permit data for a collateral signed by a borrower.
     * @return loanId Id of a newly minted LOAN token.
     */
    function createLOAN(
        address loanFactoryContract,
        bytes calldata loanFactoryData,
        bytes calldata signature,
        bytes calldata loanAssetPermit,
        bytes calldata collateralPermit
    ) external returns (uint256 loanId) {
        // Check that loan factory contract is tagged in PWNHub
        if (hub.hasTag(loanFactoryContract, PWNHubTags.SIMPLE_LOAN_FACTORY) == false)
            revert PWNError.CallerMissingHubTag(PWNHubTags.SIMPLE_LOAN_FACTORY);

        // Build LOANTerms by loan factory
        LOANTerms memory loanTerms = IPWNSimpleLoanFactory(loanFactoryContract).createLOAN({
            caller: msg.sender,
            loanFactoryData: loanFactoryData,
            signature: signature
        });

        // Mint LOAN token for lender
        loanId = loanToken.mint(loanTerms.lender);

        // Store loan data under loan id
        LOAN storage loan = LOANs[loanId];
        loan.status = 2;
        loan.borrower = loanTerms.borrower;
        loan.expiration = loanTerms.expiration;
        loan.loanAssetAddress = loanTerms.asset.assetAddress;
        loan.loanRepayAmount = loanTerms.loanRepayAmount;
        loan.collateral = loanTerms.collateral;

        emit LOANCreated(loanId, loanTerms);

        // Transfer collateral to Vault
        _permit(loanTerms.collateral, loanTerms.borrower, collateralPermit);
        _pull(loanTerms.collateral, loanTerms.borrower);

        // Permit spending if permit data provided
        _permit(loanTerms.asset, loanTerms.lender, loanAssetPermit);

        uint16 fee = config.fee();
        if (fee > 0) {
            // Compute fee size
            (uint256 feeAmount, uint256 newLoanAmount) = PWNFeeCalculator.calculateFeeAmount(fee, loanTerms.asset.amount);

            // Transfer fee amount to fee collector
            loanTerms.asset.amount = feeAmount;
            _pushFrom(loanTerms.asset, loanTerms.lender, config.feeCollector());

            // Set new loan amount value
            loanTerms.asset.amount = newLoanAmount;
        }

        // Transfer loan asset to borrower
        _pushFrom(loanTerms.asset, loanTerms.lender, loanTerms.borrower);
    }


    /*----------------------------------------------------------*|
    |*  # REPAY LOAN                                            *|
    |*----------------------------------------------------------*/

    /**
     * @notice Repay running loan.
     * @dev Any address can repay a running loan, but a collateral will be transferred to a borrower address associated with the loan.
     *      Repay will transfer a loan asset to a vault, waiting on a LOAN token holder to claim it.
     *      The function assumes a prior token approval to a vault address or a permit.
     * @param loanId Id of a loan that is being repaid.
     * @param loanAssetPermit Permit data for a loan asset signed by a borrower.
     */
    function repayLoan(
        uint256 loanId,
        bytes calldata loanAssetPermit
    ) external {
        LOAN storage loan = LOANs[loanId];
        uint8 status = loan.status;

        // Check that loan is not from a different loan contract
        if (status == 0)
            revert PWNError.NonExistingLoan();
        // Check that loan running
        else if (status != 2)
            revert PWNError.InvalidLoanStatus(status);

        // Check that loan is not expired
        if (loan.expiration <= block.timestamp)
            revert PWNError.LoanDefaulted(loan.expiration);

        // Move loan to repaid state
        loan.status = 3;

        // Transfer repaid amount of loan asset to Vault
        MultiToken.Asset memory repayLoanAsset = MultiToken.Asset({
            category: MultiToken.Category.ERC20,
            assetAddress: loan.loanAssetAddress,
            id: 0,
            amount: loan.loanRepayAmount
        });

        _permit(repayLoanAsset, msg.sender, loanAssetPermit);
        _pull(repayLoanAsset, msg.sender);

        // Transfer collateral back to borrower
        _push(loan.collateral, loan.borrower);

        emit LOANPaidBack(loanId);
    }


    /*----------------------------------------------------------*|
    |*  # CLAIM LOAN                                            *|
    |*----------------------------------------------------------*/

    /**
     * @notice Claim a repaid or defaulted loan.
     * @dev Only a LOAN token holder can claim a repaid or defaulted loan.
     *      Claim will transfer the repaid loan asset or collateral to a LOAN token holder address and burn the LOAN token.
     * @param loanId Id of a loan that is being claimed.
     */
    function claimLoan(uint256 loanId) external {
        LOAN storage loan = LOANs[loanId];

        // Check that caller is LOAN token holder
        if (loanToken.ownerOf(loanId) != msg.sender)
            revert PWNError.CallerNotLOANTokenHolder();

        if (loan.status == 0) {
            revert PWNError.NonExistingLoan();
        }
        // Loan has been paid back
        else if (loan.status == 3) {
            MultiToken.Asset memory loanAsset = MultiToken.Asset({
                category: MultiToken.Category.ERC20,
                assetAddress: loan.loanAssetAddress,
                id: 0,
                amount: loan.loanRepayAmount
            });

            // Delete loan data & burn LOAN token before calling safe transfer
            _deleteLoan(loanId);

            // Transfer repaid loan to lender
            _push(loanAsset, msg.sender);

            emit LOANClaimed(loanId, false);
        }
        // Loan is running but expired
        else if (loan.status == 2 && loan.expiration <= block.timestamp) {
             MultiToken.Asset memory collateral = loan.collateral;

            // Delete loan data & burn LOAN token before calling safe transfer
            _deleteLoan(loanId);

            // Transfer collateral to lender
            _push(collateral, msg.sender);

            emit LOANClaimed(loanId, true);
        }
        // Loan is in wrong state or from a different loan contract
        else {
            revert PWNError.InvalidLoanStatus(loan.status);
        }
    }

    function _deleteLoan(uint256 loanId) private {
        loanToken.burn(loanId);
        delete LOANs[loanId];
    }


    /*----------------------------------------------------------*|
    |*  # IPWNLoanMetadataProvider                              *|
    |*----------------------------------------------------------*/

    /**
     * @notice See { IPWNLoanMetadataProvider.sol }.
     */
    function loanMetadataUri() override external view returns (string memory) {
        return config.loanMetadataUri(address(this));
    }

}
