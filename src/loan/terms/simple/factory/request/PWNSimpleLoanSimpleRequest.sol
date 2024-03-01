// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { PWNSignatureChecker } from "@pwn/loan/lib/PWNSignatureChecker.sol";
import { PWNSimpleLoanRequest, PWNSimpleLoanTermsFactory } from "@pwn/loan/terms/simple/factory/request/base/PWNSimpleLoanRequest.sol";
import { PWNLOANTerms } from "@pwn/loan/terms/PWNLOANTerms.sol";
import "@pwn/PWNErrors.sol";


/**
 * @title PWN Simple Loan Simple Request
 * @notice Loan terms factory contract creating a simple loan terms from a simple request.
 */
contract PWNSimpleLoanSimpleRequest is PWNSimpleLoanRequest {

    string public constant VERSION = "1.2";

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    /**
     * @dev EIP-712 simple request struct type hash.
     */
    bytes32 public constant REQUEST_TYPEHASH = keccak256(
        "Request(uint8 collateralCategory,address collateralAddress,uint256 collateralId,uint256 collateralAmount,address loanAssetAddress,uint256 loanAmount,uint256 fixedInterestAmount,uint40 accruingInterestAPR,uint32 duration,uint40 expiration,address allowedLender,address borrower,uint256 refinancingLoanId,uint256 nonceSpace,uint256 nonce)"
    );

    bytes32 public immutable DOMAIN_SEPARATOR;

    /**
     * @notice Construct defining a simple request.
     * @param collateralCategory Category of an asset used as a collateral (0 == ERC20, 1 == ERC721, 2 == ERC1155).
     * @param collateralAddress Address of an asset used as a collateral.
     * @param collateralId Token id of an asset used as a collateral, in case of ERC20 should be 0.
     * @param collateralAmount Amount of tokens used as a collateral, in case of ERC721 should be 0.
     * @param loanAssetAddress Address of an asset which is lender to a borrower.
     * @param loanAmount Amount of tokens which is requested as a loan to a borrower.
     * @param fixedInterestAmount Fixed interest amount in loan asset tokens. It is the minimum amount of interest which has to be paid by a borrower.
     * @param accruingInterestAPR Accruing interest APR.
     * @param duration Loan duration in seconds.
     * @param expiration Request expiration timestamp in seconds.
     * @param allowedLender Address of an allowed lender. Only this address can accept a request. If the address is zero address, anybody with a loan asset can accept the request.
     * @param borrower Address of a borrower. This address has to sign a request to be valid.
     * @param refinancingLoanId Id of a loan which is refinanced by this request. If the id is 0, the request is not a refinancing request.
     * @param nonceSpace Nonce space of a request nonce. All nonces in the same space can be revoked at once.
     * @param nonce Additional value to enable identical requests in time. Without it, it would be impossible to make again request, which was once revoked.
     *              Can be used to create a group of requests, where accepting one request will make other requests in the group revoked.
     */
    struct Request {
        MultiToken.Category collateralCategory;
        address collateralAddress;
        uint256 collateralId;
        uint256 collateralAmount;
        address loanAssetAddress;
        uint256 loanAmount;
        uint256 fixedInterestAmount;
        uint40 accruingInterestAPR;
        uint32 duration;
        uint40 expiration;
        address allowedLender;
        address borrower;
        uint256 refinancingLoanId;
        uint256 nonceSpace;
        uint256 nonce;
    }


    /*----------------------------------------------------------*|
    |*  # EVENTS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /**
     * @dev Emitted when a request is made via an on-chain transaction.
     */
    event RequestMade(bytes32 indexed requestHash, address indexed borrower, Request request);


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(address hub, address revokedRequestNonce) PWNSimpleLoanRequest(hub, revokedRequestNonce) {
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256("PWNSimpleLoanSimpleRequest"),
            keccak256(abi.encodePacked(VERSION)),
            block.chainid,
            address(this)
        ));
    }


    /*----------------------------------------------------------*|
    |*  # REQUEST MANAGEMENT                                    *|
    |*----------------------------------------------------------*/

    /**
     * @notice Make an on-chain request.
     * @dev Function will mark a request hash as proposed. Request will become acceptable by a lender without a request signature.
     * @param request Request struct containing all needed request data.
     */
    function makeRequest(Request calldata request) external {
        bytes32 requestHash = getRequestHash(request);
        _makeRequest(requestHash, request.borrower);
        emit RequestMade(requestHash, request.borrower, request);
    }


    /*----------------------------------------------------------*|
    |*  # PWNSimpleLoanTermsFactory                             *|
    |*----------------------------------------------------------*/

    /**
     * @inheritdoc PWNSimpleLoanTermsFactory
     */
    function createLOANTerms(
        address caller,
        bytes calldata factoryData,
        bytes calldata signature
    ) external override onlyActiveLoan returns (PWNLOANTerms.Simple memory loanTerms, bytes32 requestHash) {

        Request memory request = abi.decode(factoryData, (Request));
        requestHash = getRequestHash(request);

        address lender = caller;
        address borrower = request.borrower;

        // Check that request has been made via on-chain tx, EIP-1271 or signed off-chain
        if (!requestsMade[requestHash])
            if (!PWNSignatureChecker.isValidSignatureNow(borrower, requestHash, signature))
                revert InvalidSignature();

        // Check valid request
        if (block.timestamp >= request.expiration)
            revert RequestExpired();

        if (revokedRequestNonce.isNonceRevoked(borrower, request.nonceSpace, request.nonce))
            revert NonceAlreadyRevoked();

        if (request.allowedLender != address(0))
            if (lender != request.allowedLender)
                revert CallerIsNotStatedLender(request.allowedLender);

        if (request.duration < MIN_LOAN_DURATION)
            revert InvalidDuration();

        // Check APR
        if (request.accruingInterestAPR > MAX_ACCRUING_INTEREST_APR)
            revert AccruingInterestAPROutOfBounds({
                providedAPR: request.accruingInterestAPR,
                maxAPR: MAX_ACCRUING_INTEREST_APR
            });

        // Prepare collateral and loan asset
        MultiToken.Asset memory collateral = MultiToken.Asset({
            category: request.collateralCategory,
            assetAddress: request.collateralAddress,
            id: request.collateralId,
            amount: request.collateralAmount
        });
        MultiToken.Asset memory loanAsset = MultiToken.Asset({
            category: MultiToken.Category.ERC20,
            assetAddress: request.loanAssetAddress,
            id: 0,
            amount: request.loanAmount
        });

        // Create loan terms object
        loanTerms = PWNLOANTerms.Simple({
            lender: lender,
            borrower: borrower,
            defaultTimestamp: uint40(block.timestamp) + request.duration,
            collateral: collateral,
            asset: loanAsset,
            fixedInterestAmount: request.fixedInterestAmount,
            accruingInterestAPR: request.accruingInterestAPR,
            canCreate: request.refinancingLoanId == 0,
            canRefinance: request.refinancingLoanId != 0,
            refinancingLoanId: request.refinancingLoanId
        });

        revokedRequestNonce.revokeNonce(borrower, request.nonceSpace, request.nonce);
    }


    /*----------------------------------------------------------*|
    |*  # GET REQUEST HASH                                      *|
    |*----------------------------------------------------------*/

    /**
     * @notice Get a request hash according to EIP-712.
     * @param request Request struct to be hashed.
     * @return Request struct hash.
     */
    function getRequestHash(Request memory request) public view returns (bytes32) {
        return keccak256(abi.encodePacked(
            hex"1901",
            DOMAIN_SEPARATOR,
            keccak256(abi.encodePacked(
                REQUEST_TYPEHASH,
                abi.encode(request)
            ))
        ));
    }


    /*----------------------------------------------------------*|
    |*  # LOAN TERMS FACTORY DATA ENCODING                      *|
    |*----------------------------------------------------------*/

    /**
     * @notice Return encoded input data for this loan terms factory.
     * @param request Simple loan simple request struct to encode.
     * @return Encoded loan terms factory data that can be used as an input of `createLOANTerms` function with this factory.
     */
    function encodeLoanTermsFactoryData(Request memory request) external pure returns (bytes memory) {
        return abi.encode(request);
    }

}
