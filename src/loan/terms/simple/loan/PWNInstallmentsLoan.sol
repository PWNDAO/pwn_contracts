// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken, IMultiTokenCategoryRegistry } from "MultiToken/MultiToken.sol";

import { ReentrancyGuard } from "openzeppelin/security/ReentrancyGuard.sol";
import { Math } from "openzeppelin/utils/math/Math.sol";
import { SafeCast } from "openzeppelin/utils/math/SafeCast.sol";

import { PWNConfig } from "pwn/config/PWNConfig.sol";
import { PWNHub } from "pwn/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/hub/PWNHubTags.sol";
import { IERC5646 } from "pwn/interfaces/IERC5646.sol";
import { IPWNLenderHook } from "pwn/interfaces/IPWNLenderHook.sol";
import { IPWNLoanMetadataProvider } from "pwn/interfaces/IPWNLoanMetadataProvider.sol";
import { LOANStatus } from "pwn/loan/lib/LOANStatus.sol";
import { PWNFeeCalculator } from "pwn/loan/lib/PWNFeeCalculator.sol";
import { PWNSimpleLoanProposal } from "pwn/loan/terms/simple/proposal/PWNSimpleLoanProposal.sol";
import { SimpleTerms as Terms } from "pwn/loan/terms/simple/SimpleTerms.sol";
import { PWNLOAN } from "pwn/loan/token/PWNLOAN.sol";
import { PWNVault } from "pwn/loan/vault/PWNVault.sol";
import { AddressMissingHubTag } from "pwn/PWNErrors.sol";


/**
 * @title PWN Installments Loan
 * @notice Contract managing a loan with flexible installments in PWN protocol.
 * @dev Acts as a vault for every loan created by this contract.
 */
