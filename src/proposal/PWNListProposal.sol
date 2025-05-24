// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { MerkleProof } from "openzeppelin/utils/cryptography/MerkleProof.sol";

import { PWNStableInterestModule } from "pwn/loan/module/interest/PWNStableInterestModule.sol";
import { PWNDurationDefaultModule } from "pwn/loan/module/default/PWNDurationDefaultModule.sol";
import { PWNBaseProposal, Terms } from "pwn/proposal/PWNBaseProposal.sol";


/**
 * @title PWN List Proposal
 * @notice Contract for creating and accepting list loan proposals.
 * @dev The proposal can define a list of acceptable collateral ids or the whole collection.
 */
contract PWNListProposal is PWNBaseProposal {

    string public constant VERSION = "1.5";

    /** @dev EIP-712 simple proposal struct type hash.*/
    bytes32 public constant PROPOSAL_TYPEHASH = keccak256(
        "Proposal(uint8 collateralCategory,address collateralAddress,bytes32 collateralIdsWhitelistMerkleRoot,uint256 collateralAmount,address creditAddress,uint256 creditAmount,uint256 interestAPR,uint256 duration,uint256 minCreditAmount,uint256 availableCreditLimit,bytes32 utilizedCreditId,uint256 nonceSpace,uint256 nonce,uint256 expiration,address proposer,bytes32 proposerSpecHash,bool isProposerLender,address loanContract)"
    );

    /** @notice Stable interest module used in the proposal.*/
    PWNStableInterestModule public immutable interestModule;
    /** @notice Duration based default module used in the proposal.*/
    PWNDurationDefaultModule public immutable defaultModule;

    /**
     * @notice Construct defining a list proposal.
     * @param collateralCategory Category of an asset used as a collateral (0 == ERC20, 1 == ERC721, 2 == ERC1155).
     * @param collateralAddress Address of an asset used as a collateral.
     * @param collateralIdsWhitelistMerkleRoot Merkle tree root of a set of whitelisted collateral ids.
     * @param collateralAmount Amount of tokens used as a collateral, in case of ERC721 should be 0.
     * @param creditAddress Address of an asset which is lender to a borrower.
     * @param creditAmount Amount of tokens which is proposed as a loan to a borrower.
     * @param interestAPR Accruing interest APR with 2 decimals.
     * @param duration Duration of a loan in seconds.
     * @param minCreditAmount Minimum amount of tokens which can be borrowed using the proposal.
     * @param availableCreditLimit Available credit limit for the proposal. It is the maximum amount of tokens which can be borrowed using the proposal. If non-zero, proposal can be accepted more than once, until the credit limit is reached.
     * @param utilizedCreditId Id of utilized credit. Can be shared between multiple proposals.
     * @param nonceSpace Nonce space of a proposal nonce. All nonces in the same space can be revoked at once.
     * @param nonce Additional value to enable identical proposals in time. Without it, it would be impossible to make again proposal, which was once revoked. Can be used to create a group of proposals, where accepting one proposal will make other proposals in the group revoked.
     * @param expiration Proposal expiration timestamp in seconds.
     * @param proposer Address of a proposal signer.
     * @param proposerSpecHash Hash of a proposer specific data, which must be provided during a loan creation.
     * @param isProposerLender If true, the proposer is a lender. If false, the proposer is a borrower.
     * @param loanContract Address of a loan contract that will create a loan from the proposal.
     */
    struct Proposal {
        // Collateral
        MultiToken.Category collateralCategory;
        address collateralAddress;
        bytes32 collateralIdsWhitelistMerkleRoot;
        uint256 collateralAmount;
        // Credit
        address creditAddress;
        uint256 creditAmount;
        // Interest
        uint256 interestAPR;
        // Default
        uint256 duration;
        // Proposal validity
        uint256 minCreditAmount;
        uint256 availableCreditLimit;
        bytes32 utilizedCreditId;
        uint256 nonceSpace;
        uint256 nonce;
        uint256 expiration;
        // General proposal
        address proposer;
        bytes32 proposerSpecHash;
        bool isProposerLender;
        address loanContract;
    }

    /**
     * @notice Construct defining proposal concrete values.
     * @param collateralId Selected collateral id to be used as a collateral.
     * @param merkleInclusionProof Proof of inclusion, that selected collateral id is whitelisted.
     * This proof should create same hash as the merkle tree root given in the proposal.
     * Can be empty for a proposal on a whole collection.
     */
    struct AcceptorValues {
        uint256 collateralId;
        bytes32[] merkleInclusionProof;
    }

    /** @notice Emitted when a proposal is made via an on-chain transaction.*/
    event ProposalMade(bytes32 indexed proposalHash, address indexed proposer, Proposal proposal);

    /** @notice Thrown when a collateral id is not whitelisted.*/
    error CollateralIdNotWhitelisted(uint256 id);

    constructor(
        address _hub,
        address _revokedNonce,
        address _config,
        address _utilizedCredit,
        address _interestModule,
        address _defaultModule
    ) PWNBaseProposal(_hub, _revokedNonce, _config, _utilizedCredit, "PWNSimpleLoanListProposal", VERSION) {
        interestModule = PWNStableInterestModule(_interestModule);
        defaultModule = PWNDurationDefaultModule(_defaultModule);
    }

    /**
     * @notice Get an proposal hash according to EIP-712
     * @param proposal Proposal struct to be hashed.
     * @return Proposal struct hash.
     */
    function getProposalHash(Proposal calldata proposal) public view returns (bytes32) {
        return _getProposalHash(PROPOSAL_TYPEHASH, _erc712EncodeProposal(proposal));
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
     * @param acceptorValues Acceptor values struct to be encoded.
     * @return Encoded proposal data.
     */
    function encodeProposalData(
        Proposal memory proposal,
        AcceptorValues memory acceptorValues
    ) external pure returns (bytes memory) {
        return abi.encode(proposal, acceptorValues);
    }

    /**
     * @notice Decode proposal data.
     * @param proposalData Encoded proposal data.
     * @return Decoded proposal struct.
     * @return Decoded acceptor values struct.
     */
    function decodeProposalData(bytes memory proposalData) public pure returns (Proposal memory, AcceptorValues memory) {
        return abi.decode(proposalData, (Proposal, AcceptorValues));
    }

    function acceptProposal(
        address acceptor,
        bytes calldata proposalData,
        bytes32[] calldata proposalInclusionProof,
        bytes calldata signature
    ) override external returns (Terms memory loanTerms) {
        // Decode proposal data
        (Proposal memory proposal, AcceptorValues memory acceptorValues) = decodeProposalData(proposalData);

        // Make proposal hash
        bytes32 proposalHash = _getProposalHash(PROPOSAL_TYPEHASH, _erc712EncodeProposal(proposal));

        // Check provided collateral id
        if (proposal.collateralIdsWhitelistMerkleRoot != bytes32(0)) {
            // Verify whitelisted collateral id
            if (
                !MerkleProof.verify({
                    proof: acceptorValues.merkleInclusionProof,
                    root: proposal.collateralIdsWhitelistMerkleRoot,
                    leaf: keccak256(abi.encodePacked(acceptorValues.collateralId))
                })
            ) revert CollateralIdNotWhitelisted({ id: acceptorValues.collateralId });
        }

        // Note: If the `collateralIdsWhitelistMerkleRoot` is empty, any collateral id can be used.

        // Check if proposal is valid
        _checkProposal(
            CheckInputs({
                proposalHash: proposalHash,
                acceptor: acceptor,
                creditAmount: proposal.creditAmount,
                availableCreditLimit: proposal.availableCreditLimit,
                utilizedCreditId: proposal.utilizedCreditId,
                nonceSpace: proposal.nonceSpace,
                nonce: proposal.nonce,
                expiration: proposal.expiration,
                proposer: proposal.proposer,
                loanContract: proposal.loanContract
            }),
            proposalInclusionProof,
            signature
        );

        // Create loan terms object
        return Terms({
            proposalHash: proposalHash,
            lender: proposal.isProposerLender ? proposal.proposer : acceptor,
            borrower: proposal.isProposerLender ? acceptor : proposal.proposer,
            proposerSpecHash: proposal.proposerSpecHash,
            collateral: MultiToken.Asset({
                category: proposal.collateralCategory,
                assetAddress: proposal.collateralAddress,
                id: acceptorValues.collateralId,
                amount: proposal.collateralAmount
            }),
            creditAddress: proposal.creditAddress,
            principal: proposal.creditAmount,
            interestModule: address(interestModule),
            interestModuleProposerData: abi.encode(PWNStableInterestModule.ProposerData(proposal.interestAPR)),
            defaultModule: address(defaultModule),
            defaultModuleProposerData: abi.encode(PWNDurationDefaultModule.ProposerData(proposal.duration)),
            liquidationModule: address(0),
            liquidationModuleProposerData: ""
        });
    }

    /**
     * @notice Encode proposal data for EIP-712.
     * @param proposal Proposal struct to be encoded.
     * @return Encoded proposal data.
     */
    function _erc712EncodeProposal(Proposal memory proposal) internal pure returns (bytes memory) {
        return abi.encode(proposal);
    }

}
