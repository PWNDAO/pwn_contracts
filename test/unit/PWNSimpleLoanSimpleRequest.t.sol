// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "MultiToken/MultiToken.sol";

import "@pwn/hub/PWNHubTags.sol";
import "@pwn/loan/type/PWNSimpleLoan.sol";
import "@pwn/loan-factory/simple-loan/request/PWNSimpleLoanSimpleRequest.sol";
import "@pwn/PWNErrors.sol";


abstract contract PWNSimpleLoanSimpleRequestTest is Test {

    bytes32 internal constant REQUESTS_MADE_SLOT = bytes32(uint256(0)); // `requestsMade` mapping position

    PWNSimpleLoanSimpleRequest requestContract;
    address hub = address(0x80b);
    address revokedRequestNonce = address(0x80c);
    address activeLoanContract = address(0x80d);
    PWNSimpleLoanSimpleRequest.Request request;
    address token = address(0x070ce2);
    uint256 borrowerPK = uint256(73661723);
    address borrower = vm.addr(borrowerPK);

    constructor() {
        vm.etch(hub, bytes("data"));
        vm.etch(revokedRequestNonce, bytes("data"));
        vm.etch(token, bytes("data"));
    }

    function setUp() virtual public {
        requestContract = new PWNSimpleLoanSimpleRequest(hub, revokedRequestNonce);

        request = PWNSimpleLoanSimpleRequest.Request({
            collateralCategory: MultiToken.Category.ERC721,
            collateralAddress: token,
            collateralId: 42,
            collateralAmount: 1032,
            loanAssetAddress: token,
            loanAmount: 1101001,
            loanYield: 1,
            duration: 1000,
            expiration: 0,
            borrower: borrower,
            lender: address(0),
            nonce: keccak256("nonce_1")
        });

        vm.mockCall(
            revokedRequestNonce,
            abi.encodeWithSignature("isRequestNonceRevoked(address,bytes32)"),
            abi.encode(false)
        );
    }


    function _requestHash(PWNSimpleLoanSimpleRequest.Request memory _request) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            "\x19\x01",
            keccak256(abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("PWNSimpleLoanSimpleRequest"),
                keccak256("1"),
                block.chainid,
                address(requestContract)
            )),
            keccak256(abi.encodePacked(
                keccak256("Request(uint8 collateralCategory,address collateralAddress,uint256 collateralId,uint256 collateralAmount,address loanAssetAddress,uint256 loanAmount,uint256 loanYield,uint32 duration,uint40 expiration,address borrower,address lender,bytes32 nonce)"),
                abi.encode(
                    _request.collateralCategory,
                    _request.collateralAddress,
                    _request.collateralId,
                    _request.collateralAmount
                ), // Need to prevent `slot(s) too deep inside the stack` error
                abi.encode(
                    _request.loanAssetAddress,
                    _request.loanAmount,
                    _request.loanYield,
                    _request.duration,
                    _request.expiration,
                    _request.borrower,
                    _request.lender,
                    _request.nonce
                )
            ))
        ));
    }

}


/*----------------------------------------------------------*|
|*  # MAKE REQUEST                                          *|
|*----------------------------------------------------------*/

// Feature tested in PWNSimpleLoanRequest.t.sol
contract PWNSimpleLoanSimpleRequest_MakeRequest_Test is PWNSimpleLoanSimpleRequestTest {

    function test_shouldMakeRequest() external {
        vm.prank(borrower);
        requestContract.makeRequest(request);

        bytes32 isMadeValue = vm.load(
            address(requestContract),
            keccak256(abi.encode(_requestHash(request), REQUESTS_MADE_SLOT))
        );
        assertEq(isMadeValue, bytes32(uint256(1)));
    }

}


