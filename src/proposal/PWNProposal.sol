// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MerkleProof } from "openzeppelin/utils/cryptography/MerkleProof.sol";

import { PWNConfig } from "pwn/config/PWNConfig.sol";
import { PWNHub } from "pwn/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/hub/PWNHubTags.sol";
import { PWNSignatureChecker } from "pwn/lib/PWNSignatureChecker.sol";
import { IPWNDefaultModule } from "pwn/module/IPWNDefaultModule.sol";
import { IPWNInterestModule } from "pwn/module/IPWNInterestModule.sol";
import { IPWNProposalAcceptanceHook } from "pwn/module/IPWNProposalAcceptanceHook.sol";
import { IPWNProposalAssetResolver } from "pwn/module/IPWNProposalAssetResolver.sol";
import { LoanTerms } from "pwn/loan/LoanTerms.sol";


contract PWNProposal {

    string public constant VERSION = "1.5";

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    /** @dev EIP-712 proposal struct type hash.*/
    bytes32 public constant PROPOSAL_TYPEHASH = keccak256("Proposal(address assetsResolver,bytes assetsResolverData,address interestModule,bytes interestModuleData,address defaultModule,bytes defaultModuleData,address[] acceptanceHooks,bytes[] acceptanceHooksData,address proposer,bytes32 proposerSpecHash,bool isProposerLender,address loanContract)");
    /** @dev EIP-712 multiproposal struct type hash.*/
    bytes32 public constant MULTIPROPOSAL_TYPEHASH = keccak256("Multiproposal(bytes32 multiproposalMerkleRoot)");
    bytes32 public constant ACCEPTANCE_HOOK_RETURN_VALUE = keccak256("PWNProposalAcceptanceHook.onProposalAcceptance");

    bytes32 public immutable PROPOSAL_DOMAIN_SEPARATOR;
    bytes32 public immutable MULTIPROPOSAL_DOMAIN_SEPARATOR;

    PWNHub public immutable hub;
    PWNConfig public immutable config;

    struct Multiproposal {
        bytes32 multiproposalMerkleRoot;
    }

    struct Proposal {
        IPWNProposalAssetResolver assetsResolver;
        bytes assetsResolverData;
        address interestModule;
        bytes interestModuleProposerData;
        address defaultModule;
        bytes defaultModuleProposerData;
        IPWNProposalAcceptanceHook[] acceptanceHooks;
        bytes[] acceptanceHooksData;
        address proposer;
        bytes32 proposerSpecHash;
        bool isProposerLender;
        address loanContract;
    }

    struct AcceptorValues {
        bytes assetsResolverData;
        bytes[] acceptanceHooksData;
    }

    /**
     * @dev Mapping of proposals made via on-chain transactions.
     * Could be used by contract wallets instead of EIP-1271 (proposal hash => is made).
     */
    mapping (bytes32 => bool) public proposalsMade;

    /*----------------------------------------------------------*|
    |*  # EVENTS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /** @notice Emitted when a proposal is made via an on-chain transaction.*/
    event ProposalMade(bytes32 indexed proposalHash, address indexed proposer, Proposal proposal);


    /*----------------------------------------------------------*|
    |*  # ERRORS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /** @notice Thrown when a caller is missing a required hub tag.*/
    error CallerNotLoanContract(address caller, address loanContract);
    /** @notice Thrown when an address is missing a PWN Hub tag.*/
    error AddressMissingHubTag(address addr, bytes32 tag);
    /** @notice Thrown when proposal acceptor and proposer are the same.*/
    error AcceptorIsProposer();
    /** @notice Thrown when proposal does not have a loan contract.*/
    error NoLoanContract();
    /** @notice Thrown when proposal does not have an assets resolver.*/
    error NoAssetsResolver();
    /** @notice Thrown when proposal does not have an interest module.*/
    error NoInterestModule();
    /** @notice Thrown when proposal does not have a default module.*/
    error NoDefaultModule();
    /** @notice Thrown when proposal does not have any acceptance hooks.*/
    error NoProposalAcceptorHook();
    /** @notice Thrown when hook array length does not match data array length.*/
    error AcceptorHooksDataLengthMismatch(uint256 hooksLength, uint256 dataLength);
    /** @notice Thrown when hook returns an invalid value.*/
    error InvalidHookReturnValue(bytes32 expected, bytes32 current);
    /** @notice Thrown when a caller is not a stated proposer.*/
    error CallerIsNotStatedProposer(address addr);


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(
        address _hub,
        address _config
    ) {
        hub = PWNHub(_hub);
        config = PWNConfig(_config);

        PROPOSAL_DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256("PWNProposal"),
            keccak256(abi.encodePacked(VERSION)),
            block.chainid,
            address(this)
        ));

        MULTIPROPOSAL_DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name)"),
            keccak256("PWNMultiproposal")
        ));
    }


    function acceptProposal(
        address acceptor,
        bytes calldata proposalData,
        bytes32[] calldata proposalInclusionProof,
        bytes calldata signature
    ) external returns (LoanTerms memory loanTerms) {
        // Decode proposal data
        (Proposal memory proposal, AcceptorValues memory acceptorValues) = decodeProposalData(proposalData);

        _checkProposalValidity(proposal);

        if (msg.sender != proposal.loanContract) {
            revert CallerNotLoanContract({ caller: msg.sender, loanContract: proposal.loanContract });
        }
        if (!hub.hasTag(proposal.loanContract, PWNHubTags.ACTIVE_LOAN)) {
            revert AddressMissingHubTag({ addr: proposal.loanContract, tag: PWNHubTags.ACTIVE_LOAN });
        }

        // Check proposer is not acceptor
        if (proposal.proposer == acceptor) {
            revert AcceptorIsProposer();
        }

        loanTerms.proposalHash = getProposalHash(proposal);

        // Check proposal signature or that it was made on-chain
        if (proposalInclusionProof.length == 0) {
            // Single proposal signature
            if (!proposalsMade[loanTerms.proposalHash]) {
                if (!PWNSignatureChecker.isValidSignatureNow(proposal.proposer, loanTerms.proposalHash, signature)) {
                    revert PWNSignatureChecker.InvalidSignature({ signer: proposal.proposer, digest: loanTerms.proposalHash });
                }
            }
        } else {
            // Multiproposal signature
            bytes32 multiproposalHash = getMultiproposalHash(
                Multiproposal({
                    multiproposalMerkleRoot: MerkleProof.processProofCalldata({
                        proof: proposalInclusionProof,
                        leaf: loanTerms.proposalHash
                    })
                })
            );
            if (!PWNSignatureChecker.isValidSignatureNow(proposal.proposer, multiproposalHash, signature)) {
                revert PWNSignatureChecker.InvalidSignature({ signer: proposal.proposer, digest: multiproposalHash });
            }
        }

        // Resolve loan assets
        (loanTerms.collateral, loanTerms.creditAddress, loanTerms.principal)
            = proposal.assetsResolver.resolveAssets({
                proposerData: proposal.assetsResolverData,
                acceptorData: acceptorValues.assetsResolverData
            });

        // Check acceptors array lengths
        uint256 length = proposal.acceptanceHooks.length;
        uint256 dataLength = acceptorValues.acceptanceHooksData.length;
        if (dataLength != length) {
            revert AcceptorHooksDataLengthMismatch({ hooksLength: length, dataLength: dataLength });
        }

        // Check proposal validity
        for (uint256 i; i < length; ++i) {
            // Note: !! WARNING: external call !!
            bytes32 hookReturnValue = proposal.acceptanceHooks[i].onProposalAcceptance({
                proposer: proposal.proposer,
                proposerData: proposal.acceptanceHooksData[i],
                acceptor: acceptor,
                acceptorData: acceptorValues.acceptanceHooksData[i],
                collateral: loanTerms.collateral,
                creditAddress: loanTerms.creditAddress,
                principal: loanTerms.principal
            });
            if (hookReturnValue != ACCEPTANCE_HOOK_RETURN_VALUE) {
                revert InvalidHookReturnValue({ expected: ACCEPTANCE_HOOK_RETURN_VALUE, current: hookReturnValue });
            }
        }

        loanTerms.lender = proposal.isProposerLender ? proposal.proposer : acceptor;
        loanTerms.borrower = proposal.isProposerLender ? acceptor : proposal.proposer;
        loanTerms.proposerSpecHash = proposal.proposerSpecHash;
        loanTerms.interestModule = proposal.interestModule;
        loanTerms.interestModuleProposerData = proposal.interestModuleData;
        loanTerms.interestModuleAcceptorData = acceptorValues.interestModuleData;
        loanTerms.defaultModule = proposal.defaultModule;
        loanTerms.defaultModuleProposerData = proposal.defaultModuleData;
        loanTerms.defaultModuleAcceptorData = acceptorValues.defaultModuleData;
    }

    /**
     * @notice Encode proposal data.
     * @param proposal Proposal struct to be encoded.
     * @param acceptorValues AcceptorValues struct to be encoded.
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
     * @return Decoded proposal values struct.
     */
    function decodeProposalData(bytes memory proposalData) public pure returns (Proposal memory, AcceptorValues memory) {
        return abi.decode(proposalData, (Proposal, AcceptorValues));
    }

    /**
     * @notice Make an on-chain proposal.
     * @dev Function will mark a proposal hash as proposed.
     * @param proposal Proposal struct containing all needed proposal data.
     * @return proposalHash Proposal hash.
     */
    function makeProposal(Proposal calldata proposal) external returns (bytes32 proposalHash) {
        if (msg.sender != proposal.proposer) {
            revert CallerIsNotStatedProposer({ addr: proposal.proposer });
        }
        _checkProposalValidity(proposal);

        proposalHash = getProposalHash(proposal);
        proposalsMade[proposalHash] = true;
        emit ProposalMade(proposalHash, proposal.proposer, proposal);
    }

    /**
     * @notice Get an proposal hash according to EIP-712
     * @param proposal Proposal struct to be hashed.
     * @return Proposal struct hash.
     */
    function getProposalHash(Proposal memory proposal) public view returns (bytes32) {
        return _erc712Hash(PROPOSAL_DOMAIN_SEPARATOR, PROPOSAL_TYPEHASH, _erc712EncodeProposal(proposal));
    }

    /**
     * @notice Get a multiproposal hash according to EIP-712.
     * @param multiproposal Multiproposal struct.
     * @return Multiproposal hash.
     */
    function getMultiproposalHash(Multiproposal memory multiproposal) public view returns (bytes32) {
        return _erc712Hash(MULTIPROPOSAL_DOMAIN_SEPARATOR, MULTIPROPOSAL_TYPEHASH, abi.encode(multiproposal));
    }


    function _checkProposalValidity(Proposal memory proposal) internal {
        if (proposal.loanContract == address(0)) revert NoLoanContract();
        if (address(proposal.assetsResolver) == address(0)) revert NoAssetsResolver();
        if (address(proposal.interestModule) == address(0)) revert NoInterestModule();
        if (address(proposal.defaultModule) == address(0)) revert NoDefaultModule();

        uint256 length = proposal.acceptanceHooks.length;
        if (length == 0) revert NoProposalAcceptorHook();
        uint256 dataLength = proposal.acceptanceHooksData.length;
        if (dataLength != length) revert AcceptorHooksDataLengthMismatch({ hooksLength: length, dataLength: dataLength });
    }

    function _erc712Hash(bytes32 domainSeparator, bytes32 typeHash, bytes memory encodedData) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            hex"1901", domainSeparator, keccak256(abi.encodePacked(typeHash, encodedData))
        ));
    }

    struct ERC712Proposal {
        address assetsResolver;
        bytes32 assetsResolverDataHash;
        address interestModule;
        bytes32 interestModuleDataHash;
        address defaultModule;
        bytes32 defaultModuleDataHash;
        bytes32 acceptanceHooksHash;
        bytes32 acceptanceHooksDataHash;
        address proposer;
        bytes32 proposerSpecHash;
        bool isProposerLender;
        address loanContract;
    }

    function _erc712EncodeProposal(Proposal memory proposal) internal pure returns (bytes memory) {
        ERC712Proposal memory erc712Proposal = ERC712Proposal({
            assetsResolver: address(proposal.assetsResolver),
            assetsResolverDataHash: keccak256(proposal.assetsResolverData),
            interestModule: proposal.interestModule,
            interestModuleDataHash: keccak256(proposal.interestModuleData),
            defaultModule: proposal.defaultModule,
            defaultModuleDataHash: keccak256(proposal.defaultModuleData),
            acceptanceHooksHash: keccak256(abi.encode(proposal.acceptanceHooks)),
            acceptanceHooksDataHash: keccak256(abi.encode(proposal.acceptanceHooksData)),
            proposer: proposal.proposer,
            proposerSpecHash: proposal.proposerSpecHash,
            isProposerLender: proposal.isProposerLender,
            loanContract: proposal.loanContract
        });
        return abi.encode(erc712Proposal);
    }

}
