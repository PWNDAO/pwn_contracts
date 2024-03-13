// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken, IMultiTokenCategoryRegistry } from "MultiToken/MultiToken.sol";

import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import { SafeCast } from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import { PWNConfig } from "@pwn/config/PWNConfig.sol";
import { PWNHub } from "@pwn/hub/PWNHub.sol";
import { PWNHubTags } from "@pwn/hub/PWNHubTags.sol";
import { PWNFeeCalculator } from "@pwn/loan/lib/PWNFeeCalculator.sol";
import { PWNSignatureChecker } from "@pwn/loan/lib/PWNSignatureChecker.sol";
import { PWNSimpleLoanProposal } from "@pwn/loan/terms/simple/proposal/PWNSimpleLoanProposal.sol";
import { IERC5646 } from "@pwn/loan/token/IERC5646.sol";
import { IPWNLoanMetadataProvider } from "@pwn/loan/token/IPWNLoanMetadataProvider.sol";
import { PWNLOAN } from "@pwn/loan/token/PWNLOAN.sol";
import { PWNVault } from "@pwn/loan/PWNVault.sol";
import { PWNRevokedNonce } from "@pwn/nonce/PWNRevokedNonce.sol";
import "@pwn/PWNErrors.sol";


/**
 * @title PWN Simple Loan
 * @notice Contract managing a simple loan in PWN protocol.
 * @dev Acts as a vault for every loan created by this contract.
 */