/*----------------------------------------------------------*|
|*  # GET LOAN TERMS                                        *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanSimpleRequest_GetLOANTerms_Test is PWNSimpleLoanSimpleRequestTest {

    bytes signature;
    address lender = address(0x0303030303);

    function setUp() override public {
        super.setUp();

        vm.mockCall(
            address(hub),
            abi.encodeWithSignature("hasTag(address,bytes32)"),
            abi.encode(false)
        );
        vm.mockCall(
            address(hub),
            abi.encodeWithSignature("hasTag(address,bytes32)", activeLoanContract, PWNHubTags.ACTIVE_LOAN),
            abi.encode(true)
        );

        signature = "";
    }

    // Helpers

    function _signRequest(uint256 pk, PWNSimpleLoanSimpleRequest.Request memory _request) private returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _requestHash(_request));
        return abi.encodePacked(r, s, v);
    }

    function _signRequestCompact(uint256 pk, PWNSimpleLoanSimpleRequest.Request memory _request) private returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _requestHash(_request));
        return abi.encodePacked(r, bytes32(uint256(v) - 27) << 255 | s);
    }


    // Tests

    function test_shouldFail_whenCallerIsNotActiveLoan() external {
        vm.expectRevert(abi.encodeWithSelector(CallerMissingHubTag.selector, PWNHubTags.ACTIVE_LOAN));
        requestContract.getLOANTerms(lender, abi.encode(request), signature);
    }

    function test_shouldFail_whenPassingInvalidRequestData() external {
        vm.expectRevert();
        vm.prank(activeLoanContract);
        requestContract.getLOANTerms(lender, abi.encode(uint16(1), uint256(3213), address(0x01320), false, "whaaaaat?"), signature);
    }

    function test_shouldFail_whenInvalidSignature_whenEOA() external {
        signature = _signRequest(1, request);

        vm.expectRevert(abi.encodeWithSelector(InvalidSignature.selector));
        vm.prank(activeLoanContract);
        requestContract.getLOANTerms(lender, abi.encode(request), signature);
    }

    function test_shouldFail_whenInvalidSignature_whenContractAccount() external {
        vm.etch(borrower, bytes("data"));

        vm.expectRevert(abi.encodeWithSelector(InvalidSignature.selector));
        vm.prank(activeLoanContract);
        requestContract.getLOANTerms(lender, abi.encode(request), signature);
    }

    function test_shouldPass_whenRequestHasBeenMadeOnchain() external {
        vm.store(
            address(requestContract),
            keccak256(abi.encode(_requestHash(request), REQUESTS_MADE_SLOT)),
            bytes32(uint256(1))
        );

        vm.prank(activeLoanContract);
        requestContract.getLOANTerms(lender, abi.encode(request), signature);
    }

    function test_shouldPass_withValidSignature_whenEOA_whenStandardSignature() external {
        signature = _signRequest(borrowerPK, request);

        vm.prank(activeLoanContract);
        requestContract.getLOANTerms(lender, abi.encode(request), signature);
    }

    function test_shouldPass_withValidSignature_whenEOA_whenCompactEIP2098Signature() external {
        signature = _signRequestCompact(borrowerPK, request);

        vm.prank(activeLoanContract);
        requestContract.getLOANTerms(lender, abi.encode(request), signature);
    }

    function test_shouldPass_whenValidSignature_whenContractAccount() external {
        vm.etch(borrower, bytes("data"));

        vm.mockCall(
            borrower,
            abi.encodeWithSignature("isValidSignature(bytes32,bytes)"),
            abi.encode(bytes4(0x1626ba7e))
        );

        vm.prank(activeLoanContract);
        requestContract.getLOANTerms(lender, abi.encode(request), signature);
    }

    function test_shouldFail_whenRequestIsExpired() external {
        vm.warp(40303);
        request.expiration = 30303;
        signature = _signRequestCompact(borrowerPK, request);

        vm.expectRevert(abi.encodeWithSelector(RequestExpired.selector));
        vm.prank(activeLoanContract);
        requestContract.getLOANTerms(lender, abi.encode(request), signature);
    }

    function test_shouldPass_whenRequestHasNoExpiration() external {
        vm.warp(40303);
        request.expiration = 0;
        signature = _signRequestCompact(borrowerPK, request);

        vm.prank(activeLoanContract);
        requestContract.getLOANTerms(lender, abi.encode(request), signature);
    }

    function test_shouldPass_whenRequestIsNotExpired() external {
        vm.warp(40303);
        request.expiration = 50303;
        signature = _signRequestCompact(borrowerPK, request);

        vm.prank(activeLoanContract);
        requestContract.getLOANTerms(lender, abi.encode(request), signature);
    }

    function test_shouldFail_whenRequestIsRevoked() external {
        signature = _signRequestCompact(borrowerPK, request);

        vm.mockCall(
            revokedRequestNonce,
            abi.encodeWithSignature("isRequestNonceRevoked(address,bytes32)"),
            abi.encode(true)
        );
        vm.expectCall(
            revokedRequestNonce,
            abi.encodeWithSignature("isRequestNonceRevoked(address,bytes32)", request.borrower, request.nonce)
        );

        vm.expectRevert(abi.encodeWithSelector(NonceRevoked.selector));
        vm.prank(activeLoanContract);
        requestContract.getLOANTerms(lender, abi.encode(request), signature);
    }

    function test_shouldFail_whenCallerIsNotLender_whenSetLender() external {
        request.lender = address(0x50303);
        signature = _signRequestCompact(borrowerPK, request);

        vm.expectRevert(abi.encodeWithSelector(CallerIsNotStatedLender.selector, request.lender));
        vm.prank(activeLoanContract);
        requestContract.getLOANTerms(lender, abi.encode(request), signature);
    }

    function test_shouldRevokeRequest() external {
        signature = _signRequestCompact(borrowerPK, request);

        vm.expectCall(
            revokedRequestNonce,
            abi.encodeWithSignature("revokeRequestNonce(address,bytes32)", request.borrower, request.nonce)
        );

        vm.prank(activeLoanContract);
        requestContract.getLOANTerms(lender, abi.encode(request), signature);
    }

    function test_shouldReturnCorrectValues() external {
        uint256 currentTimestamp = 40303;
        vm.warp(currentTimestamp);
        signature = _signRequestCompact(borrowerPK, request);

        vm.prank(activeLoanContract);
        PWNSimpleLoan.LOANTerms memory loanTerms = requestContract.getLOANTerms(lender, abi.encode(request), signature);

        // LOAN
        assertTrue(loanTerms.lender == lender);
        assertTrue(loanTerms.borrower == request.borrower);
        assertTrue(loanTerms.expiration == currentTimestamp + request.duration);
        assertTrue(loanTerms.collateral.category == request.collateralCategory);
        assertTrue(loanTerms.collateral.assetAddress == request.collateralAddress);
        assertTrue(loanTerms.collateral.id == request.collateralId);
        assertTrue(loanTerms.collateral.amount == request.collateralAmount);
        assertTrue(loanTerms.asset.category == MultiToken.Category.ERC20);
        assertTrue(loanTerms.asset.assetAddress == request.loanAssetAddress);
        assertTrue(loanTerms.asset.id == 0);
        assertTrue(loanTerms.asset.amount == request.loanAmount);
        assertTrue(loanTerms.loanRepayAmount == request.loanAmount + request.loanYield);
    }

}


/*----------------------------------------------------------*|
|*  # GET REQUEST HASH                                      *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanSimpleRequest_GetRequestHash_Test is PWNSimpleLoanSimpleRequestTest {

    function test_shouldReturnRequestHash() external {
        assertEq(_requestHash(request), requestContract.getRequestHash(request));
    }

}


/*----------------------------------------------------------*|
|*  # LOAN FACTORY DATA ENCODING                            *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanSimpleRequest_EncodeLoanFactoryData_Test is PWNSimpleLoanSimpleRequestTest {

    function test_shouldReturnEncodedLoanFactoryDate() external {
        assertEq(abi.encode(request), requestContract.encodeLoanFactoryData(request));
    }

}