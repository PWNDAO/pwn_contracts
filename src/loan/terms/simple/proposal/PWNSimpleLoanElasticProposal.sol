// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { Math } from "openzeppelin/utils/math/Math.sol";

import { PWNSimpleLoan } from "pwn/loan/terms/simple/loan/PWNSimpleLoan.sol";
import { PWNSimpleLoanProposal } from "pwn/loan/terms/simple/proposal/PWNSimpleLoanProposal.sol";


/**
 * @title PWN Simple Loan Elastic Proposal
 * @notice Contract for creating and accepting elastic loan proposals.
 *         Proposals are elastic, which means that they are not tied to a specific collateral or credit amount.
 *         The amount of collateral and credit is specified during the proposal acceptance.
 */
contract PWNSimpleLoanElasticProposal is PWNSimpleLoanProposal {

    string public constant VERSION = "1.1";

    /**
     * @notice Credit per collateral unit denominator. It is used to calculate credit amount from collateral amount.
     */
    uint256 public constant CREDIT_PER_COLLATERAL_UNIT_DENOMINATOR = 1e38;

    /**
     * @dev EIP-712 simple proposal struct type hash.
     */
    bytes32 public constant PROPOSAL_TYPEHASH = keccak256(
        "Proposal(uint8 collateralCategory,address collateralAddress,uint256 collateralId,bool checkCollateralStateFingerprint,bytes32 collateralStateFingerprint,address creditAddress,uint256 creditPerCollateralUnit,uint256 minCreditAmount,uint256 availableCreditLimit,bytes32 utilizedCreditId,uint256 fixedInterestAmount,uint24 accruingInterestAPR,uint32 durationOrDate,uint40 expiration,address allowedAcceptor,address proposer,bytes32 proposerSpecHash,bool isOffer,uint256 refinancingLoanId,uint256 nonceSpace,uint256 nonce,address loanContract)"
    );

    /**
     * @notice Construct defining an elastic proposal.
     * @param collateralCategory Category of an asset used as a collateral (0 == ERC20, 1 == ERC721, 2 == ERC1155).
     * @param collateralAddress Address of an asset used as a collateral.
     * @param collateralId Token id of an asset used as a collateral, in case of ERC20 should be 0.
     * @param checkCollateralStateFingerprint If true, the collateral state fingerprint will be checked during proposal acceptance.
     * @param collateralStateFingerprint Fingerprint of a collateral state. It is used to check if a collateral is in a valid state.
     * @param creditAddress Address of an asset which is lended to a borrower.
     * @param creditPerCollateralUnit Amount of tokens which are offered per collateral unit with 38 decimals.
     * @param minCreditAmount Minimum amount of tokens which can be borrowed using the proposal.
     * @param availableCreditLimit Available credit limit for the proposal. It is the maximum amount of tokens which can be borrowed using the proposal. If non-zero, proposal can be accepted more than once, until the credit limit is reached.
     * @param utilizedCreditId Id of utilized credit. Can be shared between multiple proposals.
     * @param fixedInterestAmount Fixed interest amount in credit tokens. It is the minimum amount of interest which has to be paid by a borrower.
     * @param accruingInterestAPR Accruing interest APR with 2 decimals.
     * @param durationOrDate Duration of a loan in seconds. If the value is greater than 10^9, it is treated as a timestamp of a loan end.
     * @param expiration Proposal expiration timestamp in seconds.
     * @param allowedAcceptor Address that is allowed to accept proposal. If the address is zero address, anybody can accept the proposal.
     * @param proposer Address of a proposal signer. If `isOffer` is true, the proposer is the lender. If `isOffer` is false, the proposer is the borrower.
     * @param proposerSpecHash Hash of a proposer specific data, which must be provided during a loan creation.
     * @param isOffer If true, the proposal is an offer. If false, the proposal is a request.
     * @param refinancingLoanId Id of a loan which is refinanced by this proposal. If the id is 0 and `isOffer` is true, the proposal can refinance any loan.
     * @param nonceSpace Nonce space of a proposal nonce. All nonces in the same space can be revoked at once.
     * @param nonce Additional value to enable identical proposals in time. Without it, it would be impossible to make again proposal, which was once revoked. Can be used to create a group of proposals, where accepting one will make others in the group invalid.
     * @param loanContract Address of a loan contract that will create a loan from the proposal.
     */
    struct Proposal {
        MultiToken.Category collateralCategory;
        address collateralAddress;
        uint256 collateralId;
        bool checkCollateralStateFingerprint;
        bytes32 collateralStateFingerprint;
        address creditAddress;
        uint256 creditPerCollateralUnit;
        uint256 minCreditAmount;
        uint256 availableCreditLimit;
        bytes32 utilizedCreditId;
        uint256 fixedInterestAmount;
        uint24 accruingInterestAPR;
        uint32 durationOrDate;
        uint40 expiration;
        address allowedAcceptor;
        address proposer;
        bytes32 proposerSpecHash;
        bool isOffer;
        uint256 refinancingLoanId;
        uint256 nonceSpace;
        uint256 nonce;
        address loanContract;
    }

    /**
     * @notice Construct defining proposal concrete values.
     * @param creditAmount Amount of credit to be borrowed.
     */
    struct ProposalValues {
        uint256 creditAmount;
    }

    /**
     * @notice Emitted when a proposal is made via an on-chain transaction.
     */
    event ProposalMade(bytes32 indexed proposalHash, address indexed proposer, Proposal proposal);

    /**
     * @notice Thrown when proposal has no minimum credit amount set.
     */
    error MinCreditAmountNotSet();

    /**
     * @notice Throw when proposal credit amount is insufficient.
     */
    error InsufficientCreditAmount(uint256 current, uint256 limit);

    constructor(
        address _hub,
        address _revokedNonce,
        address _config,
        address _utilizedCredit
    ) PWNSimpleLoanProposal(_hub, _revokedNonce, _config, _utilizedCredit, "PWNSimpleLoanElasticProposal", VERSION) {}

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
     * @notice Encode proposal data.
     * @param proposal Proposal struct to be encoded.
     * @param proposalValues ProposalValues struct to be encoded.
     * @return Encoded proposal data.
     */
    function encodeProposalData(
        Proposal memory proposal,
        ProposalValues memory proposalValues
    ) external pure returns (bytes memory) {
        return abi.encode(proposal, proposalValues);
    }

    /**
     * @notice Decode proposal data.
     * @param proposalData Encoded proposal data.
     * @return Decoded proposal struct.
     * @return Decoded proposal values struct.
     */
    function decodeProposalData(bytes memory proposalData) public pure returns (Proposal memory, ProposalValues memory) {
        return abi.decode(proposalData, (Proposal, ProposalValues));
    }

    /**
     * @notice Compute collateral amount from credit amount and credit per collateral unit.
     * @param creditAmount Amount of credit.
     * @param creditPerCollateralUnit Amount of credit per collateral unit with 38 decimals.
     * @return Amount of collateral.
     */
    function getCollateralAmount(uint256 creditAmount, uint256 creditPerCollateralUnit) public pure returns (uint256) {
        return Math.mulDiv(creditAmount, CREDIT_PER_COLLATERAL_UNIT_DENOMINATOR, creditPerCollateralUnit);
    }

    /**
     * @inheritdoc PWNSimpleLoanProposal
     */
    function acceptProposal(
        address acceptor,
        uint256 refinancingLoanId,
        bytes calldata proposalData,
        bytes32[] calldata proposalInclusionProof,
        bytes calldata signature
    ) override external returns (bytes32 proposalHash, PWNSimpleLoan.Terms memory loanTerms) {
        // Decode proposal data
        (Proposal memory proposal, ProposalValues memory proposalValues) = decodeProposalData(proposalData);

        // Make proposal hash
        proposalHash = _getProposalHash(PROPOSAL_TYPEHASH, abi.encode(proposal));

        // Check min credit amount
        if (proposal.minCreditAmount == 0) {
            revert MinCreditAmountNotSet();
        }

        // Check sufficient credit amount
        if (proposalValues.creditAmount < proposal.minCreditAmount) {
            revert InsufficientCreditAmount({ current: proposalValues.creditAmount, limit: proposal.minCreditAmount });
        }

        // Calculate credit amount
        uint256 collateralAmount = getCollateralAmount(proposalValues.creditAmount, proposal.creditPerCollateralUnit);

        // Try to accept proposal
        _acceptProposal(
            acceptor,
            refinancingLoanId,
            proposalHash,
            proposalInclusionProof,
            signature,
            ProposalBase({
                collateralAddress: proposal.collateralAddress,
                collateralId: proposal.collateralId,
                checkCollateralStateFingerprint: proposal.checkCollateralStateFingerprint,
                collateralStateFingerprint: proposal.collateralStateFingerprint,
                creditAmount: proposalValues.creditAmount,
                availableCreditLimit: proposal.availableCreditLimit,
                utilizedCreditId: proposal.utilizedCreditId,
                expiration: proposal.expiration,
                allowedAcceptor: proposal.allowedAcceptor,
                proposer: proposal.proposer,
                isOffer: proposal.isOffer,
                refinancingLoanId: proposal.refinancingLoanId,
                nonceSpace: proposal.nonceSpace,
                nonce: proposal.nonce,
                loanContract: proposal.loanContract
            })
        );

        // Create loan terms object
        loanTerms = PWNSimpleLoan.Terms({
            lender: proposal.isOffer ? proposal.proposer : acceptor,
            borrower: proposal.isOffer ? acceptor : proposal.proposer,
            duration: _getLoanDuration(proposal.durationOrDate),
            collateral: MultiToken.Asset({
                category: proposal.collateralCategory,
                assetAddress: proposal.collateralAddress,
                id: proposal.collateralId,
                amount: collateralAmount
            }),
            credit: MultiToken.ERC20({
                assetAddress: proposal.creditAddress,
                amount: proposalValues.creditAmount
            }),
            fixedInterestAmount: proposal.fixedInterestAmount,
            accruingInterestAPR: proposal.accruingInterestAPR,
            lenderSpecHash: proposal.isOffer ? proposal.proposerSpecHash : bytes32(0),
            borrowerSpecHash: proposal.isOffer ? bytes32(0) : proposal.proposerSpecHash
        });
    }

}
