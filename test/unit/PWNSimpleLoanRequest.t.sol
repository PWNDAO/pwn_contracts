// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "MultiToken/MultiToken.sol";

import "@pwn/hub/PWNHubTags.sol";
import "@pwn/loan/type/PWNSimpleLoan.sol";
import "@pwn/loan-factory/simple-loan/request/PWNSimpleLoanRequest.sol";
import "@pwn/PWNErrors.sol";


// The only reason for this contract is to expose internal functions of PWNSimpleLoanRequest
// No additional logic is applied here
contract PWNSimpleLoanRequestExposed is PWNSimpleLoanRequest {

    constructor(address hub, address revokedRequestNonce) PWNSimpleLoanRequest(hub, revokedRequestNonce) {

    }

    function makeRequest(bytes32 requestHash, address borrower, bytes32 nonce) external {
        _makeRequest(requestHash, borrower, nonce);
    }

    // Dummy implementation, is not tester here
    function createLOAN(
        address /*caller*/,
        bytes calldata /*loanFactoryData*/,
        bytes calldata /*signature*/
    ) override external pure returns (PWNSimpleLoan.LOANTerms memory) {
        revert("Missing implementation");
    }

}

abstract contract PWNSimpleLoanRequestTest is Test {

    bytes32 internal constant REQUESTS_MADE_SLOT = bytes32(uint256(0)); // `requestsMade` mapping position

    PWNSimpleLoanRequestExposed requestContract;
    address hub = address(0x80b);
    address revokedRequestNonce = address(0x80c);

    bytes32 requestHash = keccak256("request_hash_1");
    address borrower = address(0x070ce3);
    bytes32 nonce = keccak256("nonce_1");

    event RequestMade(bytes32 indexed requestHash, address indexed borrower);

    constructor() {
        vm.etch(hub, bytes("data"));
        vm.etch(revokedRequestNonce, bytes("data"));
    }

    function setUp() virtual public {
        requestContract = new PWNSimpleLoanRequestExposed(hub, revokedRequestNonce);

        vm.mockCall(
            revokedRequestNonce,
            abi.encodeWithSignature("isRequestNonceRevoked(address,bytes32)"),
            abi.encode(false)
        );
    }

}


/*----------------------------------------------------------*|
|*  # MAKE REQUEST                                          *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanRequest_MakeRequest_Test is PWNSimpleLoanRequestTest {

    function test_shouldFail_whenCallerIsNotBorrower() external {
        vm.expectRevert(abi.encodeWithSelector(CallerIsNotStatedBorrower.selector, borrower));
        requestContract.makeRequest(requestHash, borrower, nonce);
    }

    function test_shouldFail_whenRequestHasBeenMadeAlready() external {
        vm.store(
            address(requestContract),
            keccak256(abi.encode(requestHash, REQUESTS_MADE_SLOT)),
            bytes32(uint256(1))
        );

        vm.expectRevert(abi.encodeWithSelector(RequestAlreadyExists.selector));
        vm.prank(borrower);
        requestContract.makeRequest(requestHash, borrower, nonce);
    }

    function test_shouldFail_whenRequestIsRevoked() external {
        vm.mockCall(
            revokedRequestNonce,
            abi.encodeWithSignature("isRequestNonceRevoked(address,bytes32)", borrower, nonce),
            abi.encode(true)
        );

        vm.expectCall(
            revokedRequestNonce,
            abi.encodeWithSignature("isRequestNonceRevoked(address,bytes32)", borrower, nonce)
        );

        vm.expectRevert(abi.encodeWithSelector(NonceRevoked.selector));
        vm.prank(borrower);
        requestContract.makeRequest(requestHash, borrower, nonce);
    }

    function test_shouldMarkRequestAsMade() external {
        vm.prank(borrower);
        requestContract.makeRequest(requestHash, borrower, nonce);

        bytes32 isMadeValue = vm.load(
            address(requestContract),
            keccak256(abi.encode(requestHash, REQUESTS_MADE_SLOT))
        );
        assertEq(isMadeValue, bytes32(uint256(1)));
    }

    function test_shouldEmitEvent_RequestMade() external {
        vm.expectEmit(true, true, false, false);
        emit RequestMade(requestHash, borrower);

        vm.prank(borrower);
        requestContract.makeRequest(requestHash, borrower, nonce);
    }

}


/*----------------------------------------------------------*|
|*  # REVOKE REQUEST NONCE                                  *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanRequest_RevokeRequestNonce_Test is PWNSimpleLoanRequestTest {

    function test_shouldCallRevokeRequestNonce() external {
        bytes32 nonce = keccak256("its my monkey");

        vm.expectCall(
            revokedRequestNonce,
            abi.encodeWithSignature("revokeRequestNonce(address,bytes32)", borrower, nonce)
        );

        vm.prank(borrower);
        requestContract.revokeRequestNonce(nonce);
    }

}
