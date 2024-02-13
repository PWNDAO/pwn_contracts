// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "MultiToken/MultiToken.sol";

import "@pwn/config/PWNConfig.sol";
import "@pwn/hub/PWNHub.sol";
import "@pwn/hub/PWNHubTags.sol";
import "@pwn/loan/lib/PWNFeeCalculator.sol";
import "@pwn/loan/terms/PWNLOANTerms.sol";
import "@pwn/loan/terms/simple/factory/PWNSimpleLoanTermsFactory.sol";
import "@pwn/loan/token/IERC5646.sol";
import "@pwn/loan/token/PWNLOAN.sol";
import "@pwn/loan/PWNVault.sol";
import "@pwn/PWNErrors.sol";


/**
 * @title PWN Simple Loan
 * @notice Contract managing a simple loan in PWN protocol.
 * @dev Acts as a vault for every loan created by this contract.
 */
contract PWNSimpleLoan is PWNVault, IERC5646, IPWNLoanMetadataProvider {

    string public constant VERSION = "1.2";
    uint256 public constant MAX_EXPIRATION_EXTENSION = 2_592_000; // 30 days

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    PWNHub immutable internal hub;
    PWNLOAN immutable internal loanToken;
    PWNConfig immutable internal config;

    /**
     * @notice Struct defining a simple loan.
     * @param status 0 == none/dead || 2 == running/accepted offer/accepted request || 3 == paid back || 4 == expired.
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
     * Mapping of all LOAN data by loan id.
     */
    mapping (uint256 => LOAN) private LOANs;


    /*----------------------------------------------------------*|
    |*  # EVENTS & ERRORS DEFINITIONS                           *|
    |*----------------------------------------------------------*/

    /**
     * @dev Emitted when a new loan in created.
     */
    event LOANCreated(uint256 indexed loanId, PWNLOANTerms.Simple terms, bytes32 indexed factoryDataHash, address indexed factoryAddress);

    /**
     * @dev Emitted when a loan is paid back.
     */
    event LOANPaidBack(uint256 indexed loanId);

    /**
     * @dev Emitted when a repaid or defaulted loan is claimed.
     */
    event LOANClaimed(uint256 indexed loanId, bool indexed defaulted);

    /**
     * @dev Emitted when a LOAN token holder extends loan expiration date.
     */
    event LOANExpirationDateExtended(uint256 indexed loanId, uint40 extendedExpirationDate);


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
     * @notice Create a new loan by minting LOAN token for lender, transferring loan asset to a borrower and a collateral to a vault.
     * @dev The function assumes a prior token approval to a contract address or signed permits.
     * @param loanTermsFactoryContract Address of a loan terms factory contract. Need to have `SIMPLE_LOAN_TERMS_FACTORY` tag in PWN Hub.
     * @param loanTermsFactoryData Encoded data for a loan terms factory.
     * @param signature Signed loan factory data. Could be empty if an offer / request has been made via on-chain transaction.
     * @param loanAssetPermit Permit data for a loan asset signed by a lender.
     * @param collateralPermit Permit data for a collateral signed by a borrower.
     * @return loanId Id of a newly minted LOAN token.
     */
    function createLOAN(
        address loanTermsFactoryContract,
        bytes calldata loanTermsFactoryData,
        bytes calldata signature,
        bytes calldata loanAssetPermit,
        bytes calldata collateralPermit
    ) external returns (uint256 loanId) {
        // Check that loan terms factory contract is tagged in PWNHub
        if (hub.hasTag(loanTermsFactoryContract, PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY) == false)
            revert CallerMissingHubTag(PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY);

        // Build PWNLOANTerms.Simple by loan factory
        (PWNLOANTerms.Simple memory loanTerms, bytes32 factoryDataHash) = PWNSimpleLoanTermsFactory(loanTermsFactoryContract).createLOANTerms({
            caller: msg.sender,
            factoryData: loanTermsFactoryData,
            signature: signature
        });

        // Check loan asset validity
        if (MultiToken.isValid(loanTerms.asset) == false)
            revert InvalidLoanAsset();

        // Check collateral validity
        if (MultiToken.isValid(loanTerms.collateral) == false)
            revert InvalidCollateralAsset();

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

        emit LOANCreated(loanId, loanTerms, factoryDataHash, loanTermsFactoryContract);

        // Transfer collateral to Vault
        _permit(loanTerms.collateral, loanTerms.borrower, collateralPermit);
        _pull(loanTerms.collateral, loanTerms.borrower);

        // Permit spending if permit data provided
        _permit(loanTerms.asset, loanTerms.lender, loanAssetPermit);

        uint16 fee = config.fee();
        if (fee > 0) {
            // Compute fee size
            (uint256 feeAmount, uint256 newLoanAmount) = PWNFeeCalculator.calculateFeeAmount(fee, loanTerms.asset.amount);

            if (feeAmount > 0) {
                // Transfer fee amount to fee collector
                loanTerms.asset.amount = feeAmount;
                _pushFrom(loanTerms.asset, loanTerms.lender, config.feeCollector());

                // Set new loan amount value
                loanTerms.asset.amount = newLoanAmount;
            }
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
     *      The function assumes a prior token approval to a contract address or a signed  permit.
     * @param loanId Id of a loan that is being repaid.
     * @param loanAssetPermit Permit data for a loan asset signed by a borrower.
     */
    function repayLOAN(
        uint256 loanId,
        bytes calldata loanAssetPermit
    ) external {
        LOAN storage loan = LOANs[loanId];
        uint8 status = loan.status;

        // Check that loan is not from a different loan contract
        if (status == 0)
            revert NonExistingLoan();
        // Check that loan is running
        else if (status != 2)
            revert InvalidLoanStatus(status);

        // Check that loan is not expired
        if (loan.expiration <= block.timestamp)
            revert LoanDefaulted(loan.expiration);

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
    function claimLOAN(uint256 loanId) external {
        LOAN storage loan = LOANs[loanId];

        // Check that caller is LOAN token holder
        if (loanToken.ownerOf(loanId) != msg.sender)
            revert CallerNotLOANTokenHolder();

        if (loan.status == 0) {
            revert NonExistingLoan();
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
            revert InvalidLoanStatus(loan.status);
        }
    }

    function _deleteLoan(uint256 loanId) private {
        loanToken.burn(loanId);
        delete LOANs[loanId];
    }


    /*----------------------------------------------------------*|
    |*  # EXTEND LOAN EXPIRATION DATE                           *|
    |*----------------------------------------------------------*/

    /**
     * @notice Enable lender to extend loans expiration date.
     * @dev Only LOAN token holder can call this function.
     *      Extending the expiration date of a repaid loan is allowed, but considered a lender mistake.
     *      The extended expiration date has to be in the future, be later than the current expiration date, and cannot be extending the date by more than `MAX_EXPIRATION_EXTENSION`.
     * @param loanId Id of a LOAN to extend its expiration date.
     * @param extendedExpirationDate New LOAN expiration date.
     */
    function extendLOANExpirationDate(uint256 loanId, uint40 extendedExpirationDate) external {
        // Check that caller is LOAN token holder
        // This prevents from extending non-existing loans
        if (loanToken.ownerOf(loanId) != msg.sender)
            revert CallerNotLOANTokenHolder();

        LOAN storage loan = LOANs[loanId];

        // Check extended expiration date
        if (extendedExpirationDate > uint40(block.timestamp + MAX_EXPIRATION_EXTENSION)) // to protect lender
            revert InvalidExtendedExpirationDate();
        if (extendedExpirationDate <= uint40(block.timestamp)) // have to extend expiration futher in time
            revert InvalidExtendedExpirationDate();
        if (extendedExpirationDate <= loan.expiration) // have to be later than current expiration date
            revert InvalidExtendedExpirationDate();

        // Extend expiration date
        loan.expiration = extendedExpirationDate;

        emit LOANExpirationDateExtended(loanId, extendedExpirationDate);
    }


    /*----------------------------------------------------------*|
    |*  # GET LOAN                                              *|
    |*----------------------------------------------------------*/

    /**
     * @notice Return a LOAN data struct associated with a loan id.
     * @param loanId Id of a loan in question.
     * @return loan LOAN data struct or empty struct if the LOAN doesn't exist.
     */
    function getLOAN(uint256 loanId) external view returns (LOAN memory loan) {
        loan = LOANs[loanId];
        loan.status = _getLOANStatus(loanId);
    }

    function _getLOANStatus(uint256 loanId) private view returns (uint8) {
        LOAN storage loan = LOANs[loanId];
        return (loan.status == 2 && loan.expiration <= block.timestamp) ? 4 : loan.status;
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


    /*----------------------------------------------------------*|
    |*  # ERC5646                                               *|
    |*----------------------------------------------------------*/

    /**
     * @dev See {IERC5646-getStateFingerprint}.
     */
    function getStateFingerprint(uint256 tokenId) external view virtual override returns (bytes32) {
        LOAN storage loan = LOANs[tokenId];

        if (loan.status == 0)
            return bytes32(0);

        // The only mutable state properties are:
        // - status, expiration
        // Status is updated for expired loans based on block.timestamp.
        // Others don't have to be part of the state fingerprint as it does not act as a token identification.
        return keccak256(abi.encode(
            _getLOANStatus(tokenId),
            loan.expiration
        ));
    }

}
