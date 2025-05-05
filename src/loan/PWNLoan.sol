// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken, IMultiTokenCategoryRegistry } from "MultiToken/MultiToken.sol";

import { ReentrancyGuard } from "openzeppelin/security/ReentrancyGuard.sol";
import { Math } from "openzeppelin/utils/math/Math.sol";

import { PWNConfig } from "pwn/config/PWNConfig.sol";
import { PWNHub } from "pwn/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/hub/PWNHubTags.sol";
import { IERC5646 } from "pwn/interfaces/IERC5646.sol";
import { IPWNLoanMetadataProvider } from "pwn/interfaces/IPWNLoanMetadataProvider.sol";
import { LOANStatus } from "pwn/lib/LOANStatus.sol";
import { PWNFeeCalculator } from "pwn/lib/PWNFeeCalculator.sol";
import { IPWNDefaultModule } from "pwn/loan/default/IPWNDefaultModule.sol";
import { IPWNInterestModule } from "pwn/loan/interest/IPWNInterestModule.sol";
import { PWNProposal } from "pwn/proposal/PWNProposal.sol";
import { LoanTerms as Terms } from "pwn/loan/LoanTerms.sol";
import { PWNVault } from "pwn/loan/PWNVault.sol";
import { PWNLOAN } from "pwn/token/PWNLOAN.sol";

/**
 * @title PWN Loan
 * @notice Contract managing loans in PWN protocol.
 * @dev Acts as a vault for every loan created by this contract.
 */
