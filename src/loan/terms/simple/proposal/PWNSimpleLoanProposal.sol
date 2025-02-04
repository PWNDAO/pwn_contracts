// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MerkleProof } from "openzeppelin/utils/cryptography/MerkleProof.sol";
import { ERC165Checker } from "openzeppelin/utils/introspection/ERC165Checker.sol";

import { PWNConfig, IStateFingerpringComputer } from "pwn/config/PWNConfig.sol";
import { PWNHub } from "pwn/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/hub/PWNHubTags.sol";
import { IERC5646 } from "pwn/interfaces/IERC5646.sol";
import { IPWNAcceptorController } from "pwn/interfaces/IPWNAcceptorController.sol";
import { PWNSignatureChecker } from "pwn/loan/lib/PWNSignatureChecker.sol";
import { PWNSimpleLoan } from "pwn/loan/terms/simple/loan/PWNSimpleLoan.sol";
import { PWNUtilizedCredit } from "pwn/utilized-credit/PWNUtilizedCredit.sol";
import { PWNRevokedNonce } from "pwn/nonce/PWNRevokedNonce.sol";
import { Expired, AddressMissingHubTag } from "pwn/PWNErrors.sol";

/**
 * @title PWN Simple Loan Proposal Base Contract
 * @notice Base contract of loan proposals that builds a simple loan terms.
 */
