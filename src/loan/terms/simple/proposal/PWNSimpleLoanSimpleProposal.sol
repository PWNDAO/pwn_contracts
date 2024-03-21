// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { PWNSimpleLoan } from "@pwn/loan/terms/simple/loan/PWNSimpleLoan.sol";
import { PWNSimpleLoanProposal } from "@pwn/loan/terms/simple/proposal/PWNSimpleLoanProposal.sol";
import { Permit } from "@pwn/loan/vault/Permit.sol";
import "@pwn/PWNErrors.sol";


/**
 * @title PWN Simple Loan Simple Proposal
 * @notice Contract for creating and accepting simple loan proposals.
 */
contract PWNSimpleLoanSimpleProposal is PWNSimpleLoanProposal {

    string public constant VERSION = "1.2";

    /**
     * @dev EIP-712 simple proposal struct type hash.
     */
    bytes32 public constant PROPOSAL_TYPEHASH = keccak256(
        "Proposal(uint8 collateralCategory,address collateralAddress,uint256 collateralId,uint256 collateralAmount,bool checkCollateralStateFingerprint,bytes32 collateralStateFingerprint,address creditAddress,uint256 creditAmount,uint256 availableCreditLimit,uint256 fixedInterestAmount,uint40 accruingInterestAPR,uint32 duration,uint40 expiration,address allowedAcceptor,address proposer,bool isOffer,uint256 refinancingLoanId,uint256 nonceSpace,uint256 nonce,address loanContract)"
    );

    /**
     * @notice Construct defining a simple proposal.
     * @param collateralCategory Category of an asset used as a collateral (0 == ERC20, 1 == ERC721, 2 == ERC1155).
     * @param collateralAddress Address of an asset used as a collateral.
     * @param collateralId Token id of an asset used as a collateral, in case of ERC20 should be 0.
     * @param collateralAmount Amount of tokens used as a collateral, in case of ERC721 should be 0.
     * @param checkCollateralStateFingerprint If true, the collateral state fingerprint has to be checked.
     * @param collateralStateFingerprint Fingerprint of a collateral state defined by ERC5646.
     * @param creditAddress Address of an asset which is lended to a borrower.
     * @param creditAmount Amount of tokens which is proposed as a loan to a borrower.
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
     *              Can be used to create a group of proposals, where accepting one proposal will make other proposals in the group revoked.
     * @param loanContract Address of a loan contract that will create a loan from the proposal.
     */
    struct Proposal {
        MultiToken.Category collateralCategory;
        address collateralAddress;
        uint256 collateralId;
        uint256 collateralAmount;
        bool checkCollateralStateFingerprint;
        bytes32 collateralStateFingerprint;
        address creditAddress;
        uint256 creditAmount;
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
     * @dev Emitted when a proposal is made via an on-chain transaction.
     */
    event ProposalMade(bytes32 indexed proposalHash, address indexed proposer, Proposal proposal);

    constructor(
        address _hub,
        address _revokedNonce,
        address _stateFingerprintComputerRegistry
    ) PWNSimpleLoanProposal(
        _hub, _revokedNonce, _stateFingerprintComputerRegistry, "PWNSimpleLoanSimpleProposal", VERSION
    ) {}

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
     * @notice Accept a proposal.
     * @param proposal Proposal struct containing all proposal data.
     * @param signature Proposal signature signed by a proposer.
     * @param permit Callers permit data.
     * @param extra Auxiliary data that are emitted in the loan creation event. They are not used in the contract logic.
     * @return loanId Id of a created loan.
     */
    function acceptProposal(
        Proposal calldata proposal,
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
        (bytes32 proposalHash, PWNSimpleLoan.Terms memory loanTerms) = _acceptProposal(proposal, signature);

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
     * @param signature Proposal signature signed by a proposer.
     * @param permit Callers permit data.
     * @param extra Auxiliary data that are emitted in the loan creation event. They are not used in the contract logic.
     * @return refinancedLoanId Id of a created refinanced loan.
     */
    function acceptRefinanceProposal(
        uint256 loanId,
        Proposal calldata proposal,
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
        (bytes32 proposalHash, PWNSimpleLoan.Terms memory loanTerms) = _acceptProposal(proposal, signature);

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
     * @param signature Proposal signature signed by a proposer.
     * @param permit Callers permit data.
     * @param extra Auxiliary data that are emitted in the loan creation event. They are not used in the contract logic.
     * @param callersNonceSpace Nonce space of a callers nonce.
     * @param callersNonceToRevoke Nonce to revoke.
     * @return loanId Id of a created loan.
     */
    function acceptProposal(
        Proposal calldata proposal,
        bytes calldata signature,
        Permit calldata permit,
        bytes calldata extra,
        uint256 callersNonceSpace,
        uint256 callersNonceToRevoke
    ) external returns (uint256 loanId) {
        _revokeCallersNonce(msg.sender, callersNonceSpace, callersNonceToRevoke);
        return acceptProposal(proposal, signature, permit, extra);
    }

    /**
     * @notice Accept a refinancing proposal with a callers nonce revocation.
     * @dev Function will mark callers nonce as revoked.
     * @param loanId Id of a loan to be refinanced.
     * @param proposal Proposal struct containing all proposal data.
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
        bytes calldata signature,
        Permit calldata permit,
        bytes calldata extra,
        uint256 callersNonceSpace,
        uint256 callersNonceToRevoke
    ) external returns (uint256 refinancedLoanId) {
        _revokeCallersNonce(msg.sender, callersNonceSpace, callersNonceToRevoke);
        return acceptRefinanceProposal(loanId, proposal, signature, permit, extra);
    }


    /*----------------------------------------------------------*|
    |*  # INTERNALS                                             *|
    |*----------------------------------------------------------*/

    function _acceptProposal(
        Proposal calldata proposal,
        bytes calldata signature
    )  private returns (bytes32 proposalHash, PWNSimpleLoan.Terms memory loanTerms) {
        // Check if the loan contract has a tag
        _checkLoanContractTag(proposal.loanContract);

        // Check collateral state fingerprint if needed
        if (proposal.checkCollateralStateFingerprint) {
            _checkCollateralState({
                addr: proposal.collateralAddress,
                id: proposal.collateralId,
                stateFingerprint: proposal.collateralStateFingerprint
            });
        }

        // Try to accept proposal
        proposalHash = _tryAcceptProposal(proposal, signature);

        // Create loan terms object
        loanTerms = _createLoanTerms(proposal);
    }

    function _tryAcceptProposal(Proposal calldata proposal, bytes calldata signature) private returns (bytes32 proposalHash) {
        proposalHash = getProposalHash(proposal);
        _tryAcceptProposal({
            proposalHash: proposalHash,
            creditAmount: proposal.creditAmount,
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

    function _createLoanTerms(Proposal calldata proposal) private view returns (PWNSimpleLoan.Terms memory) {
        return PWNSimpleLoan.Terms({
            lender: proposal.isOffer ? proposal.proposer : msg.sender,
            borrower: proposal.isOffer ? msg.sender : proposal.proposer,
            duration: proposal.duration,
            collateral: MultiToken.Asset({
                category: proposal.collateralCategory,
                assetAddress: proposal.collateralAddress,
                id: proposal.collateralId,
                amount: proposal.collateralAmount
            }),
            credit: MultiToken.ERC20({
                assetAddress: proposal.creditAddress,
                amount: proposal.creditAmount
            }),
            fixedInterestAmount: proposal.fixedInterestAmount,
            accruingInterestAPR: proposal.accruingInterestAPR
        });
    }

}
