// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { PWNSimpleLoan } from "@pwn/loan/terms/simple/loan/PWNSimpleLoan.sol";
import { PWNSimpleLoanProposal } from "@pwn/loan/terms/simple/proposal/PWNSimpleLoanProposal.sol";
import { Permit } from "@pwn/loan/vault/Permit.sol";
import "@pwn/PWNErrors.sol";


/**
 * @title PWN Simple Loan Simple Request
 * @notice Loan terms factory contract creating a simple loan terms from a simple request.
 */
contract PWNSimpleLoanSimpleRequest is PWNSimpleLoanProposal {

    string public constant VERSION = "1.2";

    /**
     * @dev EIP-712 simple request struct type hash.
     */
    bytes32 public constant REQUEST_TYPEHASH = keccak256(
        "Request(uint8 collateralCategory,address collateralAddress,uint256 collateralId,uint256 collateralAmount,bool checkCollateralStateFingerprint,bytes32 collateralStateFingerprint,address creditAddress,uint256 creditAmount,uint256 availableCreditLimit,uint256 fixedInterestAmount,uint40 accruingInterestAPR,uint32 duration,uint40 expiration,address allowedLender,address borrower,uint256 refinancingLoanId,uint256 nonceSpace,uint256 nonce,address loanContract)"
    );

    /**
     * @notice Construct defining a simple request.
     * @param collateralCategory Category of an asset used as a collateral (0 == ERC20, 1 == ERC721, 2 == ERC1155).
     * @param collateralAddress Address of an asset used as a collateral.
     * @param collateralId Token id of an asset used as a collateral, in case of ERC20 should be 0.
     * @param collateralAmount Amount of tokens used as a collateral, in case of ERC721 should be 0.
     * @param checkCollateralStateFingerprint If true, the collateral state fingerprint has to be checked.
     * @param collateralStateFingerprint Fingerprint of a collateral state defined by ERC5646.
     * @param creditAddress Address of an asset which is lender to a borrower.
     * @param creditAmount Amount of tokens which is requested as a loan to a borrower.
     * @param availableCreditLimit Available credit limit for the request. It is the maximum amount of tokens which can be borrowed using the request.
     * @param fixedInterestAmount Fixed interest amount in credit tokens. It is the minimum amount of interest which has to be paid by a borrower.
     * @param accruingInterestAPR Accruing interest APR.
     * @param duration Loan duration in seconds.
     * @param expiration Request expiration timestamp in seconds.
     * @param allowedLender Address of an allowed lender. Only this address can accept a request. If the address is zero address, anybody with a credit asset can accept the request.
     * @param borrower Address of a borrower. This address has to sign a request to be valid.
     * @param refinancingLoanId Id of a loan which is refinanced by this request. If the id is 0, the request is not a refinancing request.
     * @param nonceSpace Nonce space of a request nonce. All nonces in the same space can be revoked at once.
     * @param nonce Additional value to enable identical requests in time. Without it, it would be impossible to make again request, which was once revoked.
     *              Can be used to create a group of requests, where accepting one request will make other requests in the group revoked.
     * @param loanContract Address of a loan contract that will create a loan from the request.
     */
    struct Request {
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
        address allowedLender;
        address borrower;
        uint256 refinancingLoanId;
        uint256 nonceSpace;
        uint256 nonce;
        address loanContract;
    }

    /**
     * @dev Emitted when a proposal is made via an on-chain transaction.
     */
    event RequestMade(bytes32 indexed proposalHash, address indexed proposer, Request request);

    constructor(
        address _hub,
        address _revokedNonce,
        address _stateFingerprintComputerRegistry
    ) PWNSimpleLoanProposal(
        _hub, _revokedNonce, _stateFingerprintComputerRegistry, "PWNSimpleLoanSimpleRequest", VERSION
    ) {}

    /**
     * @notice Get a request hash according to EIP-712.
     * @param request Request struct to be hashed.
     * @return Request struct hash.
     */
    function getRequestHash(Request calldata request) public view returns (bytes32) {
        return _getProposalHash(REQUEST_TYPEHASH, abi.encode(request));
    }

    /**
     * @notice Make an on-chain request.
     * @dev Function will mark a request hash as proposed. Request will become acceptable by a lender without a request signature.
     * @param request Request struct containing all needed request data.
     * @return proposalHash Request hash.
     */
    function makeRequest(Request calldata request) external returns (bytes32 proposalHash){
        proposalHash = getRequestHash(request);
        _makeProposal(proposalHash, request.borrower);
        emit RequestMade(proposalHash, request.borrower, request);
    }


    function acceptRequest(
        Request calldata request,
        bytes calldata signature,
        Permit calldata permit,
        bytes calldata extra
    ) public returns (uint256 loanId) {
        // Check if the request is refinancing request
        if (request.refinancingLoanId != 0) {
            revert InvalidRefinancingLoanId({ refinancingLoanId: request.refinancingLoanId });
        }

        // Check permit
        _checkPermit(msg.sender, request.creditAddress, permit);

        // Accept request
        (bytes32 requestHash, PWNSimpleLoan.Terms memory loanTerms) = _acceptRequest(request, signature);

        // Create loan
        return PWNSimpleLoan(request.loanContract).createLOAN({
            proposalHash: requestHash,
            loanTerms: loanTerms,
            permit: permit,
            extra: extra
        });
    }

    function acceptRefinanceRequest(
        uint256 loanId,
        Request calldata request,
        bytes calldata signature,
        Permit calldata permit,
        bytes calldata extra
    ) public returns (uint256 refinancedLoanId) {
        // Check if the request is refinancing request
        if (request.refinancingLoanId == 0 || request.refinancingLoanId != loanId) {
            revert InvalidRefinancingLoanId({ refinancingLoanId: request.refinancingLoanId });
        }

        // Check permit
        _checkPermit(msg.sender, request.creditAddress, permit);

        // Accept request
        (bytes32 requestHash, PWNSimpleLoan.Terms memory loanTerms) = _acceptRequest(request, signature);

        // Refinance loan
        return PWNSimpleLoan(request.loanContract).refinanceLOAN({
            loanId: loanId,
            proposalHash: requestHash,
            loanTerms: loanTerms,
            permit: permit,
            extra: extra
        });
    }

    function acceptRequest(
        Request calldata request,
        bytes calldata signature,
        Permit calldata permit,
        bytes calldata extra,
        uint256 callersNonceSpace,
        uint256 callersNonceToRevoke
    ) external returns (uint256 loanId) {
        _revokeCallersNonce(msg.sender, callersNonceSpace, callersNonceToRevoke);
        return acceptRequest(request, signature, permit, extra);
    }

    function acceptRefinanceRequest(
        uint256 loanId,
        Request calldata request,
        bytes calldata signature,
        Permit calldata permit,
        bytes calldata extra,
        uint256 callersNonceSpace,
        uint256 callersNonceToRevoke
    ) external returns (uint256 refinancedLoanId) {
        _revokeCallersNonce(msg.sender, callersNonceSpace, callersNonceToRevoke);
        return acceptRefinanceRequest(loanId, request, signature, permit, extra);
    }


    /*----------------------------------------------------------*|
    |*  # INTERNALS                                             *|
    |*----------------------------------------------------------*/

    function _acceptRequest(
        Request calldata request,
        bytes calldata signature
    )  private returns (bytes32 requestHash, PWNSimpleLoan.Terms memory loanTerms) {
        // Check if the loan contract has a tag
        _checkLoanContractTag(request.loanContract);

        // Check collateral state fingerprint if needed
        if (request.checkCollateralStateFingerprint) {
            _checkCollateralState({
                addr: request.collateralAddress,
                id: request.collateralId,
                stateFingerprint: request.collateralStateFingerprint
            });
        }

        // Try to accept request
        requestHash = _tryAcceptRequest(request, signature);

        // Create loan terms object
        loanTerms = _createLoanTerms(request);
    }

    function _tryAcceptRequest(Request calldata request, bytes calldata signature) private returns (bytes32 requestHash) {
        requestHash = getRequestHash(request);
        _tryAcceptProposal({
            proposalHash: requestHash,
            creditAmount: request.creditAmount,
            availableCreditLimit: request.availableCreditLimit,
            apr: request.accruingInterestAPR,
            duration: request.duration,
            expiration: request.expiration,
            nonceSpace: request.nonceSpace,
            nonce: request.nonce,
            allowedAcceptor: request.allowedLender,
            acceptor: msg.sender,
            signer: request.borrower,
            signature: signature
        });
    }

    function _createLoanTerms(Request calldata request) private view returns (PWNSimpleLoan.Terms memory) {
        return PWNSimpleLoan.Terms({
            lender: msg.sender,
            borrower: request.borrower,
            duration: request.duration,
            collateral: MultiToken.Asset({
                category: request.collateralCategory,
                assetAddress: request.collateralAddress,
                id: request.collateralId,
                amount: request.collateralAmount
            }),
            credit: MultiToken.ERC20({
                assetAddress: request.creditAddress,
                amount: request.creditAmount
            }),
            fixedInterestAmount: request.fixedInterestAmount,
            accruingInterestAPR: request.accruingInterestAPR
        });
    }

}
