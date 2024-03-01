// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "MultiToken/MultiToken.sol";

import "@pwn/hub/PWNHubTags.sol";
import "@pwn/loan/terms/simple/factory/request/base/PWNSimpleLoanRequest.sol";
import "@pwn/loan/terms/PWNLOANTerms.sol";
import "@pwn/PWNErrors.sol";


// The only reason for this contract is to expose internal functions of PWNSimpleLoanRequest
// No additional logic is applied here
contract PWNSimpleLoanRequestExposed is PWNSimpleLoanRequest {

    constructor(address hub, address revokedRequestNonce) PWNSimpleLoanRequest(hub, revokedRequestNonce) {

    }

    function makeRequest(bytes32 requestHash, address borrower) external {
        _makeRequest(requestHash, borrower);
    }

    // Dummy implementation, is not tester here
    function createLOANTerms(
        address /*caller*/,
        bytes calldata /*factoryData*/,
        bytes calldata /*signature*/
    ) override external pure returns (PWNLOANTerms.Simple memory, bytes32) {
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
    uint256 nonce = uint256(keccak256("nonce_1"));

    function setUp() virtual public {
        vm.etch(hub, bytes("data"));
        vm.etch(revokedRequestNonce, bytes("data"));

        requestContract = new PWNSimpleLoanRequestExposed(hub, revokedRequestNonce);

        vm.mockCall(
            revokedRequestNonce,
            abi.encodeWithSignature("isNonceRevoked(address,uint256,uint256)"),
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
        requestContract.makeRequest(requestHash, borrower);
    }

    function test_shouldMarkRequestAsMade() external {
        vm.prank(borrower);
        requestContract.makeRequest(requestHash, borrower);

        bytes32 isMadeValue = vm.load(
            address(requestContract),
            keccak256(abi.encode(requestHash, REQUESTS_MADE_SLOT))
        );
        assertEq(uint256(isMadeValue), 1);
    }

}


/*----------------------------------------------------------*|
|*  # REVOKE REQUEST NONCE                                  *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanRequest_RevokeRequestNonce_Test is PWNSimpleLoanRequestTest {

    function testFuzz_shouldCallRevokeRequestNonce(uint256 nonceSpace, uint256 nonce) external {
        vm.expectCall(
            revokedRequestNonce,
            abi.encodeWithSignature("revokeNonce(address,uint256,uint256)", borrower, nonceSpace, nonce)
        );

        vm.prank(borrower);
        requestContract.revokeRequestNonce(nonceSpace, nonce);
    }

}