contract PWNInstallmentsLoan is PWNVault, ReentrancyGuard, IERC5646, IPWNLoanMetadataProvider {
    using MultiToken for address;

    string public constant VERSION = "1.0";

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    uint32 public constant MIN_LOAN_DURATION = 180 days;
    uint40 public constant MAX_ACCRUING_INTEREST_APR = 160_000e2; // 160,000 APR (with 2 decimals)

    uint256 public constant ACCRUING_INTEREST_APR_DECIMALS = 1e2;
    uint256 public constant MINUTES_IN_YEAR = 365 days / 1 minutes; // Note: Assuming 365 days in a year
    uint256 public constant ACCRUING_INTEREST_APR_DENOMINATOR = ACCRUING_INTEREST_APR_DECIMALS * MINUTES_IN_YEAR * 100;

    uint256 public constant DEBT_LIMIT_POSTPONEMENT = 120 days;
    uint256 public constant DEBT_LIMIT_TANGENT_DECIMALS = 8;

    PWNHub public immutable hub;
    PWNLOAN public immutable loanToken;
    PWNConfig public immutable config;
    IMultiTokenCategoryRegistry public immutable categoryRegistry;

    /**
     * @notice Loan proposal specification during loan creation.
     * @param proposalContract Address of a loan proposal contract.
     * @param proposalData Encoded proposal data that is passed to the loan proposal contract.
     * @param signature Signature of the proposal.
     */
    struct ProposalSpec {
        address proposalContract;
        bytes proposalData;
        bytes signature;
    }

    /**
     * @notice Lender specification during loan creation.
     * @param lenderHook Address of a lender hook contract that will be called before credit transfer.
     * @param lenderHookParameters Data that is passed to the lender hook contract as lender parameters.
     */
    struct LenderSpec {
        IPWNLenderHook lenderHook;
        bytes lenderHookParameters;
    }

    /**
     * @notice Struct defining a simple loan.
     * @param creditAddress Address of an asset used as a loan credit.
     * @param lastUpdateTimestamp Unix timestamp (in seconds) of the last loan update.
     * @param defaultTimestamp Unix timestamp (in seconds) of a default date.
     * @param borrower Address of a borrower.
     * @param accruingInterestAPR Accruing interest APR with 2 decimals.
     * @param fixedInterestAmount Fixed interest amount in credit asset tokens.
     * It is the minimum amount of interest which has to be paid by a borrower.
     * This property is reused to store the final interest amount if the loan is repaid and waiting to be claimed.
     * @param principalAmount Principal amount in credit asset tokens.
     * @param unclaimedAmount Amount of the credit asset that can be claimed by loan owner.
     * @param collateral Asset used as a loan collateral. For a definition see { MultiToken dependency lib }.
     */
    struct LOAN {
        address creditAddress;
        uint40 lastUpdateTimestamp;
        uint40 defaultTimestamp;
        address borrower;
        uint24 accruingInterestAPR;
        uint256 fixedInterestAmount;
        uint256 principalAmount;
        uint256 unclaimedAmount;
        uint256 debtLimitTangent;
        MultiToken.Asset collateral;
    }

    /**
     * Mapping of all LOAN data by loan id.
     */
    mapping (uint256 => LOAN) private LOANs;


    /*----------------------------------------------------------*|
    |*  # EVENTS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /**
     * @notice Emitted when a new loan in created.
     */
    event LOANCreated(uint256 indexed loanId, bytes32 indexed proposalHash, address indexed proposalContract, Terms terms, LenderSpec lenderSpec, bytes extra);

    /**
     * @notice Emitted when a loan repayment is made.
     */
    event LOANRepaymentMade(uint256 indexed loanId, uint256 repaymentAmount, uint256 newPrincipal);

    /**
     * @notice Emitted when a loan is paid back.
     */
    event LOANPaidBack(uint256 indexed loanId);

    /**
     * @notice Emitted when a repaid or defaulted loan is claimed.
     */
    event LOANClaimed(uint256 indexed loanId, uint256 claimedAmount, bool claimedCollateral);


    /*----------------------------------------------------------*|
    |*  # ERRORS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /**
     * @notice Thrown when managed loan is running.
     */
    error LoanNotRunning();

    /**
     * @notice Thrown when manged loan is still running.
     */
    error LoanRunning();

    /**
     * @notice Thrown when managed loan is defaulted.
     */
    error LoanDefaulted(uint40 timestap);

    /**
     * @notice Thrown when loan doesn't exist.
     */
    error NonExistingLoan();

    /**
     * @notice Thrown when loan is repaid.
     */
    error LoanRepaid();

    /**
     * @notice Thrown when caller is not a LOAN token holder.
     */
    error CallerNotLOANTokenHolder();

    /**
     * @notice Thrown when hash of provided lender spec doesn't match the one in loan terms.
     */
    error InvalidLenderSpecHash(bytes32 current, bytes32 expected);

    /**
     * @notice Thrown when loan duration is below the minimum.
     */
    error InvalidDuration(uint256 current, uint256 limit);

    /**
     * @notice Thrown when accruing interest APR is above the maximum.
     */
    error InterestAPROutOfBounds(uint256 current, uint256 limit);

    /**
     * @notice Thrown when MultiToken.Asset is invalid.
     * @dev Could be because of invalid category, address, id or amount.
     */
    error InvalidMultiTokenAsset(uint8 category, address addr, uint256 id, uint256 amount);

    /**
     * @notice Thrown when repayment amount is out of bounds.
     */
    error InvalidRepaymentAmount(uint256 current, uint256 limit);

    /**
     * @notice Thrown when nothing can be claimed.
     */
    error NothingToClaim();


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(
        address _hub,
        address _loanToken,
        address _config,
        address _categoryRegistry
    ) {
        hub = PWNHub(_hub);
        loanToken = PWNLOAN(_loanToken);
        config = PWNConfig(_config);
        categoryRegistry = IMultiTokenCategoryRegistry(_categoryRegistry);
    }


    /*----------------------------------------------------------*|
    |*  # LENDER SPEC                                           *|
    |*----------------------------------------------------------*/

    /**
     * @notice Get hash of a lender specification.
     * @param lenderSpec Lender specification struct.
     * @return Hash of a lender specification.
     */
    function getLenderSpecHash(LenderSpec calldata lenderSpec) public pure returns (bytes32) {
        return keccak256(abi.encode(lenderSpec));
    }


    /*----------------------------------------------------------*|
    |*  # CREATE LOAN                                           *|
    |*----------------------------------------------------------*/

    /**
     * @notice Create a new loan.
     * @dev The function assumes a prior token approval to a contract address.
     * @param proposalSpec Proposal specification struct.
     * @param lenderSpec Lender specification struct.
     * @param extra Auxiliary data that are emitted in the loan creation event. They are not used in the contract logic.
     * @return loanId Id of the created LOAN token.
     */
    function createLOAN(
        ProposalSpec calldata proposalSpec,
        LenderSpec calldata lenderSpec,
        bytes calldata extra
    ) external nonReentrant returns (uint256 loanId) {
        // Check provided proposal contract
        if (!hub.hasTag(proposalSpec.proposalContract, PWNHubTags.LOAN_PROPOSAL)) {
            revert AddressMissingHubTag({ addr: proposalSpec.proposalContract, tag: PWNHubTags.LOAN_PROPOSAL });
        }

        // Accept proposal and get loan terms
        (bytes32 proposalHash, Terms memory loanTerms) = PWNSimpleLoanProposal(proposalSpec.proposalContract)
            .acceptProposal({
                acceptor: msg.sender,
                refinancingLoanId: 0,
                proposalData: proposalSpec.proposalData,
                proposalInclusionProof: new bytes32[](0),
                signature: proposalSpec.signature
            });

        // Check that provided lender spec is correct
        if (msg.sender != loanTerms.lender) {
            if (loanTerms.lenderSpecHash != bytes32(0) && loanTerms.lenderSpecHash != getLenderSpecHash(lenderSpec)) {
                revert InvalidLenderSpecHash({ current: loanTerms.lenderSpecHash, expected: getLenderSpecHash(lenderSpec) });
            } else if (loanTerms.lenderSpecHash == bytes32(0) && address(lenderSpec.lenderHook) != address(0)) {
                revert InvalidLenderSpecHash({ current: loanTerms.lenderSpecHash, expected: getLenderSpecHash(lenderSpec) });
            }
        }

        // Check minimum loan duration
        if (loanTerms.duration < MIN_LOAN_DURATION) {
            revert InvalidDuration({ current: loanTerms.duration, limit: MIN_LOAN_DURATION });
        }

        // Check maximum accruing interest APR
        if (loanTerms.accruingInterestAPR > MAX_ACCRUING_INTEREST_APR) {
            revert InterestAPROutOfBounds({ current: loanTerms.accruingInterestAPR, limit: MAX_ACCRUING_INTEREST_APR });
        }

        _checkValidAsset(loanTerms.credit);
        _checkValidAsset(loanTerms.collateral);

        // Create a new loan
        loanId = _createLoan(loanTerms);

        emit LOANCreated({
            loanId: loanId,
            proposalHash: proposalHash,
            proposalContract: proposalSpec.proposalContract,
            terms: loanTerms,
            lenderSpec: lenderSpec,
            extra: extra
        });

        _settleNewLoan(loanId, proposalHash, loanTerms, lenderSpec);
    }

    /**
     * @notice Mint LOAN token and store loan data under loan id.
     * @param loanTerms Loan terms struct.
     */
    function _createLoan(Terms memory loanTerms) private returns (uint256 loanId) {
        // Mint LOAN token for lender
        loanId = loanToken.mint(loanTerms.lender);

        // Store loan data under loan id
        LOAN storage loan = LOANs[loanId];
        loan.creditAddress = loanTerms.credit.assetAddress;
        loan.lastUpdateTimestamp = uint40(block.timestamp);
        loan.defaultTimestamp = uint40(block.timestamp) + loanTerms.duration;
        loan.borrower = loanTerms.borrower;
        loan.accruingInterestAPR = loanTerms.accruingInterestAPR;
        loan.fixedInterestAmount = loanTerms.fixedInterestAmount;
        loan.principalAmount = loanTerms.credit.amount;
        loan.collateral = loanTerms.collateral;
        loan.debtLimitTangent = _debtLimitTangent(loanTerms.credit.amount, loanTerms.fixedInterestAmount, loanTerms.duration);
    }

    /**
     * @notice Calculate the debt limit tangent.
     * @param principalAmount Principal amount in credit asset tokens.
     * @param duration Loan duration in seconds.
     * @return Debt limit tangent.
     */
    function _debtLimitTangent(uint256 principalAmount, uint256 fixedInterestAmount, uint256 duration) internal pure returns (uint256) {
        return Math.mulDiv(
            principalAmount + fixedInterestAmount, 10 ** DEBT_LIMIT_TANGENT_DECIMALS,
            duration - DEBT_LIMIT_POSTPONEMENT
        );
    }

    /**
     * @notice Transfer collateral to Vault and credit to borrower.
     * @dev The function assumes a prior token approval to a contract address.
     * @param loanTerms Loan terms struct.
     */
    function _settleNewLoan(uint256 loanId, bytes32 proposalHash, Terms memory loanTerms, LenderSpec calldata lenderSpec) private {
        // Transfer collateral to Vault
        _pull(loanTerms.collateral, loanTerms.borrower);

        // Call lender hook
        if (address(lenderSpec.lenderHook) != address(0)) {
            lenderSpec.lenderHook.onLoanCreated({
                loanId: loanId,
                proposalHash: proposalHash,
                lender: loanTerms.lender,
                creditAddress: loanTerms.credit.assetAddress,
                creditAmount: loanTerms.credit.amount,
                lenderParameters: lenderSpec.lenderHookParameters
            });
        }

        // Calculate fee amount and new loan amount
        (uint256 feeAmount, uint256 newLoanAmount)
            = PWNFeeCalculator.calculateFeeAmount(config.fee(), loanTerms.credit.amount);

        // Note: `creditHelper` must not be used before updating the amount.
        MultiToken.Asset memory creditHelper = loanTerms.credit;

        // Collect fees
        if (feeAmount > 0) {
            creditHelper.amount = feeAmount;
            _pushFrom(creditHelper, loanTerms.lender, config.feeCollector());
        }

        // Transfer credit to borrower
        creditHelper.amount = newLoanAmount;
        _pushFrom(creditHelper, loanTerms.lender, loanTerms.borrower);
    }


    /*----------------------------------------------------------*|
    |*  # REPAY LOAN                                            *|
    |*----------------------------------------------------------*/

    /**
     * @notice Repay running loan.
     * @dev Any address can repay a running loan, but a collateral will be transferred to a borrower address associated with the loan.
     *      The function assumes a prior token approval to a contract address.
     * @param loanId Id of a loan that is being repaid.
     * @param repaymentAmount Amount of a credit asset to be repaid. Use 0 to repay the whole loan.
     */
    function repayLOAN(uint256 loanId, uint256 repaymentAmount) external nonReentrant {
        LOAN storage loan = LOANs[loanId];
        uint8 status = _getLOANStatus(loan);
        // Check that loan exists and is not from a different loan contract
        if (status == LOANStatus.DEAD) revert NonExistingLoan();
        // Check that loan is running
        if (status == LOANStatus.REPAID) revert LoanRepaid();
        // Check that loan is not defaulted
        if (status == LOANStatus.DEFAULTED) revert LoanDefaulted({ timestap: loan.defaultTimestamp });

        // Check repayment amount
        uint256 maxRepaymentAmount = _totalDebt(loan);
        if (repaymentAmount == 0) {
            repaymentAmount = maxRepaymentAmount;
        } else if (repaymentAmount > maxRepaymentAmount) {
            revert InvalidRepaymentAmount({ current: repaymentAmount, limit: maxRepaymentAmount });
        }

        // Decrease debt by the repayment amount
        // Note: The accrued interest is repaid first, then principal.
        uint256 interest = maxRepaymentAmount - loan.principalAmount;
        loan.fixedInterestAmount = repaymentAmount < interest ? interest - repaymentAmount : 0;
        loan.principalAmount -= repaymentAmount > interest ? repaymentAmount - interest : 0;
        loan.unclaimedAmount += repaymentAmount;
        loan.lastUpdateTimestamp = uint40(block.timestamp);

        emit LOANRepaymentMade({ loanId: loanId, repaymentAmount: repaymentAmount, newPrincipal: loan.principalAmount });

        // Transfer the repaid credit to the Vault
        _pull(loan.creditAddress.ERC20(repaymentAmount), msg.sender);

        // If loan is fully repaid, transfer collateral to borrower
        if (loan.principalAmount == 0) {
            _push(loan.collateral, loan.borrower);
            emit LOANPaidBack({ loanId: loanId });
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
        return _totalDebt(LOANs[loanId]);
    }

    /**
     * @notice Calculate the total debt of a loan.
     * @dev The total debt is the sum of the principal amount, fixed interest amount and accrued interest.
     * @param loan Storage pointer to a LOAN struct.
     * @return Total debt.
     */
    function _totalDebt(LOAN storage loan) internal view returns (uint256) {
        uint256 accruingMinutes = (block.timestamp - loan.lastUpdateTimestamp) / 1 minutes;
        uint256 accruedInterest = Math.mulDiv(
            loan.principalAmount, uint256(loan.accruingInterestAPR) * accruingMinutes,
            ACCRUING_INTEREST_APR_DENOMINATOR
        );
        return loan.principalAmount + loan.fixedInterestAmount + accruedInterest;
    }


    /*----------------------------------------------------------*|
    |*  # CLAIM LOAN                                            *|
    |*----------------------------------------------------------*/

    /**
     * @notice Claim a repaid or defaulted loan.
     * @dev Only a LOAN token holder can claim a repaid or defaulted loan.
     * Claim will transfer the repaid credit or collateral to a LOAN token holder address and burn the LOAN token.
     * @param loanId Id of a loan that is being claimed.
     */
    function claimLOAN(uint256 loanId) external nonReentrant {
        // Check that caller is LOAN token holder
        if (loanToken.ownerOf(loanId) != msg.sender) revert CallerNotLOANTokenHolder();

        LOAN storage loan = LOANs[loanId];
        uint8 status = _getLOANStatus(loan);
        // Loan is not existing or from a different loan contract
        if (status == LOANStatus.DEAD) revert NonExistingLoan();
        // Check that there is something to claim
        if (loan.unclaimedAmount == 0 && status != LOANStatus.DEFAULTED) revert NothingToClaim();

        emit LOANClaimed({
            loanId: loanId,
            claimedAmount: loan.unclaimedAmount,
            claimedCollateral: status == LOANStatus.DEFAULTED
        });

        MultiToken.Asset memory unclaimedCredit = loan.creditAddress.ERC20(loan.unclaimedAmount);
        MultiToken.Asset memory collateral = loan.collateral;

        // Note: Both unclaimed amount and collateral are claimed in the one transaction.

        if (status == LOANStatus.RUNNING) {
            loan.unclaimedAmount = 0;
        } else {
            _deleteLoan(loanId);
        }

        // Transfer defaulted collateral to the loan owner
        if (status == LOANStatus.DEFAULTED) _push(collateral, msg.sender);
        // Transfer unclaimed amount to the loan owner
        if (unclaimedCredit.amount > 0) _push(unclaimedCredit, msg.sender);
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
    |*  # GET LOAN                                              *|
    |*----------------------------------------------------------*/

    /**
     * @notice Return a LOAN data struct associated with a loan id.
     * @param loanId Id of a loan.
     * @return status LOAN status.
     * @return loan LOAN data struct.
     */
    function getLOAN(uint256 loanId) external view returns (uint8, LOAN memory) {
        LOAN storage loan = LOANs[loanId];
        return (_getLOANStatus(loan), loan);
    }

    /**
     * @notice Return a default debt limit value.
     * @dev The default debt limit is a linear decreasing function of the total debt from the original debt amount
     * at the time of loan creation postponed by `DEBT_LIMIT_POSTPONEMENT` to 0 at the default timestamp.
     * @param loanId Id of a loan.
     * @param timestamp Timestamp to calculate the default debt limit. Use 0 for the current timestamp.
     * @return Default debt limit.
     */
    function getDefaultDebtLimit(uint256 loanId, uint256 timestamp) external view returns (uint256) {
        return _defaultDebtLimit(LOANs[loanId], timestamp);
    }

    /**
     * @notice Return a LOAN status associated with a loan id.
     * @param loan Storage pointer to a LOAN struct.
     * @return status LOAN status.
     */
    function _getLOANStatus(LOAN storage loan) internal view returns (uint8) {
        if (loan.principalAmount == 0) {
            return loan.unclaimedAmount == 0 ? LOANStatus.DEAD : LOANStatus.REPAID;
        } else {
            return _totalDebt(loan) > _defaultDebtLimit(loan, 0) ? LOANStatus.DEFAULTED : LOANStatus.RUNNING;
        }
    }

    /**
     * @notice Calculate the default debt limit.
     * @dev The default debt limit is a linear decreasing function of the total debt from the original debt amount
     * at the time of loan creation postponed by `DEBT_LIMIT_POSTPONEMENT` to 0 at the default timestamp.
     * @param loan Storage pointer to a LOAN struct.
     * @param timestamp Timestamp to calculate the default debt limit.
     * @return Default debt limit.
     */
    function _defaultDebtLimit(LOAN storage loan, uint256 timestamp) internal view returns (uint256) {
        timestamp = timestamp == 0 ? block.timestamp : timestamp;
        if (timestamp >= loan.defaultTimestamp) {
            return 0;
        }

        return Math.mulDiv(
            loan.debtLimitTangent, uint256(loan.defaultTimestamp) - timestamp,
            10 ** DEBT_LIMIT_TANGENT_DECIMALS
        );
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

        uint8 status = _getLOANStatus(loan);
        if (status == LOANStatus.DEAD)
            return bytes32(0);

        // The only mutable state properties are:
        // - status: updated for expired loans based on block.timestamp
        // - lastUpdateTimestamp: updated on every loan repayment
        // - fixedInterestAmount: used to store currently unpaid accrued interest on every loan repayment
        // - principalAmount: decreased on every loan repayment
        // - unclaimedAmount: increased on every loan repayment
        // Others don't have to be part of the state fingerprint as it does not act as a token identification.
        return keccak256(abi.encode(
            status,
            loan.lastUpdateTimestamp,
            loan.fixedInterestAmount,
            loan.principalAmount,
            loan.unclaimedAmount
        ));
    }

}