contract PWNSimpleLoan is PWNVault, IERC5646, IPWNLoanMetadataProvider {

    string public constant VERSION = "1.2";

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    uint256 public constant APR_INTEREST_DENOMINATOR = 1e4;
    uint256 public constant DAILY_INTEREST_DENOMINATOR = 1e10;

    uint256 public constant APR_TO_DAILY_INTEREST_NUMERATOR = 274;
    uint256 public constant APR_TO_DAILY_INTEREST_DENOMINATOR = 1e5;

    uint256 public constant MAX_EXTENSION_DURATION = 90 days;
    uint256 public constant MIN_EXTENSION_DURATION = 1 days;

    bytes32 public constant EXTENSION_PROPOSAL_TYPEHASH = keccak256(
        "ExtensionProposal(uint256 loanId,address compensationAddress,uint256 compensationAmount,uint40 duration,uint40 expiration,address proposer,uint256 nonceSpace,uint256 nonce)"
    );

    bytes32 public immutable DOMAIN_SEPARATOR = keccak256(abi.encode(
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
        keccak256("PWNSimpleLoan"),
        keccak256(abi.encodePacked(VERSION)),
        block.chainid,
        address(this)
    ));

    PWNHub public immutable hub;
    PWNLOAN public immutable loanToken;
    PWNConfig public immutable config;
    PWNRevokedNonce public immutable revokedNonce;
    IMultiTokenCategoryRegistry public immutable categoryRegistry;

    /**
     * @notice Struct defining a simple loan terms.
     * @dev This struct is created by proposal contracts and never stored.
     * @param lender Address of a lender.
     * @param borrower Address of a borrower.
     * @param duration Loan duration in seconds.
     * @param collateral Asset used as a loan collateral. For a definition see { MultiToken dependency lib }.
     * @param credit Asset used as a loan credit. For a definition see { MultiToken dependency lib }.
     * @param fixedInterestAmount Fixed interest amount in credit asset tokens. It is the minimum amount of interest which has to be paid by a borrower.
     * @param accruingInterestAPR Accruing interest APR.
     */
    struct Terms {
        address lender;
        address borrower;
        uint32 duration;
        MultiToken.Asset collateral;
        MultiToken.Asset credit;
        uint256 fixedInterestAmount;
        uint40 accruingInterestAPR;
    }

    /**
     * @notice Struct defining a simple loan.
     * @param status 0 == none/dead || 2 == running/accepted offer/accepted request || 3 == paid back || 4 == expired.
     * @param creditAddress Address of an asset used as a loan credit.
     * @param startTimestamp Unix timestamp (in seconds) of a start date.
     * @param defaultTimestamp Unix timestamp (in seconds) of a default date.
     * @param borrower Address of a borrower.
     * @param originalLender Address of a lender that funded the loan.
     * @param accruingInterestDailyRate Accruing daily interest rate.
     * @param fixedInterestAmount Fixed interest amount in credit asset tokens.
     *                            It is the minimum amount of interest which has to be paid by a borrower.
     *                            This property is reused to store the final interest amount if the loan is repaid and waiting to be claimed.
     * @param principalAmount Principal amount in credit asset tokens.
     * @param collateral Asset used as a loan collateral. For a definition see { MultiToken dependency lib }.
     */
    struct LOAN {
        uint8 status;
        address creditAddress;
        uint40 startTimestamp;
        uint40 defaultTimestamp;
        address borrower;
        address originalLender;
        uint40 accruingInterestDailyRate;
        uint256 fixedInterestAmount;
        uint256 principalAmount;
        MultiToken.Asset collateral;
    }

    /**
     * Mapping of all LOAN data by loan id.
     */
    mapping (uint256 => LOAN) private LOANs;

    /**
     * @notice Struct defining a loan extension proposal that can be signed by a borrower or a lender.
     * @param loanId Id of a loan to be extended.
     * @param compensationAddress Address of a compensation asset.
     * @param compensationAmount Amount of a compensation asset that a borrower has to pay to a lender.
     * @param duration Duration of the extension in seconds.
     * @param expiration Unix timestamp (in seconds) of an expiration date.
     * @param proposer Address of a proposer that signed the extension proposal.
     * @param nonceSpace Nonce space of the extension proposal nonce.
     * @param nonce Nonce of the extension proposal.
     */
    struct ExtensionProposal {
        uint256 loanId;
        address compensationAddress;
        uint256 compensationAmount;
        uint40 duration;
        uint40 expiration;
        address proposer;
        uint256 nonceSpace;
        uint256 nonce;
    }

    /**
     * Mapping of extension proposals made via on-chain transaction by extension hash.
     */
    mapping (bytes32 => bool) public extensionProposalsMade;

    /*----------------------------------------------------------*|
    |*  # EVENTS & ERRORS DEFINITIONS                           *|
    |*----------------------------------------------------------*/

    /**
     * @dev Emitted when a new loan in created.
     */
    event LOANCreated(uint256 indexed loanId, Terms terms, bytes32 indexed proposalHash, address indexed proposalContract);

    /**
     * @dev Emitted when a loan is paid back.
     */
    event LOANPaidBack(uint256 indexed loanId);

    /**
     * @dev Emitted when a repaid or defaulted loan is claimed.
     */
    event LOANClaimed(uint256 indexed loanId, bool indexed defaulted);

    /**
     * @dev Emitted when a loan is refinanced.
     */
    event LOANRefinanced(uint256 indexed loanId, uint256 indexed refinancedLoanId);

    /**
     * @dev Emitted when a LOAN token holder extends a loan.
     */
    event LOANExtended(uint256 indexed loanId, uint40 originalDefaultTimestamp, uint40 extendedDefaultTimestamp);

    /**
     * @dev Emitted when a loan extension proposal is made.
     */
    event ExtensionProposalMade(bytes32 indexed extensionHash, address indexed proposer,  ExtensionProposal proposal);


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(
        address _hub,
        address _loanToken,
        address _config,
        address _revokedNonce,
        address _categoryRegistry
    ) {
        hub = PWNHub(_hub);
        loanToken = PWNLOAN(_loanToken);
        config = PWNConfig(_config);
        revokedNonce = PWNRevokedNonce(_revokedNonce);
        categoryRegistry = IMultiTokenCategoryRegistry(_categoryRegistry);
    }


    /*----------------------------------------------------------*|
    |*  # CREATE LOAN                                           *|
    |*----------------------------------------------------------*/

    /**
     * @notice Create a new loan.
     * @dev The function assumes a prior token approval to a contract address or signed permits.
     * @param proposalHash Hash of a loan offer / request that is signed by a lender / borrower.
     * @param loanTerms Loan terms struct.
     * @param creditPermit Permit data for a credit asset signed by a lender.
     * @param collateralPermit Permit data for a collateral signed by a borrower.
     * @return loanId Id of the created LOAN token.
     */
    function createLOAN(
        bytes32 proposalHash,
        Terms calldata loanTerms,
        bytes calldata creditPermit,
        bytes calldata collateralPermit
    ) external returns (uint256 loanId) {
        // Check that caller is loan proposal contract
        if (!hub.hasTag(msg.sender, PWNHubTags.LOAN_PROPOSAL)) {
            revert CallerMissingHubTag(PWNHubTags.LOAN_PROPOSAL);
        }

        // Check loan terms
        _checkLoanTerms(loanTerms);

        // Create a new loan
        loanId = _createLoan({
            proposalHash: proposalHash,
            proposalContract: msg.sender,
            loanTerms: loanTerms
        });

        // Transfer collateral to Vault and credit to borrower
        _settleNewLoan(loanTerms, creditPermit, collateralPermit);
    }

    /**
     * @notice Check loan terms validity.
     * @dev The function will revert if the loan terms are not valid.
     * @param loanTerms Loan terms struct.
     */
    function _checkLoanTerms(Terms calldata loanTerms) private view {
        // Check loan credit and collateral validity
        _checkValidAsset(loanTerms.credit);
        _checkValidAsset(loanTerms.collateral);
    }

    /**
     * @notice Mint LOAN token and store loan data under loan id.
     * @param proposalHash Hash of a loan offer / request that is signed by a lender / borrower.
     * @param proposalContract Address of a loan proposal contract.
     * @param loanTerms Loan terms struct.
     */
    function _createLoan(
        bytes32 proposalHash,
        address proposalContract,
        Terms calldata loanTerms
    ) private returns (uint256 loanId) {
        // Mint LOAN token for lender
        loanId = loanToken.mint(loanTerms.lender);

        // Store loan data under loan id
        LOAN storage loan = LOANs[loanId];
        loan.status = 2;
        loan.creditAddress = loanTerms.credit.assetAddress;
        loan.startTimestamp = uint40(block.timestamp);
        loan.defaultTimestamp = uint40(block.timestamp) + loanTerms.duration;
        loan.borrower = loanTerms.borrower;
        loan.originalLender = loanTerms.lender;
        loan.accruingInterestDailyRate = SafeCast.toUint40(Math.mulDiv(
            loanTerms.accruingInterestAPR, APR_TO_DAILY_INTEREST_NUMERATOR, APR_TO_DAILY_INTEREST_DENOMINATOR
        ));
        loan.fixedInterestAmount = loanTerms.fixedInterestAmount;
        loan.principalAmount = loanTerms.credit.amount;
        loan.collateral = loanTerms.collateral;

        emit LOANCreated({
            loanId: loanId,
            terms: loanTerms,
            proposalHash: proposalHash,
            proposalContract: proposalContract
        });
    }

    /**
     * @notice Transfer collateral to Vault and credit to borrower.
     * @dev The function assumes a prior token approval to a contract address or signed permits.
     * @param loanTerms Loan terms struct.
     * @param creditPermit Permit data for a credit asset signed by a lender.
     * @param collateralPermit Permit data for a collateral signed by a borrower.
     */
    function _settleNewLoan(
        Terms calldata loanTerms,
        bytes calldata creditPermit,
        bytes calldata collateralPermit
    ) private {
        // Transfer collateral to Vault
        _permit(loanTerms.collateral, loanTerms.borrower, collateralPermit);
        _pull(loanTerms.collateral, loanTerms.borrower);

        // Permit credit spending if permit provided
        _permit(loanTerms.credit, loanTerms.lender, creditPermit);

        MultiToken.Asset memory creditHelper = loanTerms.credit;

        // Collect fee if any and update credit asset amount
        (uint256 feeAmount, uint256 newLoanAmount)
            = PWNFeeCalculator.calculateFeeAmount(config.fee(), loanTerms.credit.amount);
        if (feeAmount > 0) {
            // Transfer fee amount to fee collector
            creditHelper.amount = feeAmount;
            _pushFrom(creditHelper, loanTerms.lender, config.feeCollector());

            // Set new loan amount value
            creditHelper.amount = newLoanAmount;
        }

        // Note: If the fee amount is greater than zero, the credit amount is already updated to the new loan amount.

        // Transfer credit to borrower
        _pushFrom(creditHelper, loanTerms.lender, loanTerms.borrower);
    }


    /*----------------------------------------------------------*|
    |*  # REFINANCE LOAN                                        *|
    |*----------------------------------------------------------*/

    /**
     * @notice Refinance a loan by repaying the original loan and creating a new one.
     * @dev If the new lender is the same as the current LOAN owner,
     *      the function will transfer only the surplus to the borrower, if any.
     *      If the new loan amount is not enough to cover the original loan, the borrower needs to contribute.
     *      The function assumes a prior token approval to a contract address or signed permits.
     * @param proposalHash Hash of a loan offer / request that is signed by a lender / borrower. Used to uniquely identify a loan offer / request.
     * @param loanTerms Loan terms struct.
     * @param lenderCreditPermit Permit data for a credit asset signed by a lender.
     * @param borrowerCreditPermit Permit data for a credit asset signed by a borrower.
     * @return refinancedLoanId Id of the refinanced LOAN token.
     */
    function refinanceLOAN(
        uint256 loanId,
        bytes32 proposalHash,
        Terms calldata loanTerms,
        bytes calldata lenderCreditPermit,
        bytes calldata borrowerCreditPermit
    ) external returns (uint256 refinancedLoanId) {
        // Check that caller is loan proposal contract
        if (!hub.hasTag(msg.sender, PWNHubTags.LOAN_PROPOSAL)) {
            revert CallerMissingHubTag(PWNHubTags.LOAN_PROPOSAL);
        }

        LOAN storage loan = LOANs[loanId];

        // Check that the original loan can be repaid, revert if not
        _checkLoanCanBeRepaid(loan.status, loan.defaultTimestamp);

        // Check refinance loan terms
        _checkRefinanceLoanTerms(loanId, loanTerms);

        // Create a new loan
        refinancedLoanId = _createLoan({
            proposalHash: proposalHash,
            proposalContract: msg.sender,
            loanTerms: loanTerms
        });

        // Refinance the original loan
        _refinanceOriginalLoan(
            loanId,
            loanTerms,
            lenderCreditPermit,
            borrowerCreditPermit
        );

        emit LOANRefinanced({ loanId: loanId, refinancedLoanId: refinancedLoanId });
    }

    /**
     * @notice Check if the loan terms are valid for refinancing.
     * @dev The function will revert if the loan terms are not valid for refinancing.
     * @param loanId Original loan id.
     * @param loanTerms Refinancing loan terms struct.
     */
    function _checkRefinanceLoanTerms(uint256 loanId, Terms calldata loanTerms) private view {
        LOAN storage loan = LOANs[loanId];

        // Check that the credit asset is the same as in the original loan
        // Note: Address check is enough because the asset has always ERC20 category and zero id.
        // Amount can be different, but nonzero.
        if (
            loan.creditAddress != loanTerms.credit.assetAddress ||
            loanTerms.credit.amount == 0
        ) revert RefinanceCreditMismatch();

        // Check that the collateral is identical to the original one
        if (
            loan.collateral.category != loanTerms.collateral.category ||
            loan.collateral.assetAddress != loanTerms.collateral.assetAddress ||
            loan.collateral.id != loanTerms.collateral.id ||
            loan.collateral.amount != loanTerms.collateral.amount
        ) revert RefinanceCollateralMismatch();

        // Check that the borrower is the same as in the original loan
        if (loan.borrower != loanTerms.borrower) {
            revert RefinanceBorrowerMismatch({
                currentBorrower: loan.borrower,
                newBorrower: loanTerms.borrower
            });
        }
    }

    /**
     * @notice Repay the original loan and transfer the surplus to the borrower if any.
     * @dev If the new lender is the same as the current LOAN owner,
     *      the function will transfer only the surplus to the borrower, if any.
     *      If the new loan amount is not enough to cover the original loan, the borrower needs to contribute.
     *      The function assumes a prior token approval to a contract address or signed permits.
     * @param loanId Id of a loan that is being refinanced.
     * @param loanTerms Loan terms struct.
     * @param lenderCreditPermit Permit data for a credit asset signed by a lender.
     * @param borrowerCreditPermit Permit data for a credit asset signed by a borrower.
     */
    function _refinanceOriginalLoan(
        uint256 loanId,
        Terms calldata loanTerms,
        bytes calldata lenderCreditPermit,
        bytes calldata borrowerCreditPermit
    ) private {
        uint256 repaymentAmount = _loanRepaymentAmount(loanId);

        // Delete or update the original loan
        (bool repayLoanDirectly, address loanOwner) = _deleteOrUpdateRepaidLoan(loanId);

        // Repay the original loan and transfer the surplus to the borrower if any
        _settleLoanRefinance({
            repayLoanDirectly: repayLoanDirectly,
            loanOwner: loanOwner,
            repaymentAmount: repaymentAmount,
            loanTerms: loanTerms,
            lenderPermit: lenderCreditPermit,
            borrowerPermit: borrowerCreditPermit
        });
    }

    /**
     * @notice Settle the refinanced loan. If the new lender is the same as the current LOAN owner,
     *         the function will transfer only the surplus to the borrower, if any.
     *         If the new loan amount is not enough to cover the original loan, the borrower needs to contribute.
     *         The function assumes a prior token approval to a contract address or signed permits.
     * @param repayLoanDirectly If the loan can be repaid directly to the current LOAN owner.
     * @param loanOwner Address of the current LOAN owner.
     * @param repaymentAmount Amount of the original loan to be repaid.
     * @param loanTerms Loan terms struct.
     * @param lenderPermit Permit data for a credit asset signed by a lender.
     * @param borrowerPermit Permit data for a credit asset signed by a borrower.
     */
    function _settleLoanRefinance(
        bool repayLoanDirectly,
        address loanOwner,
        uint256 repaymentAmount,
        Terms calldata loanTerms,
        bytes calldata lenderPermit,
        bytes calldata borrowerPermit
    ) private {
        MultiToken.Asset memory creditHelper = loanTerms.credit;

        // Compute fee size
        (uint256 feeAmount, uint256 newLoanAmount)
            = PWNFeeCalculator.calculateFeeAmount(config.fee(), loanTerms.credit.amount);

        // Permit lenders credit spending if permit provided
        creditHelper.amount -= loanTerms.lender == loanOwner // Permit only the surplus transfer + fee
            ? Math.min(repaymentAmount, newLoanAmount)
            : 0;

        if (creditHelper.amount > 0) {
            _permit(creditHelper, loanTerms.lender, lenderPermit);
        }

        // Collect fees
        if (feeAmount > 0) {
            creditHelper.amount = feeAmount;
            _pushFrom(creditHelper, loanTerms.lender, config.feeCollector());
        }

        // If the new lender is the LOAN token owner, don't execute the transfer at all,
        // it would make transfer from the same address to the same address
        if (loanTerms.lender != loanOwner) {
            creditHelper.amount = Math.min(repaymentAmount, newLoanAmount);
            _transferLoanRepayment({
                repayLoanDirectly: repayLoanDirectly,
                repaymentCredit: creditHelper,
                repayingAddress: loanTerms.lender,
                currentLoanOwner: loanOwner
            });
        }

        if (newLoanAmount >= repaymentAmount) {
            // New loan covers the whole original loan, transfer surplus to the borrower if any
            uint256 surplus = newLoanAmount - repaymentAmount;
            if (surplus > 0) {
                creditHelper.amount = surplus;
                _pushFrom(creditHelper, loanTerms.lender, loanTerms.borrower);
            }
        } else {
            // Permit borrowers credit spending if permit provided
            creditHelper.amount = repaymentAmount - newLoanAmount;
            _permit(creditHelper, loanTerms.borrower, borrowerPermit);

            // New loan covers only part of the original loan, borrower needs to contribute
            _transferLoanRepayment({
                repayLoanDirectly: repayLoanDirectly || loanTerms.lender == loanOwner,
                repaymentCredit: creditHelper,
                repayingAddress: loanTerms.borrower,
                currentLoanOwner: loanOwner
            });
        }
    }


    /*----------------------------------------------------------*|
    |*  # REPAY LOAN                                            *|
    |*----------------------------------------------------------*/

    /**
     * @notice Repay running loan.
     * @dev Any address can repay a running loan, but a collateral will be transferred to a borrower address associated with the loan.
     *      Repay will transfer a credit asset to a vault, waiting on a LOAN token holder to claim it.
     *      The function assumes a prior token approval to a contract address or a signed  permit.
     * @param loanId Id of a loan that is being repaid.
     * @param creditPermit Permit data for a credit asset signed by a borrower.
     */
    function repayLOAN(
        uint256 loanId,
        bytes calldata creditPermit
    ) external {
        LOAN storage loan = LOANs[loanId];

        _checkLoanCanBeRepaid(loan.status, loan.defaultTimestamp);

        address borrower = loan.borrower;
        MultiToken.Asset memory collateral = loan.collateral;
        MultiToken.Asset memory repaymentCredit = MultiToken.ERC20(loan.creditAddress, _loanRepaymentAmount(loanId));

        (bool repayLoanDirectly, address loanOwner) = _deleteOrUpdateRepaidLoan(loanId);

        _settleLoanRepayment({
            repayLoanDirectly: repayLoanDirectly,
            loanOwner: loanOwner,
            repayingAddress: msg.sender,
            borrower: borrower,
            repaymentCredit: repaymentCredit,
            collateral: collateral,
            creditPermit: creditPermit
        });
    }

    /**
     * @notice Check if the loan can be repaid.
     * @dev The function will revert if the loan cannot be repaid.
     * @param status Loan status.
     * @param defaultTimestamp Loan default timestamp.
     */
    function _checkLoanCanBeRepaid(uint8 status, uint40 defaultTimestamp) private view {
        // Check that loan exists and is not from a different loan contract
        if (status == 0) revert NonExistingLoan();
        // Check that loan is running
        if (status != 2) revert InvalidLoanStatus(status);
        // Check that loan is not defaulted
        if (defaultTimestamp <= block.timestamp) revert LoanDefaulted(defaultTimestamp);
    }

    /**
     * @notice Delete or update the original loan.
     * @dev If the loan can be repaid directly to the current LOAN owner,
     *      the function will delete the loan and burn the LOAN token.
     *      If the loan cannot be repaid directly to the current LOAN owner,
     *      the function will move the loan to repaid state and wait for the lender to claim the repaid credit.
     * @param loanId Id of a loan that is being repaid.
     * @return repayLoanDirectly If the loan can be repaid directly to the current LOAN owner.
     * @return loanOwner Address of the current LOAN owner.
     */
    function _deleteOrUpdateRepaidLoan(uint256 loanId) private returns (bool repayLoanDirectly, address loanOwner) {
        LOAN storage loan = LOANs[loanId];

        emit LOANPaidBack({ loanId: loanId });

        // Note: Assuming that it is safe to transfer the credit asset to the original lender
        // if the lender still owns the LOAN token because the lender was able to sign an offer
        // or make a contract call, thus can handle incoming transfers.
        loanOwner = loanToken.ownerOf(loanId);
        repayLoanDirectly = loan.originalLender == loanOwner;
        if (repayLoanDirectly) {
            // Delete loan data & burn LOAN token before calling safe transfer
            _deleteLoan(loanId);

            emit LOANClaimed({ loanId: loanId, defaulted: false });
        } else {
            // Move loan to repaid state and wait for the lender to claim the repaid credit
            loan.status = 3;
            // Update accrued interest amount
            loan.fixedInterestAmount = _loanAccruedInterest(loan);
            // Note: Reusing `fixedInterestAmount` to store accrued interest at the time of repayment
            // to have the value at the time of claim and stop accruing new interest.
            loan.accruingInterestDailyRate = 0;
        }
    }

    /**
     * @notice Settle the loan repayment.
     * @dev The function assumes a prior token approval to a contract address or a signed permit.
     * @param repayLoanDirectly If the loan can be repaid directly to the current LOAN owner.
     * @param loanOwner Address of the current LOAN owner.
     * @param repayingAddress Address of the account repaying the loan.
     * @param borrower Address of the borrower associated with the loan.
     * @param repaymentCredit Credit asset to be repaid.
     * @param collateral Collateral to be transferred back to the borrower.
     * @param creditPermit Permit data for a credit asset signed by a borrower.
     */
    function _settleLoanRepayment(
        bool repayLoanDirectly,
        address loanOwner,
        address repayingAddress,
        address borrower,
        MultiToken.Asset memory repaymentCredit,
        MultiToken.Asset memory collateral,
        bytes calldata creditPermit
    ) private {
        // Transfer credit to the original lender or to the Vault
        _permit(repaymentCredit, repayingAddress, creditPermit);
        _transferLoanRepayment(repayLoanDirectly, repaymentCredit, repayingAddress, loanOwner);

        // Transfer collateral back to borrower
        _push(collateral, borrower);
    }

    /**
     * @notice Transfer the repaid credit to the original lender or to the Vault.
     * @param repayLoanDirectly If the loan can be repaid directly to the current LOAN owner.
     * @param repaymentCredit Asset to be repaid.
     * @param repayingAddress Address of the account repaying the loan.
     * @param currentLoanOwner Address of the current LOAN owner.
     */
    function _transferLoanRepayment(
        bool repayLoanDirectly,
        MultiToken.Asset memory repaymentCredit,
        address repayingAddress,
        address currentLoanOwner
    ) private {
        if (repayLoanDirectly) {
            // Transfer the repaid credit to the LOAN token owner
            _pushFrom(repaymentCredit, repayingAddress, currentLoanOwner);
        } else {
            // Transfer the repaid credit to the Vault
            _pull(repaymentCredit, repayingAddress);
        }
    }


    /*----------------------------------------------------------*|
    |*  # LOAN REPAYMENT AMOUNT                                 *|
    |*----------------------------------------------------------*/

    /**
     * @notice Calculate the loan repayment amount with fixed and accrued interest.
     * @param loanId Id of a loan.
     * @return Repayment amount.
     */
    function loanRepaymentAmount(uint256 loanId) public view returns (uint256) {
        LOAN storage loan = LOANs[loanId];

        // Check non-existent
        if (loan.status == 0) return 0;

        return _loanRepaymentAmount(loanId);
    }

    /**
     * @notice Internal function to calculate the loan repayment amount with fixed and accrued interest.
     * @param loanId Id of a loan.
     * @return Repayment amount.
     */
    function _loanRepaymentAmount(uint256 loanId) private view returns (uint256) {
        LOAN storage loan = LOANs[loanId];

        // Return loan principal with accrued interest
        return loan.principalAmount + _loanAccruedInterest(loan);
    }

    /**
     * @notice Calculate the loan accrued interest.
     * @param loan Loan data struct.
     * @return Accrued interest amount.
     */
    function _loanAccruedInterest(LOAN storage loan) private view returns (uint256) {
        if (loan.accruingInterestDailyRate == 0)
            return loan.fixedInterestAmount;

        uint256 accruingDays = (block.timestamp - loan.startTimestamp) / 1 days;
        uint256 accruedInterest = Math.mulDiv(
            loan.principalAmount, loan.accruingInterestDailyRate * accruingDays, DAILY_INTEREST_DENOMINATOR
        );
        return loan.fixedInterestAmount + accruedInterest;
    }


    /*----------------------------------------------------------*|
    |*  # CLAIM LOAN                                            *|
    |*----------------------------------------------------------*/

    /**
     * @notice Claim a repaid or defaulted loan.
     * @dev Only a LOAN token holder can claim a repaid or defaulted loan.
     *      Claim will transfer the repaid credit or collateral to a LOAN token holder address and burn the LOAN token.
     * @param loanId Id of a loan that is being claimed.
     */
    function claimLOAN(uint256 loanId) external {
        LOAN storage loan = LOANs[loanId];

        // Check that caller is LOAN token holder
        if (loanToken.ownerOf(loanId) != msg.sender)
            revert CallerNotLOANTokenHolder();

        // Loan is not existing or from a different loan contract
        if (loan.status == 0)
            revert NonExistingLoan();
        // Loan has been paid back
        else if (loan.status == 3)
            _settleLoanClaim({ loanId: loanId, loanOwner: msg.sender, defaulted: false });
        // Loan is running but expired
        else if (loan.status == 2 && loan.defaultTimestamp <= block.timestamp)
            _settleLoanClaim({ loanId: loanId, loanOwner: msg.sender, defaulted: true });
        // Loan is in wrong state
        else
            revert InvalidLoanStatus(loan.status);
    }

    /**
     * @notice Settle the loan claim.
     * @param loanId Id of a loan that is being claimed.
     * @param loanOwner Address of the LOAN token holder.
     * @param defaulted If the loan is defaulted.
     */
    function _settleLoanClaim(uint256 loanId, address loanOwner, bool defaulted) private {
        LOAN storage loan = LOANs[loanId];

        // Store in memory before deleting the loan
        MultiToken.Asset memory asset = defaulted
            ? loan.collateral
            : MultiToken.ERC20(loan.creditAddress, _loanRepaymentAmount(loanId));

        // Delete loan data & burn LOAN token before calling safe transfer
        _deleteLoan(loanId);

        emit LOANClaimed({ loanId: loanId, defaulted: defaulted });

        // Transfer asset to current LOAN token owner
        _push(asset, loanOwner);
    }

    /**
     * @notice Delete loan data and burn LOAN token.
     * @param loanId Id of a loan that is being deleted.
     */
    function _deleteLoan(uint256 loanId) private {
        loanToken.burn(loanId);
        delete LOANs[loanId];
    }


    /*----------------------------------------------------------*|
    |*  # EXTEND LOAN                                           *|
    |*----------------------------------------------------------*/

    /**
     * @notice Make an on-chain extension proposal.
     * @param extension Extension proposal struct.
     */
    function makeExtensionProposal(ExtensionProposal calldata extension) external {
        // Check that caller is a proposer
        if (msg.sender != extension.proposer)
            revert InvalidExtensionSigner({ allowed: extension.proposer, current: msg.sender });

        // Mark extension proposal as made
        bytes32 extensionHash = getExtensionHash(extension);
        extensionProposalsMade[extensionHash] = true;

        emit ExtensionProposalMade(extensionHash, extension.proposer, extension);
    }

    /**
     * @notice Extend loans default date with signed extension proposal signed by borrower or LOAN token owner.
     * @dev The function assumes a prior token approval to a contract address or a signed permit.
     * @param extension Extension proposal struct.
     * @param signature Signature of the extension proposal.
     * @param compensationPermit Permit data for a fungible compensation asset signed by a borrower.
     */
    function extendLOAN(
        ExtensionProposal calldata extension,
        bytes calldata signature,
        bytes calldata compensationPermit
    ) external {
        LOAN storage loan = LOANs[extension.loanId];

        // Check that loan is in the right state
        if (loan.status == 0)
            revert NonExistingLoan();
        if (loan.status == 3) // cannot extend repaid loan
            revert InvalidLoanStatus(loan.status);

        // Check extension validity
        bytes32 extensionHash = getExtensionHash(extension);
        if (!extensionProposalsMade[extensionHash])
            if (!PWNSignatureChecker.isValidSignatureNow(extension.proposer, extensionHash, signature))
                revert InvalidSignature({ signer: extension.proposer, digest: extensionHash });

        // Check extension expiration
        if (block.timestamp >= extension.expiration)
            revert Expired({ current: block.timestamp, expiration: extension.expiration });

        // Check extension nonce
        if (!revokedNonce.isNonceUsable(extension.proposer, extension.nonceSpace, extension.nonce))
            revert NonceNotUsable({ addr: extension.proposer, nonceSpace: extension.nonceSpace, nonce: extension.nonce });

        // Check caller and signer
        address loanOwner = loanToken.ownerOf(extension.loanId);
        if (msg.sender == loanOwner) {
            if (extension.proposer != loan.borrower) {
                // If caller is loan owner, proposer must be borrower
                revert InvalidExtensionSigner({
                    allowed: loan.borrower,
                    current: extension.proposer
                });
            }
        } else if (msg.sender == loan.borrower) {
            if (extension.proposer != loanOwner) {
                // If caller is borrower, proposer must be loan owner
                revert InvalidExtensionSigner({
                    allowed: loanOwner,
                    current: extension.proposer
                });
            }
        } else {
            // Caller must be loan owner or borrower
            revert InvalidExtensionCaller();
        }

        // Check duration range
        if (extension.duration < MIN_EXTENSION_DURATION)
            revert InvalidExtensionDuration({
                duration: extension.duration,
                limit: MIN_EXTENSION_DURATION
            });
        if (extension.duration > MAX_EXTENSION_DURATION)
            revert InvalidExtensionDuration({
                duration: extension.duration,
                limit: MAX_EXTENSION_DURATION
            });

        // Revoke extension proposal nonce
        revokedNonce.revokeNonce(extension.proposer, extension.nonceSpace, extension.nonce);

        // Update loan
        uint40 originalDefaultTimestamp = loan.defaultTimestamp;
        loan.defaultTimestamp = originalDefaultTimestamp + extension.duration;

        // Emit event
        emit LOANExtended({
            loanId: extension.loanId,
            originalDefaultTimestamp: originalDefaultTimestamp,
            extendedDefaultTimestamp: loan.defaultTimestamp
        });

        // Skip compensation transfer if it's not set
        if (extension.compensationAddress != address(0) && extension.compensationAmount > 0) {
            MultiToken.Asset memory compensation = MultiToken.ERC20(
                extension.compensationAddress, extension.compensationAmount
            );

            // Check compensation asset validity
            _checkValidAsset(compensation);

            // Transfer compensation to the loan owner
            _permit(compensation, loan.borrower, compensationPermit);
            _pushFrom(compensation, loan.borrower, loanOwner);
        }
    }

    /**
     * @notice Get the hash of the extension struct.
     * @param extension Extension proposal struct.
     * @return Hash of the extension struct.
     */
    function getExtensionHash(ExtensionProposal calldata extension) public view returns (bytes32) {
        return keccak256(abi.encodePacked(
            hex"1901",
            DOMAIN_SEPARATOR,
            keccak256(abi.encodePacked(
                EXTENSION_PROPOSAL_TYPEHASH,
                abi.encode(extension)
            ))
        ));
    }


    /*----------------------------------------------------------*|
    |*  # GET LOAN                                              *|
    |*----------------------------------------------------------*/

    /**
     * @notice Return a LOAN data struct associated with a loan id.
     * @param loanId Id of a loan in question.
     * @return status LOAN status.
     * @return startTimestamp Unix timestamp (in seconds) of a loan creation date.
     * @return defaultTimestamp Unix timestamp (in seconds) of a loan default date.
     * @return borrower Address of a loan borrower.
     * @return originalLender Address of a loan original lender.
     * @return loanOwner Address of a LOAN token holder.
     * @return accruingInterestDailyRate Daily interest rate in basis points.
     * @return fixedInterestAmount Fixed interest amount in credit asset tokens.
     * @return credit Asset used as a loan credit. For a definition see { MultiToken dependency lib }.
     * @return collateral Asset used as a loan collateral. For a definition see { MultiToken dependency lib }.
     * @return repaymentAmount Loan repayment amount in credit asset tokens.
     */
    function getLOAN(uint256 loanId) external view returns (
        uint8 status,
        uint40 startTimestamp,
        uint40 defaultTimestamp,
        address borrower,
        address originalLender,
        address loanOwner,
        uint40 accruingInterestDailyRate,
        uint256 fixedInterestAmount,
        MultiToken.Asset memory credit,
        MultiToken.Asset memory collateral,
        uint256 repaymentAmount
    ) {
        LOAN storage loan = LOANs[loanId];

        status = _getLOANStatus(loanId);
        startTimestamp = loan.startTimestamp;
        defaultTimestamp = loan.defaultTimestamp;
        borrower = loan.borrower;
        originalLender = loan.originalLender;
        loanOwner = loan.status != 0 ? loanToken.ownerOf(loanId) : address(0);
        accruingInterestDailyRate = loan.accruingInterestDailyRate;
        fixedInterestAmount = loan.fixedInterestAmount;
        credit = MultiToken.ERC20(loan.creditAddress, loan.principalAmount);
        collateral = loan.collateral;
        repaymentAmount = loanRepaymentAmount(loanId);
    }

    /**
     * @notice Return a LOAN status associated with a loan id.
     * @param loanId Id of a loan in question.
     * @return status LOAN status.
     */
    function _getLOANStatus(uint256 loanId) private view returns (uint8) {
        LOAN storage loan = LOANs[loanId];
        return (loan.status == 2 && loan.defaultTimestamp <= block.timestamp) ? 4 : loan.status;
    }


    /*----------------------------------------------------------*|
    |*  # MultiToken                                            *|
    |*----------------------------------------------------------*/

    /**
     * @notice Check if the asset is valid with the MultiToken dependency lib and the category registry.
     * @dev See MultiToken.isValid for more details.
     * @param asset Asset to be checked.
     * @return True if the asset is valid.
     */
    function isValidAsset(MultiToken.Asset memory asset) public view returns (bool) {
        return MultiToken.isValid(asset, categoryRegistry);
    }

    /**
     * @notice Check if the asset is valid with the MultiToken lib and the category registry.
     * @dev The function will revert if the asset is not valid.
     * @param asset Asset to be checked.
     */
    function _checkValidAsset(MultiToken.Asset memory asset) private view {
        if (!isValidAsset(asset)) {
            revert InvalidMultiTokenAsset({
                category: uint8(asset.category),
                addr: asset.assetAddress,
                id: asset.id,
                amount: asset.amount
            });
        }
    }


    /*----------------------------------------------------------*|
    |*  # IPWNLoanMetadataProvider                              *|
    |*----------------------------------------------------------*/

    /**
     * @inheritdoc IPWNLoanMetadataProvider
     */
    function loanMetadataUri() override external view returns (string memory) {
        return config.loanMetadataUri(address(this));
    }


    /*----------------------------------------------------------*|
    |*  # ERC5646                                               *|
    |*----------------------------------------------------------*/

    /**
     * @inheritdoc IERC5646
     */
    function getStateFingerprint(uint256 tokenId) external view virtual override returns (bytes32) {
        LOAN storage loan = LOANs[tokenId];

        if (loan.status == 0)
            return bytes32(0);

        // The only mutable state properties are:
        // - status: updated for expired loans based on block.timestamp
        // - defaultTimestamp: updated when the loan is extended
        // - fixedInterestAmount: updated when the loan is repaid and waiting to be claimed
        // - accruingInterestDailyRate: updated when the loan is repaid and waiting to be claimed
        // Others don't have to be part of the state fingerprint as it does not act as a token identification.
        return keccak256(abi.encode(
            _getLOANStatus(tokenId),
            loan.defaultTimestamp,
            loan.fixedInterestAmount,
            loan.accruingInterestDailyRate
        ));
    }

}
