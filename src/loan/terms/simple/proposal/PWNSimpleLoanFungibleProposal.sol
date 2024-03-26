// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import { PWNSimpleLoan } from "@pwn/loan/terms/simple/loan/PWNSimpleLoan.sol";
import { PWNSimpleLoanProposal } from "@pwn/loan/terms/simple/proposal/PWNSimpleLoanProposal.sol";
import { Permit } from "@pwn/loan/vault/Permit.sol";
import "@pwn/PWNErrors.sol";


/**
 * @title PWN Simple Loan Fungible Proposal
 * @notice Contract for creating and accepting fungible loan proposals.
 *         Proposals are fungible, which means that they are not tied to a specific collateral or credit amount.
 *         The amount of collateral and credit is specified during the proposal acceptance.
 */
contract PWNSimpleLoanFungibleProposal is PWNSimpleLoanProposal {

    string public constant VERSION = "1.0";

    /**
     * @notice Credit per collateral unit denominator. It is used to calculate credit amount from collateral amount.
     */
    uint256 public constant CREDIT_PER_COLLATERAL_UNIT_DENOMINATOR = 1e38;

    /**
     * @dev EIP-712 simple proposal struct type hash.
     */
    bytes32 public constant PROPOSAL_TYPEHASH = keccak256(
        "Proposal(uint8 collateralCategory,address collateralAddress,uint256 collateralId,uint256 minCollateralAmount,bool checkCollateralStateFingerprint,bytes32 collateralStateFingerprint,address creditAddress,uint256 creditPerCollateralUnit,uint256 availableCreditLimit,uint256 fixedInterestAmount,uint40 accruingInterestAPR,uint32 duration,uint40 expiration,address allowedAcceptor,address proposer,bool isOffer,uint256 refinancingLoanId,uint256 nonceSpace,uint256 nonce,address loanContract)"
    );

    /**
     * @notice Construct defining a fungible proposal.
     * @param collateralCategory Category of an asset used as a collateral (0 == ERC20, 2 == ERC1155).
     * @param collateralAddress Address of an asset used as a collateral.
     * @param collateralId Token id of an asset used as a collateral, in case of ERC20 should be 0.
     * @param minCollateralAmount Minimal amount of tokens used as a collateral.
     * @param checkCollateralStateFingerprint If true, collateral state fingerprint will be checked on loan terms creation.
     * @param collateralStateFingerprint Fingerprint of a collateral state. It is used to check if a collateral is in a valid state.
     * @param creditAddress Address of an asset which is lended to a borrower.
     * @param creditPerCollateralUnit Amount of tokens which are offered per collateral unit with 38 decimals.
     * @param availableCreditLimit Available credit limit for the proposal. It is the maximum amount of tokens which can be borrowed using the proposal.
     * @param fixedInterestAmount Fixed interest amount in credit tokens. It is the minimum amount of interest which has to be paid by a borrower.
     * @param accruingInterestAPR Accruing interest APR.
     * @param duration Loan duration in seconds.
     * @param expiration Proposal expiration timestamp in seconds.
     * @param allowedAcceptor Address that is allowed to accept proposal. If the address is zero address, anybody can accept the proposal.
     * @param proposer Address of a proposal signer. If `isOffer` is true, the proposer is the lender. If `isOffer` is false, the proposer is the borrower.
     * @param isOffer If true, the proposal is an offer. If false, the proposal is a request.
     * @param refinancingLoanId Id of a loan which is refinanced by this proposal. If the id is 0 and `isOffer` is true, the proposal can refinance any loan.
     * @param nonceSpace Nonce space of a proposal nonce. All nonces in the same space can be revoked at once.
     * @param nonce Additional value to enable identical proposals in time. Without it, it would be impossible to make again proposal, which was once revoked.
     *              Can be used to create a group of proposals, where accepting one will make others in the group invalid.
     * @param loanContract Address of a loan contract that will create a loan from the proposal.
     */
    struct Proposal {
        MultiToken.Category collateralCategory;
        address collateralAddress;
        uint256 collateralId;
        uint256 minCollateralAmount;
        bool checkCollateralStateFingerprint;
        bytes32 collateralStateFingerprint;
        address creditAddress;
        uint256 creditPerCollateralUnit;
        uint256 availableCreditLimit;
        uint256 fixedInterestAmount;
        uint40 accruingInterestAPR;
        uint32 duration;
        uint40 expiration;
        address allowedAcceptor;
        address proposer;
        bool isOffer;
        uint256 refinancingLoanId;
        uint256 nonceSpace;
        uint256 nonce;
        address loanContract;
    }

    /**
     * @notice Construct defining proposal concrete values.
     * @param collateralAmount Amount of collateral to be used in the loan.
     */
    struct ProposalValues {
        uint256 collateralAmount;
    }

    /**
     * @dev Emitted when a proposal is made via an on-chain transaction.
     */
    event ProposalMade(bytes32 indexed proposalHash, address indexed proposer, Proposal proposal);

    constructor(
        address _hub,
        address _revokedNonce,
        address _config
    ) PWNSimpleLoanProposal(_hub, _revokedNonce, _config, "PWNSimpleLoanFungibleProposal", VERSION) {}

    /**
     * @notice Get an proposal hash according to EIP-712
     * @param proposal Proposal struct to be hashed.
     * @return Proposal struct hash.
     */
    function getProposalHash(Proposal calldata proposal) public view returns (bytes32) {
        return _getProposalHash(PROPOSAL_TYPEHASH, abi.encode(proposal));
    }

    /**
     * @notice Make an on-chain proposal.
     * @dev Function will mark a proposal hash as proposed.
     * @param proposal Proposal struct containing all needed proposal data.
     * @return proposalHash Proposal hash.
     */
    function makeProposal(Proposal calldata proposal) external returns (bytes32 proposalHash) {
        proposalHash = getProposalHash(proposal);
        _makeProposal(proposalHash, proposal.proposer);
        emit ProposalMade(proposalHash, proposal.proposer, proposal);
    }

    /**
     * @notice Compute credit amount from collateral amount and credit per collateral unit.
     * @param collateralAmount Amount of collateral.
     * @param creditPerCollateralUnit Amount of credit per collateral unit with 38 decimals.
     * @return Amount of credit.
     */
    function getCreditAmount(uint256 collateralAmount, uint256 creditPerCollateralUnit) public pure returns (uint256) {
        return Math.mulDiv(collateralAmount, creditPerCollateralUnit, CREDIT_PER_COLLATERAL_UNIT_DENOMINATOR);
    }

    /**
     * @notice Accept a proposal.
     * @param proposal Proposal struct containing all proposal data.
     * @param proposalValues ProposalValues struct specifying all flexible proposal values.
     * @param signature Proposal signature signed by a proposer.
     * @param permit Callers permit data.
     * @param extra Auxiliary data that are emitted in the loan creation event. They are not used in the contract logic.
     * @return loanId Id of a created loan.
     */
    function acceptProposal(
        Proposal calldata proposal,
        ProposalValues calldata proposalValues,
        bytes calldata signature,
        Permit calldata permit,
        bytes calldata extra
    ) public returns (uint256 loanId) {
        // Check if the proposal is refinancing proposal
        if (proposal.refinancingLoanId != 0) {
            revert InvalidRefinancingLoanId({ refinancingLoanId: proposal.refinancingLoanId });
        }

        // Check permit
        _checkPermit(msg.sender, proposal.creditAddress, permit);

        // Accept proposal
        (bytes32 proposalHash, PWNSimpleLoan.Terms memory loanTerms)
            = _acceptProposal(proposal, proposalValues, signature);

        // Create loan
        return PWNSimpleLoan(proposal.loanContract).createLOAN({
            proposalHash: proposalHash,
            loanTerms: loanTerms,
            permit: permit,
            extra: extra
        });
    }

    /**
     * @notice Accept a refinancing proposal.
     * @param loanId Id of a loan to be refinanced.
     * @param proposal Proposal struct containing all proposal data.
     * @param proposalValues ProposalValues struct specifying all flexible proposal values.
     * @param signature Proposal signature signed by a proposer.
     * @param permit Callers permit data.
     * @param extra Auxiliary data that are emitted in the loan creation event. They are not used in the contract logic.
     * @return refinancedLoanId Id of a created refinanced loan.
     */
    function acceptRefinanceProposal(
        uint256 loanId,
        Proposal calldata proposal,
        ProposalValues calldata proposalValues,
        bytes calldata signature,
        Permit calldata permit,
        bytes calldata extra
    ) public returns (uint256 refinancedLoanId) {
        // Check if the proposal is refinancing proposal
        if (proposal.refinancingLoanId != loanId) {
            if (proposal.refinancingLoanId != 0 || !proposal.isOffer) {
                revert InvalidRefinancingLoanId({ refinancingLoanId: proposal.refinancingLoanId });
            }
        }

        // Check permit
        _checkPermit(msg.sender, proposal.creditAddress, permit);

        // Accept proposal
        (bytes32 proposalHash, PWNSimpleLoan.Terms memory loanTerms)
            = _acceptProposal(proposal, proposalValues, signature);

        // Refinance loan
        return PWNSimpleLoan(proposal.loanContract).refinanceLOAN({
            loanId: loanId,
            proposalHash: proposalHash,
            loanTerms: loanTerms,
            permit: permit,
            extra: extra
        });
    }

    /**
     * @notice Accept a proposal with a callers nonce revocation.
     * @dev Function will mark callers nonce as revoked.
     * @param proposal Proposal struct containing all proposal data.
     * @param proposalValues ProposalValues struct specifying all flexible proposal values.
     * @param signature Proposal signature signed by a proposer.
     * @param permit Callers permit data.
     * @param extra Auxiliary data that are emitted in the loan creation event. They are not used in the contract logic.
     * @param callersNonceSpace Nonce space of a callers nonce.
     * @param callersNonceToRevoke Nonce to revoke.
     * @return loanId Id of a created loan.
     */
    function acceptProposal(
        Proposal calldata proposal,
        ProposalValues calldata proposalValues,
        bytes calldata signature,
        Permit calldata permit,
        bytes calldata extra,
        uint256 callersNonceSpace,
        uint256 callersNonceToRevoke
    ) external returns (uint256 loanId) {
        _revokeCallersNonce(msg.sender, callersNonceSpace, callersNonceToRevoke);
        return acceptProposal(proposal, proposalValues, signature, permit, extra);
    }

    /**
     * @notice Accept a refinancing proposal with a callers nonce revocation.
     * @dev Function will mark callers nonce as revoked.
     * @param loanId Id of a loan to be refinanced.
     * @param proposal Proposal struct containing all proposal data.
     * @param proposalValues ProposalValues struct specifying all flexible proposal values.
     * @param signature Proposal signature signed by a proposer.
     * @param permit Callers permit data.
     * @param extra Auxiliary data that are emitted in the loan creation event. They are not used in the contract logic.
     * @param callersNonceSpace Nonce space of a callers nonce.
     * @param callersNonceToRevoke Nonce to revoke.
     * @return refinancedLoanId Id of a created refinanced loan.
     */
    function acceptRefinanceProposal(
        uint256 loanId,
        Proposal calldata proposal,
        ProposalValues calldata proposalValues,
        bytes calldata signature,
        Permit calldata permit,
        bytes calldata extra,
        uint256 callersNonceSpace,
        uint256 callersNonceToRevoke
    ) external returns (uint256 refinancedLoanId) {
        _revokeCallersNonce(msg.sender, callersNonceSpace, callersNonceToRevoke);
        return acceptRefinanceProposal(loanId, proposal, proposalValues, signature, permit, extra);
    }


    /*----------------------------------------------------------*|
    |*  # INTERNALS                                             *|
    |*----------------------------------------------------------*/

    function _acceptProposal(
        Proposal calldata proposal,
        ProposalValues calldata proposalValues,
        bytes calldata signature
    )  private returns (bytes32 proposalHash, PWNSimpleLoan.Terms memory loanTerms) {
        // Check if the loan contract has a tag
        _checkLoanContractTag(proposal.loanContract);

        // Check min collateral amount
        if (proposal.minCollateralAmount == 0) {
            revert MinCollateralAmountNotSet();
        }
        if (proposalValues.collateralAmount < proposal.minCollateralAmount) {
            revert InsufficientCollateralAmount({
                current: proposalValues.collateralAmount,
                limit: proposal.minCollateralAmount
            });
        }

        // Check collateral state fingerprint if needed
        if (proposal.checkCollateralStateFingerprint) {
            _checkCollateralState({
                addr: proposal.collateralAddress,
                id: proposal.collateralId,
                stateFingerprint: proposal.collateralStateFingerprint
            });
        }

        // Calculate credit amount
        uint256 creditAmount = getCreditAmount(proposalValues.collateralAmount, proposal.creditPerCollateralUnit);

        // Try to accept proposal
        proposalHash = _tryAcceptProposal(proposal, creditAmount, signature);

        // Create loan terms object
        loanTerms = _createLoanTerms(proposal, proposalValues.collateralAmount, creditAmount);
    }

    function _tryAcceptProposal(
        Proposal calldata proposal,
        uint256 creditAmount,
        bytes calldata signature
    ) private returns (bytes32 proposalHash) {
        proposalHash = getProposalHash(proposal);
        _tryAcceptProposal({
            proposalHash: proposalHash,
            creditAmount: creditAmount,
            availableCreditLimit: proposal.availableCreditLimit,
            apr: proposal.accruingInterestAPR,
            duration: proposal.duration,
            expiration: proposal.expiration,
            nonceSpace: proposal.nonceSpace,
            nonce: proposal.nonce,
            allowedAcceptor: proposal.allowedAcceptor,
            acceptor: msg.sender,
            signer: proposal.proposer,
            signature: signature
        });
    }

    function _createLoanTerms(
        Proposal calldata proposal,
        uint256 collateralAmount,
        uint256 creditAmount
    ) private view returns (PWNSimpleLoan.Terms memory) {
        return PWNSimpleLoan.Terms({
            lender: proposal.isOffer ? proposal.proposer : msg.sender,
            borrower: proposal.isOffer ? msg.sender : proposal.proposer,
            duration: proposal.duration,
            collateral: MultiToken.Asset({
                category: proposal.collateralCategory,
                assetAddress: proposal.collateralAddress,
                id: proposal.collateralId,
                amount: collateralAmount
            }),
            credit: MultiToken.ERC20({
                assetAddress: proposal.creditAddress,
                amount: creditAmount
            }),
            fixedInterestAmount: proposal.fixedInterestAmount,
            accruingInterestAPR: proposal.accruingInterestAPR
        });
    }

}
