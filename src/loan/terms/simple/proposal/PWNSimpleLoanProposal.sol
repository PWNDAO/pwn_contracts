// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { PWNConfig, IERC5646 } from "@pwn/config/PWNConfig.sol";
import { PWNHub } from "@pwn/hub/PWNHub.sol";
import { PWNHubTags } from "@pwn/hub/PWNHubTags.sol";
import { PWNSignatureChecker } from "@pwn/loan/lib/PWNSignatureChecker.sol";
import { Permit } from "@pwn/loan/vault/Permit.sol";
import { PWNRevokedNonce } from "@pwn/nonce/PWNRevokedNonce.sol";
import "@pwn/PWNErrors.sol";

/**
 * @title PWN Simple Loan Proposal Base Contract
 * @notice Base contract of loan proposals that builds a simple loan terms.
 */
abstract contract PWNSimpleLoanProposal {

    uint32 public constant MIN_LOAN_DURATION = 10 minutes;
    uint40 public constant MAX_ACCRUING_INTEREST_APR = 1e11; // 1,000,000% APR

    bytes32 public immutable DOMAIN_SEPARATOR;

    PWNHub public immutable hub;
    PWNRevokedNonce public immutable revokedNonce;
    PWNConfig public immutable config;

    /**
     * @dev Mapping of proposals made via on-chain transactions.
     *      Could be used by contract wallets instead of EIP-1271.
     *      (proposal hash => is made)
     */
    mapping (bytes32 => bool) public proposalsMade;

    /**
     * @dev Mapping of credit used by a proposal with defined available credit limit.
     *      (proposal hash => credit used)
     */
    mapping (bytes32 => uint256) public creditUsed;

    constructor(
        address _hub,
        address _revokedNonce,
        address _config,
        string memory name,
        string memory version
    ) {
        hub = PWNHub(_hub);
        revokedNonce = PWNRevokedNonce(_revokedNonce);
        config = PWNConfig(_config);

        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(abi.encodePacked(name)),
            keccak256(abi.encodePacked(version)),
            block.chainid,
            address(this)
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


    /*----------------------------------------------------------*|
    |*  # INTERNALS                                             *|
    |*----------------------------------------------------------*/

    /**
     * @notice Try to accept a proposal.
     * @param proposalHash Proposal hash.
     * @param creditAmount Amount of credit to be used.
     * @param availableCreditLimit Available credit limit.
     * @param apr Accruing interest APR.
     * @param duration Loan duration.
     * @param expiration Proposal expiration.
     * @param nonceSpace Nonce space of a proposal nonce.
     * @param nonce Proposal nonce.
     * @param allowedAcceptor Allowed acceptor address.
     * @param acceptor Acctual acceptor address.
     * @param signer Signer address.
     * @param signature Signature of a proposal.
     */
    function _tryAcceptProposal(
        bytes32 proposalHash,
        uint256 creditAmount,
        uint256 availableCreditLimit,
        uint40 apr,
        uint32 duration,
        uint40 expiration,
        uint256 nonceSpace,
        uint256 nonce,
        address allowedAcceptor,
        address acceptor,
        address signer,
        bytes memory signature
    ) internal {
        // Check proposal has been made via on-chain tx, EIP-1271 or signed off-chain
        if (!proposalsMade[proposalHash]) {
            if (!PWNSignatureChecker.isValidSignatureNow(signer, proposalHash, signature)) {
                revert InvalidSignature({ signer: signer, digest: proposalHash });
            }
        }

        // Check proposal is not expired
        if (block.timestamp >= expiration) {
            revert Expired({ current: block.timestamp, expiration: expiration });
        }

        // Check proposal is not revoked
        if (!revokedNonce.isNonceUsable(signer, nonceSpace, nonce)) {
            revert NonceNotUsable({ addr: signer, nonceSpace: nonceSpace, nonce: nonce });
        }

        // Check propsal is accepted by an allowed address
        if (allowedAcceptor != address(0) && acceptor != allowedAcceptor) {
            revert CallerNotAllowedAcceptor({ current: acceptor, allowed: allowedAcceptor });
        }

        // Check minimum loan duration
        if (duration < MIN_LOAN_DURATION) {
            revert InvalidDuration({ current: duration, limit: MIN_LOAN_DURATION });
        }

        // Check maximum accruing interest APR
        if (apr > MAX_ACCRUING_INTEREST_APR) {
            revert AccruingInterestAPROutOfBounds({ current: apr, limit: MAX_ACCRUING_INTEREST_APR });
        }

        if (availableCreditLimit == 0) {
            // Revoke nonce if credit limit is 0, proposal can be accepted only once
            revokedNonce.revokeNonce(signer, nonceSpace, nonce);
        } else if (creditUsed[proposalHash] + creditAmount <= availableCreditLimit) {
            // Increase used credit if credit limit is not exceeded
            creditUsed[proposalHash] += creditAmount;
        } else {
            // Revert if credit limit is exceeded
            revert AvailableCreditLimitExceeded({
                used: creditUsed[proposalHash] + creditAmount,
                limit: availableCreditLimit
            });
        }
    }

    /**
     * @notice Check if a collateral state fingerprint is valid.
     * @param addr Address of a collateral contract.
     * @param id Collateral ID.
     * @param stateFingerprint Proposed state fingerprint.
     */
    function _checkCollateralState(address addr, uint256 id, bytes32 stateFingerprint) internal view {
        IERC5646 computer = config.getStateFingerprintComputer(addr);
        if (address(computer) == address(0)) {
            // Asset is not implementing ERC5646 and no computer is registered
            revert MissingStateFingerprintComputer();
        }

        bytes32 currentFingerprint = computer.getStateFingerprint(id);
        if (stateFingerprint != currentFingerprint) {
            // Fingerprint mismatch
            revert InvalidCollateralStateFingerprint({
                current: currentFingerprint,
                proposed: stateFingerprint
            });
        }
    }

    /**
     * @notice Check if a loan contract has an active loan tag.
     * @param loanContract Loan contract address.
     */
    function _checkLoanContractTag(address loanContract) internal view {
        if (!hub.hasTag(loanContract, PWNHubTags.ACTIVE_LOAN)) {
            revert AddressMissingHubTag({ addr: loanContract, tag: PWNHubTags.ACTIVE_LOAN });
        }
    }

    /**
     * @notice Check that permit data have correct owner and asset.
     * @param caller Caller address.
     * @param creditAddress Address of a credit to be used.
     * @param permit Permit to be checked.
     */
    function _checkPermit(address caller, address creditAddress, Permit calldata permit) internal pure {
        if (permit.asset != address(0)) {
            if (permit.owner != caller) {
                revert InvalidPermitOwner({ current: permit.owner, expected: caller});
            }
            if (creditAddress != permit.asset) {
                revert InvalidPermitAsset({ current: permit.asset, expected: creditAddress });
            }
        }
    }

    /**
     * @notice Check if refinancing loan ID is valid.
     * @param refinancingLoanId Refinancing loan ID.
     * @param proposalRefinancingLoanId Proposal refinancing loan ID.
     * @param isOffer True if proposal is an offer, false if it is a request.
     */
    function _checkRefinancingLoanId(
        uint256 refinancingLoanId,
        uint256 proposalRefinancingLoanId,
        bool isOffer
    ) internal pure {
        if (refinancingLoanId == 0) {
            if (proposalRefinancingLoanId != 0) {
                revert InvalidRefinancingLoanId({ refinancingLoanId: proposalRefinancingLoanId });
            }
        } else {
            if (refinancingLoanId != proposalRefinancingLoanId) {
                if (proposalRefinancingLoanId != 0 || !isOffer) {
                    revert InvalidRefinancingLoanId({ refinancingLoanId: proposalRefinancingLoanId });
                }
            }
        }
    }

    /**
     * @notice Make an on-chain proposal.
     * @dev Function will mark a proposal hash as proposed.
     * @param proposalHash Proposal hash.
     * @param proposer Address of a proposal proposer.
     */
    function _makeProposal(bytes32 proposalHash, address proposer) internal {
        if (msg.sender != proposer) {
            revert CallerIsNotStatedProposer(proposer);
        }

        proposalsMade[proposalHash] = true;
    }

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
     * @notice Revoke a nonce of a caller.
     * @param caller Caller address.
     * @param nonceSpace Nonce space of a nonce to be revoked.
     * @param nonce Nonce to be revoked.
     */
    function _revokeCallersNonce(address caller, uint256 nonceSpace, uint256 nonce) internal {
        if (!revokedNonce.isNonceUsable(caller, nonceSpace, nonce)) {
            revert NonceNotUsable({ addr: caller, nonceSpace: nonceSpace, nonce: nonce });
        }
        revokedNonce.revokeNonce(caller, nonceSpace, nonce);
    }

}