contract PWNLoan is PWNVault, ReentrancyGuard, IERC5646, IPWNLoanMetadataProvider {
    using MultiToken for address;

    string public constant VERSION = "1.5";

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    bytes32 public constant INTEREST_MODULE_RETURN_VALUE = keccak256("PWNInterestModule.onLoanCreated");
    bytes32 public constant DEFAULT_MODULE_RETURN_VALUE = keccak256("PWNDefaultModule.onLoanCreated");

    PWNHub public immutable hub;
    PWNLOAN public immutable loanToken;
    PWNConfig public immutable config;
    IMultiTokenCategoryRegistry public immutable categoryRegistry;

    /**
     * @notice Loan proposal specification during loan creation.
     * @param proposalContract Address of a loan proposal contract.
     * @param proposalData Encoded proposal data that is passed to the loan proposal contract.
     * @param proposalInclusionProof Inclusion proof of the proposal in the proposal contract.
     * @param signature Signature of the proposal.
     */
    struct ProposalSpec {
        address proposalContract;
        bytes proposalData;
        bytes32[] proposalInclusionProof;
        bytes signature;
    }

    // todo: lender & borrower spec

    /**
     * @notice Struct defining a loan.
     * @param borrower Address of a borrower.
     * @param lastUpdateTimestamp Unix timestamp (in seconds) of the last loan update.
     * @param collateral Asset used as a loan collateral. For a definition see { MultiToken dependency lib }.
     * @param creditAddress Address of an asset used as a loan credit.
     * @param principal Principal amount in credit asset tokens.
     * @param pastAccruedInterest Accrued interest amount in credit asset tokens before `lastUpdateTimestamp`.
     * @param unclaimedRepayment Amount of the credit asset that can be claimed by loan owner.
     * @param interestModule Address of an interest module. It is a contract which defines the interest conditions.
     * @param defaultModule Address of a default module. It is a contract which defines the default conditions.
     */
    struct LOAN {
        address borrower;
        uint40 lastUpdateTimestamp;
        MultiToken.Asset collateral;
        address creditAddress;
        uint256 principal;
        uint256 pastAccruedInterest;
        uint256 unclaimedRepayment;
        IPWNInterestModule interestModule;
        IPWNDefaultModule defaultModule;
    }

    /** Mapping of all LOAN data by loan id.*/
    mapping (uint256 => LOAN) private LOANs;


    /*----------------------------------------------------------*|
    |*  # EVENTS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /** @notice Emitted when a new loan in created.*/
    // todo: lender & borrower spec
    event LOANCreated(uint256 indexed loanId, bytes32 indexed proposalHash, address indexed proposalContract, Terms terms, bytes extra);
    /** @notice Emitted when a loan repayment is made.*/
    event LOANRepaymentMade(uint256 indexed loanId, uint256 repaymentAmount, uint256 newPrincipal);
    /** @notice Emitted when a loan is paid back.*/
    event LOANPaidBack(uint256 indexed loanId);
    /** @notice Emitted when a repaid or defaulted loan is claimed.*/
    event LOANClaimed(uint256 indexed loanId, uint256 claimedAmount, bool claimedCollateral);


    /*----------------------------------------------------------*|
    |*  # ERRORS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /** @notice Thrown when an address is missing a PWN Hub tag.*/
    error AddressMissingHubTag(address addr, bytes32 tag);
    /** @notice Thrown when managed loan is running.*/
    error LoanNotRunning();
    /** @notice Thrown when manged loan is still running.*/
    error LoanRunning();
    /** @notice Thrown when managed loan is repaid.*/
    error LoanRepaid();
    /** @notice Thrown when managed loan is not repaid.*/
    error LoanNotRepaid();
    /** @notice Thrown when managed loan is defaulted.*/
    error LoanDefaulted();
    /** @notice Thrown when loan doesn't exist.*/
    error NonExistingLoan();
    /** @notice Thrown when caller is not a LOAN token holder.*/
    error CallerNotLOANTokenHolder();
    /** @notice Thrown when refinancing loan terms have different borrower than the original loan.*/
    error RefinanceBorrowerMismatch(address currentBorrower, address newBorrower);
    /** @notice Thrown when refinancing loan terms have different credit asset than the original loan.*/
    error RefinanceCreditMismatch();
    /** @notice Thrown when refinancing loan terms have different collateral asset than the original loan.*/
    error RefinanceCollateralMismatch();
    /** @notice Thrown when hash of provided lender spec doesn't match the one in loan terms.*/
    error InvalidLenderSpecHash(bytes32 current, bytes32 expected);
    /** @notice Thrown when loan duration is below the minimum.*/
    error InvalidDuration(uint256 current, uint256 limit);
    /** @notice Thrown when accruing interest APR is above the maximum.*/
    error InterestAPROutOfBounds(uint256 current, uint256 limit);
    /** @notice Thrown when caller is not a vault.*/
    error CallerNotVault();
    /** @notice Thrown when pool based source of funds doesn't have a registered adapter.*/
    error InvalidSourceOfFunds(address sourceOfFunds);
    /** @notice Thrown when caller is not a loan borrower or lender.*/
    error InvalidExtensionCaller();
    /** @notice Thrown when signer is not a loan extension proposer.*/
    error InvalidExtensionSigner(address allowed, address current);
    /** @notice Thrown when loan extension duration is out of bounds.*/
    error InvalidExtensionDuration(uint256 duration, uint256 limit);
    /** @notice Thrown when MultiToken.Asset is invalid because of invalid category, address, id or amount.*/
    error InvalidMultiTokenAsset(uint8 category, address addr, uint256 id, uint256 amount);
    /** @notice Thrown when repayment amount is out of bounds.*/
    error InvalidRepaymentAmount(uint256 current, uint256 limit);
    /** @notice Thrown when nothing can be claimed.*/
    error NothingToClaim();
    /** @notice Thrown when hook returns an invalid value.*/
    error InvalidHookReturnValue(bytes32 expected, bytes32 current);


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
    |*  # LENDER & BORROWER SPEC                                *|
    |*----------------------------------------------------------*/

    // todo: lender & borrower spec


    /*----------------------------------------------------------*|
    |*  # CREATE LOAN                                           *|
    |*----------------------------------------------------------*/

    /**
     * @notice Create a new loan.
     * @dev The function assumes a prior token approval to a contract address.
     * @param proposalSpec Proposal specification struct.
     * @param extra Auxiliary data that are emitted in the loan creation event. They are not used in the contract logic.
     * @return loanId Id of the created LOAN token.
     */
    function createLOAN(
        ProposalSpec calldata proposalSpec,
        // todo: lender & borrower spec
        bytes calldata extra
    ) external nonReentrant returns (uint256 loanId) {
        // Check provided proposal contract
        if (!hub.hasTag(proposalSpec.proposalContract, PWNHubTags.LOAN_PROPOSAL)) {
            revert AddressMissingHubTag({ addr: proposalSpec.proposalContract, tag: PWNHubTags.LOAN_PROPOSAL });
        }

        // Accept proposal and get loan terms
        Terms memory loanTerms = PWNProposal(proposalSpec.proposalContract)
            .acceptProposal({
                acceptor: msg.sender,
                proposalData: proposalSpec.proposalData,
                proposalInclusionProof: proposalSpec.proposalInclusionProof,
                signature: proposalSpec.signature
            });

        // todo: check lender & borrower spec

        // Check loan credit and collateral validity
        _checkValidAsset(MultiToken.ERC20(loanTerms.creditAddress, loanTerms.principal));
        _checkValidAsset(loanTerms.collateral);

        // Create a new loan
        loanId = _createLoan(loanTerms);

        // Initialize interest module
        bytes32 hookReturnValue = loanTerms.interestModule.onLoanCreated(loanId, loanTerms.interestModuleProposerData);
        if (hookReturnValue != INTEREST_MODULE_RETURN_VALUE) {
            revert InvalidHookReturnValue({ expected: INTEREST_MODULE_RETURN_VALUE, current: hookReturnValue });
        }

        // Initialize default module
        hookReturnValue = loanTerms.defaultModule.onLoanCreated(loanId, loanTerms.defaultModuleProposerData);
        if (hookReturnValue != DEFAULT_MODULE_RETURN_VALUE) {
            revert InvalidHookReturnValue({ expected: DEFAULT_MODULE_RETURN_VALUE, current: hookReturnValue });
        }

        emit LOANCreated({
            loanId: loanId,
            proposalHash: loanTerms.proposalHash,
            proposalContract: proposalSpec.proposalContract,
            terms: loanTerms,
            // todo: lender & borrower spec
            extra: extra
        });

        // Settle the loan
        _settleNewLoan(loanTerms);
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
        loan.borrower = loanTerms.borrower;
        loan.lastUpdateTimestamp = uint40(block.timestamp);
        loan.creditAddress = loanTerms.creditAddress;
        loan.principal = loanTerms.principal;
        loan.collateral = loanTerms.collateral;
        loan.interestModule = loanTerms.interestModule;
        loan.defaultModule = loanTerms.defaultModule;
    }

    /**
     * @notice Transfer collateral to Vault and credit to borrower.
     * @dev The function assumes a prior token approval to a contract address.
     * @param loanTerms Loan terms struct.
     */
    function _settleNewLoan(
        Terms memory loanTerms
        // todo: lender & borrower spec
    ) private {
        // Transfer collateral to Vault
        _pull(loanTerms.collateral, loanTerms.borrower);

        // TODO: Hooks

        // Calculate fee amount and new loan amount
        (uint256 feeAmount, uint256 newLoanAmount)
            = PWNFeeCalculator.calculateFeeAmount(config.fee(), loanTerms.principal);

        // Note: `creditHelper` must not be used before updating the amount.
        MultiToken.Asset memory creditHelper = MultiToken.ERC20(loanTerms.creditAddress, loanTerms.principal);

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
     * The function assumes a prior token approval to Loan contract.
     * @param loanId Id of a loan that is being repaid.
     * @param repaymentAmount Amount of a credit asset to be repaid. Use 0 to repay the whole loan.
     */
    function repayLOAN(uint256 loanId, uint256 repaymentAmount) external nonReentrant {
        LOAN storage loan = LOANs[loanId];
        uint8 status = getLOANStatus(loanId);

        // Check that loan exists and is not from a different loan contract
        if (status == LOANStatus.DEAD) revert NonExistingLoan();
        // Check that loan is running
        if (status == LOANStatus.REPAID) revert LoanRepaid();
        // Check that loan is not defaulted
        if (status == LOANStatus.DEFAULTED) revert LoanDefaulted();

        // Check repayment amount
        uint256 debt = loanDebt(loanId);
        if (repaymentAmount == 0) {
            repaymentAmount = debt;
        } else if (repaymentAmount > debt) {
            revert InvalidRepaymentAmount({ current: repaymentAmount, limit: debt });
        }

        // Decrease debt by the repayment amount
        // Note: The accrued interest is repaid first, then principal.
        uint256 interest = debt - loan.principal;
        loan.pastAccruedInterest = repaymentAmount < interest ? interest - repaymentAmount : 0;
        loan.principal -= repaymentAmount > interest ? repaymentAmount - interest : 0;
        loan.unclaimedRepayment += repaymentAmount;
        loan.lastUpdateTimestamp = uint40(block.timestamp);

        emit LOANRepaymentMade({ loanId: loanId, repaymentAmount: repaymentAmount, newPrincipal: loan.principal });

        // Transfer the repaid credit to the Vault
        _pull(loan.creditAddress.ERC20(repaymentAmount), msg.sender);

        // If loan is fully repaid, transfer collateral to borrower
        if (loan.principal == 0) {
            _push(loan.collateral, loan.borrower);
            emit LOANPaidBack({ loanId: loanId });
        }
    }


    /*----------------------------------------------------------*|
    |*  # LOAN DEBT                                             *|
    |*----------------------------------------------------------*/

    /**
     * @notice Calculate the total debt of a loan.
     * @dev The total debt is the sum of the principal amount and accrued interest.
     * @param loanId Id of a loan.
     * @return Total debt.
     */
    function loanDebt(uint256 loanId) public view returns (uint256) {
        LOAN storage loan = LOANs[loanId];
        return loan.principal + loan.interestModule.interest(address(this), loanId);
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
        uint8 status = getLOANStatus(loanId);
        // Loan is not existing or from a different loan contract
        if (status == LOANStatus.DEAD) revert NonExistingLoan();
        // Check that there is something to claim
        if (loan.unclaimedRepayment == 0 && status != LOANStatus.DEFAULTED) revert NothingToClaim();

        emit LOANClaimed({
            loanId: loanId,
            claimedAmount: loan.unclaimedRepayment,
            claimedCollateral: status == LOANStatus.DEFAULTED
        });

        MultiToken.Asset memory unclaimedCredit = loan.creditAddress.ERC20(loan.unclaimedRepayment);
        MultiToken.Asset memory collateral = loan.collateral;

        // Note: Both unclaimed amount and collateral are claimed in the one transaction.

        if (status == LOANStatus.RUNNING) {
            loan.unclaimedRepayment = 0;
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
     * @return loan LOAN data struct.
     */
    function getLOAN(uint256 loanId) external view returns (LOAN memory) {
        return LOANs[loanId];
    }

    /**
     * @notice Return a LOAN status associated with a loan id.
     * @param loanId Id of a loan.
     * @return status LOAN status.
     */
    function getLOANStatus(uint256 loanId) public view returns (uint8) {
        LOAN storage loan = LOANs[loanId];
        if (loan.principal == 0) {
            return loan.unclaimedRepayment == 0 ? LOANStatus.DEAD : LOANStatus.REPAID;
        } else {
            return loan.defaultModule.isDefaulted(address(this), loanId) ? LOANStatus.DEFAULTED : LOANStatus.RUNNING;
        }
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

    /** @inheritdoc IPWNLoanMetadataProvider*/
    function loanMetadataUri() override external view returns (string memory) {
        return config.loanMetadataUri(address(this));
    }


    /*----------------------------------------------------------*|
    |*  # ERC5646                                               *|
    |*----------------------------------------------------------*/

    /** @inheritdoc IERC5646*/
    function getStateFingerprint(uint256 tokenId) external view virtual override returns (bytes32) {
        LOAN storage loan = LOANs[tokenId];
        uint8 status = getLOANStatus(tokenId);
        if (status == LOANStatus.DEAD)
            return bytes32(0);

        // The only mutable state properties are:
        // - status: updated for repaid or defaulted loans
        // - lastUpdateTimestamp: updated on every loan repayment
        // - pastAccruedInterest: used to store currently unpaid accrued interest on every loan repayment
        // - principal: decreased on every loan repayment
        // - unclaimedRepayment: increased on every loan repayment
        // Others don't have to be part of the state fingerprint as it does not act as a token identification.
        return keccak256(abi.encode(
            status,
            loan.lastUpdateTimestamp,
            loan.pastAccruedInterest,
            loan.principal,
            loan.unclaimedRepayment
        ));
    }

}