abstract contract PWNSimpleLoanProposal {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 public immutable MULTIPROPOSAL_DOMAIN_SEPARATOR;

    PWNHub public immutable hub;
    PWNRevokedNonce public immutable revokedNonce;
    PWNConfig public immutable config;
    PWNUtilizedCredit public immutable utilizedCredit;

    bytes32 public constant MULTIPROPOSAL_TYPEHASH = keccak256("Multiproposal(bytes32 multiproposalMerkleRoot)");

    struct Multiproposal {
        bytes32 multiproposalMerkleRoot;
    }

    struct ProposalBase {
        address collateralAddress;
        uint256 collateralId;
        bool checkCollateralStateFingerprint;
        bytes32 collateralStateFingerprint;
        uint256 creditAmount;
        uint256 availableCreditLimit;
        bytes32 utilizedCreditId;
        uint40 expiration;
        address acceptorController;
        bytes acceptorControllerData;
        address proposer;
        bool isOffer;
        uint256 refinancingLoanId;
        uint256 nonceSpace;
        uint256 nonce;
        address loanContract;
    }

    struct ProposalValuesBase {
        uint256 refinancingLoanId;
        address acceptor;
        bytes acceptorControllerData;
    }

    /**
     * @dev Mapping of proposals made via on-chain transactions.
     *      Could be used by contract wallets instead of EIP-1271.
     *      (proposal hash => is made)
     */
    mapping (bytes32 => bool) public proposalsMade;


    /*----------------------------------------------------------*|
    |*  # ERRORS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /**
     * @notice Thrown when a caller is missing a required hub tag.
     */
    error CallerNotLoanContract(address caller, address loanContract);

    /**
     * @notice Thrown when a state fingerprint computer is not registered.
     */
    error MissingStateFingerprintComputer();

    /**
     * @notice Thrown when a proposed collateral state fingerprint doesn't match the current state.
     */
    error InvalidCollateralStateFingerprint(bytes32 current, bytes32 proposed);

    /**
     * @notice Thrown when a caller is not a stated proposer.
     */
    error CallerIsNotStatedProposer(address addr);

    /**
     * @notice Thrown when proposal acceptor and proposer are the same.
     */
    error AcceptorIsProposer(address addr);

    /**
     * @notice Thrown when provided refinance loan id cannot be used.
     */
    error InvalidRefinancingLoanId(uint256 refinancingLoanId);

    /**
     * @notice Thrown when acceptor controller is invalid.
     */
    error InvalidAcceptorController(address acceptorController);

    /**
     * @notice Thrown when a default date is in the past.
     */
    error DefaultDateInPast(uint32 defaultDate, uint32 current);


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(
        address _hub,
        address _revokedNonce,
        address _config,
        address _utilizedCredit,
        string memory name,
        string memory version
    ) {
        hub = PWNHub(_hub);
        revokedNonce = PWNRevokedNonce(_revokedNonce);
        config = PWNConfig(_config);
        utilizedCredit = PWNUtilizedCredit(_utilizedCredit);

        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(abi.encodePacked(name)),
            keccak256(abi.encodePacked(version)),
            block.chainid,
            address(this)
        ));

        MULTIPROPOSAL_DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name)"),
            keccak256("PWNMultiproposal")
        ));
    }


    /*----------------------------------------------------------*|
    |*  # EXTERNALS                                             *|
    |*----------------------------------------------------------*/

    /**
     * @notice Get a multiproposal hash according to EIP-712.
     * @param multiproposal Multiproposal struct.
     * @return Multiproposal hash.
     */
    function getMultiproposalHash(Multiproposal memory multiproposal) public view returns (bytes32) {
        return keccak256(abi.encodePacked(
            hex"1901", MULTIPROPOSAL_DOMAIN_SEPARATOR, keccak256(abi.encodePacked(
                MULTIPROPOSAL_TYPEHASH, abi.encode(multiproposal)
            ))
        ));
    }

    /**
     * @notice Helper function for revoking a proposal nonce on behalf of a caller.
     * @param nonceSpace Nonce space of a proposal nonce to be revoked.
     * @param nonce Proposal nonce to be revoked.
     */
    function revokeNonce(uint256 nonceSpace, uint256 nonce) external {
        revokedNonce.revokeNonce(msg.sender, nonceSpace, nonce);
    }

    /**
     * @notice Accept a proposal and create new loan terms.
     * @dev Function can be called only by a loan contract with appropriate PWN Hub tag.
     * @param acceptor Address of a proposal acceptor.
     * @param refinancingLoanId Id of a loan to be refinanced. 0 if creating a new loan.
     * @param proposalData Encoded proposal data with signature.
     * @param proposalInclusionProof Multiproposal inclusion proof. Empty if single proposal.
     * @return proposalHash Proposal hash.
     * @return loanTerms Loan terms.
     */
    function acceptProposal(
        address acceptor,
        uint256 refinancingLoanId,
        bytes calldata proposalData,
        bytes32[] calldata proposalInclusionProof,
        bytes calldata signature
    ) virtual external returns (bytes32 proposalHash, PWNSimpleLoan.Terms memory loanTerms);


    /*----------------------------------------------------------*|
    |*  # INTERNALS                                             *|
    |*----------------------------------------------------------*/

    /**
     * @notice Get a proposal hash according to EIP-712.
     * @param encodedProposal Encoded proposal struct.
     * @return Struct hash.
     */
    function _getProposalHash(
        bytes32 proposalTypehash,
        bytes memory encodedProposal
    ) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            hex"1901", DOMAIN_SEPARATOR, keccak256(abi.encodePacked(
                proposalTypehash, encodedProposal
            ))
        ));
    }

    /**
     * @notice Make an on-chain proposal.
     * @dev Function will mark a proposal hash as proposed.
     * @param proposalHash Proposal hash.
     * @param proposer Address of a proposal proposer.
     */
    function _makeProposal(bytes32 proposalHash, address proposer) internal {
        if (msg.sender != proposer) {
            revert CallerIsNotStatedProposer({ addr: proposer });
        }

        proposalsMade[proposalHash] = true;
    }

    /**
     * @notice Get loan duration from a duration or date value.
     * @param durationOrDate Duration or date value.
     * @return Loan duration.
     */
    function _getLoanDuration(uint32 durationOrDate) internal view returns (uint32) {
        if (durationOrDate <= 1e9) {
            // Value is duration
            return durationOrDate;
        } else if (durationOrDate > block.timestamp) {
            // Value is date
            return uint32(uint256(durationOrDate) - block.timestamp);
        } else {
            revert DefaultDateInPast({ defaultDate: durationOrDate, current: uint32(block.timestamp) });
        }
    }

    /**
     * @notice Try to accept proposal base.
     * @param proposalHash Proposal hash.
     * @param proposalInclusionProof Multiproposal inclusion proof. Empty if single proposal.
     * @param signature Signature of a proposal.
     * @param proposal Proposal base struct.
     * @param proposalValues Proposal values struct.
     */
    function _acceptProposal(
        bytes32 proposalHash,
        bytes32[] calldata proposalInclusionProof,
        bytes calldata signature,
        ProposalBase memory proposal,
        ProposalValuesBase memory proposalValues
    ) internal {
        // Check loan contract
        if (msg.sender != proposal.loanContract) {
            revert CallerNotLoanContract({ caller: msg.sender, loanContract: proposal.loanContract });
        }
        if (!hub.hasTag(proposal.loanContract, PWNHubTags.ACTIVE_LOAN)) {
            revert AddressMissingHubTag({ addr: proposal.loanContract, tag: PWNHubTags.ACTIVE_LOAN });
        }

        // Check proposal signature or that it was made on-chain
        if (proposalInclusionProof.length == 0) {
            // Single proposal signature
            if (!proposalsMade[proposalHash]) {
                if (!PWNSignatureChecker.isValidSignatureNow(proposal.proposer, proposalHash, signature)) {
                    revert PWNSignatureChecker.InvalidSignature({ signer: proposal.proposer, digest: proposalHash });
                }
            }
        } else {
            // Multiproposal signature
            bytes32 multiproposalHash = getMultiproposalHash(
                Multiproposal({
                    multiproposalMerkleRoot: MerkleProof.processProofCalldata({
                        proof: proposalInclusionProof,
                        leaf: proposalHash
                    })
                })
            );
            if (!PWNSignatureChecker.isValidSignatureNow(proposal.proposer, multiproposalHash, signature)) {
                revert PWNSignatureChecker.InvalidSignature({ signer: proposal.proposer, digest: multiproposalHash });
            }
        }

        // Check proposer is not acceptor
        if (proposal.proposer == proposalValues.acceptor) {
            revert AcceptorIsProposer({ addr: proposalValues.acceptor});
        }

        // Check refinancing proposal
        if (proposalValues.refinancingLoanId == 0) {
            if (proposal.refinancingLoanId != 0) {
                revert InvalidRefinancingLoanId({ refinancingLoanId: proposal.refinancingLoanId });
            }
        } else {
            if (proposalValues.refinancingLoanId != proposal.refinancingLoanId) {
                if (proposal.refinancingLoanId != 0 || !proposal.isOffer) {
                    revert InvalidRefinancingLoanId({ refinancingLoanId: proposal.refinancingLoanId });
                }
            }
        }

        // Check proposal is not expired
        if (block.timestamp >= proposal.expiration) {
            revert Expired({ current: block.timestamp, expiration: proposal.expiration });
        }

        // Check proposal is not revoked
        if (!revokedNonce.isNonceUsable(proposal.proposer, proposal.nonceSpace, proposal.nonce)) {
            revert PWNRevokedNonce.NonceNotUsable({
                addr: proposal.proposer,
                nonceSpace: proposal.nonceSpace,
                nonce: proposal.nonce
            });
        }

        // Check proposal acceptor controller
        if (proposal.acceptorController != address(0)) {
            if (IPWNAcceptorController(proposal.acceptorController).checkAcceptor({
                acceptor: proposalValues.acceptor,
                proposerData: proposal.acceptorControllerData,
                acceptorData: proposalValues.acceptorControllerData
            }) != type(IPWNAcceptorController).interfaceId) {
                revert InvalidAcceptorController({ acceptorController: proposal.acceptorController });
            }
        }

        if (proposal.availableCreditLimit == 0) {
            // Revoke nonce if credit limit is 0, proposal can be accepted only once
            revokedNonce.revokeNonce(proposal.proposer, proposal.nonceSpace, proposal.nonce);
        } else {
            // Update utilized credit
            // Note: This will revert if utilized credit would exceed the available credit limit
            utilizedCredit.utilizeCredit(
                proposal.proposer, proposal.utilizedCreditId, proposal.creditAmount, proposal.availableCreditLimit
            );
        }

        // Check collateral state fingerprint if needed
        if (proposal.checkCollateralStateFingerprint) {
            bytes32 currentFingerprint;
            IStateFingerpringComputer computer = config.getStateFingerprintComputer(proposal.collateralAddress);
            if (address(computer) != address(0)) {
                // Asset has registered computer
                currentFingerprint = computer.computeStateFingerprint({
                    token: proposal.collateralAddress, tokenId: proposal.collateralId
                });
            } else if (ERC165Checker.supportsInterface(proposal.collateralAddress, type(IERC5646).interfaceId)) {
                // Asset implements ERC5646
                currentFingerprint = IERC5646(proposal.collateralAddress).getStateFingerprint(proposal.collateralId);
            } else {
                // Asset is not implementing ERC5646 and no computer is registered
                revert MissingStateFingerprintComputer();
            }

            if (proposal.collateralStateFingerprint != currentFingerprint) {
                // Fingerprint mismatch
                revert InvalidCollateralStateFingerprint({
                    current: currentFingerprint,
                    proposed: proposal.collateralStateFingerprint
                });
            }
        }
    }

}
