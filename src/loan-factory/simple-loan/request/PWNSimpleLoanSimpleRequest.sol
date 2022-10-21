// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "MultiToken/MultiToken.sol";

import "@pwn/loan-factory/lib/PWNSignatureChecker.sol";
import "@pwn/loan-factory/simple-loan/request/PWNSimpleLoanRequest.sol";
import "@pwn/PWNErrors.sol";


/**
 * @title PWN Simple Loan Simple Request
 * @notice Loan factory contract creating a simple loan from a simple request.
 */
contract PWNSimpleLoanSimpleRequest is PWNSimpleLoanRequest {

    string internal constant VERSION = "0.1.0";

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    /**
     * @dev EIP-712 simple request struct type hash.
     */
    bytes32 constant internal REQUEST_TYPEHASH = keccak256(
        "Request(uint8 collateralCategory,address collateralAddress,uint256 collateralId,uint256 collateralAmount,address loanAssetAddress,uint256 loanAmount,uint256 loanYield,uint32 duration,uint40 expiration,address borrower,address lender,bytes32 nonce)"
    );

    /**
     * @notice Construct defining a simple request.
     * @param collateralCategory Category of an asset used as a collateral (0 == ERC20, 1 == ERC721, 2 == ERC1155).
     * @param collateralAddress Address of an asset used as a collateral.
     * @param collateralId Token id of an asset used as a collateral, in case of ERC20 should be 0.
     * @param collateralAmount Amount of tokens used as a collateral, in case of ERC721 should be 1.
     * @param loanAssetAddress Address of an asset which is lended to a borrower.
     * @param loanAmount Amount of tokens which is requested as a loan to a borrower
     * @param loanYield Amount of tokens which acts as a lenders loan interest. Borrower has to pay back a borrowed amount + yield.
     * @param duration Loan duration in seconds.
     * @param expiration Request expiration timestamp in seconds.
     * @param borrower Address of a borrower. This address has to sign a request to be valid.
     * @param lender Address of a lender. Only this address can accept a request. If the address is zero address, anybody with a loan asset can accept the request.
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
        uint256 loanYield;
        uint32 duration;
        uint40 expiration;
        address borrower;
        address lender;
        bytes32 nonce;
    }

    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(address hub, address revokedRequestNonce) PWNSimpleLoanRequest(hub, revokedRequestNonce) {

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
        _makeRequest(getRequestHash(request), request.borrower, request.nonce);
    }


    /*----------------------------------------------------------*|
    |*  # IPWNSimpleLoanFactory                                 *|
    |*----------------------------------------------------------*/

    /**
     * @notice See { IPWNSimpleLoanFactory.sol }.
     */
    function createLOAN(
        address caller,
        bytes calldata loanFactoryData,
        bytes calldata signature
    ) external override onlyActiveLoan returns (PWNSimpleLoan.LOANTerms memory loanTerms) {

        Request memory request = abi.decode(loanFactoryData, (Request));
        bytes32 requestHash = getRequestHash(request);

        address lender = caller;
        address borrower = request.borrower;

        // Check that request has been made via on-chain tx, EIP-1271 or signed off-chain
        if (requestsMade[requestHash] == false)
            if (PWNSignatureChecker.isValidSignatureNow(borrower, requestHash, signature) == false)
                revert InvalidSignature();

        // Check valid request
        if (request.expiration != 0 && block.timestamp >= request.expiration)
            revert RequestExpired();

        if (revokedRequestNonce.isRequestNonceRevoked(borrower, request.nonce) == true)
            revert NonceRevoked();

        if (request.lender != address(0))
            if (lender != request.lender)
                revert CallerIsNotStatedLender(request.lender);

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

        // Create loan object
        loanTerms = PWNSimpleLoan.LOANTerms({
            lender: lender,
            borrower: borrower,
            expiration: uint40(block.timestamp) + request.duration,
            collateral: collateral,
            asset: loanAsset,
            loanRepayAmount: request.loanAmount + request.loanYield
        });

        revokedRequestNonce.revokeRequestNonce(borrower, request.nonce);
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
            "\x19\x01",
            keccak256(abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("PWNSimpleLoanSimpleRequest"),
                keccak256("1"),
                block.chainid,
                address(this)
            )),
            keccak256(abi.encodePacked(
                REQUEST_TYPEHASH,
                abi.encode(
                    request.collateralCategory,
                    request.collateralAddress,
                    request.collateralId,
                    request.collateralAmount
                ), // Need to prevent `slot(s) too deep inside the stack` error
                abi.encode(
                    request.loanAssetAddress,
                    request.loanAmount,
                    request.loanYield,
                    request.duration,
                    request.expiration,
                    request.borrower,
                    request.lender,
                    request.nonce
                )
            ))
        ));
    }


    /*----------------------------------------------------------*|
    |*  # LOAN FACTORY DATA ENCODING                            *|
    |*----------------------------------------------------------*/

    /**
     * @notice Return encoded input data for this loan factory.
     * @param request Simple loan simple request struct to encode.
     * @return Encoded loan factory data that can be used as an input of `createLOAN` function with this loan factory.
     */
    function encodeLoanFactoryData(Request memory request) external pure returns (bytes memory) {
        return abi.encode(request);
    }

}
