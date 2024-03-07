// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "MultiToken/MultiToken.sol";

import "@pwn/hub/PWNHubTags.sol";
import "@pwn/loan/terms/simple/factory/request/PWNSimpleLoanSimpleRequest.sol";
import "@pwn/loan/terms/PWNLOANTerms.sol";
import "@pwn/PWNErrors.sol";


abstract contract PWNSimpleLoanSimpleRequestTest is Test {

    bytes32 internal constant REQUESTS_MADE_SLOT = bytes32(uint256(0)); // `requestsMade` mapping position
    bytes32 internal constant CREDIT_USED_SLOT = bytes32(uint256(1)); // `_creditUsed` mapping position

    PWNSimpleLoanSimpleRequest requestContract;
    address hub = address(0x80b);
    address revokedRequestNonce = address(0x80c);
    address stateFingerprintComputerRegistry = makeAddr("stateFingerprintComputerRegistry");
    address activeLoanContract = address(0x80d);
    PWNSimpleLoanSimpleRequest.Request request;
    address token = address(0x070ce2);
    uint256 borrowerPK = uint256(73661723);
    address borrower = vm.addr(borrowerPK);

    event RequestMade(bytes32 indexed requestHash, address indexed borrower, PWNSimpleLoanSimpleRequest.Request request);

    function setUp() virtual public {
        vm.etch(hub, bytes("data"));
        vm.etch(revokedRequestNonce, bytes("data"));
        vm.etch(token, bytes("data"));

        requestContract = new PWNSimpleLoanSimpleRequest(hub, revokedRequestNonce, stateFingerprintComputerRegistry);

        request = PWNSimpleLoanSimpleRequest.Request({
            collateralCategory: MultiToken.Category.ERC721,
            collateralAddress: token,
            collateralId: 42,
            collateralAmount: 1032,
            checkCollateralStateFingerprint: true,
            collateralStateFingerprint: keccak256("some state fingerprint"),
            loanAssetAddress: token,
            loanAmount: 1101001,
            availableCreditLimit: 0,
            fixedInterestAmount: 1,
            accruingInterestAPR: 0,
            duration: 1000,
            expiration: 60303,
            allowedLender: address(0),
            borrower: borrower,
            refinancingLoanId: 0,
            nonceSpace: 1,
            nonce: uint256(keccak256("nonce_1"))
        });

        vm.mockCall(
            revokedRequestNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)"),
            abi.encode(true)
        );
    }


    function _requestHash(PWNSimpleLoanSimpleRequest.Request memory _request) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            "\x19\x01",
            keccak256(abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("PWNSimpleLoanSimpleRequest"),
                keccak256("1.2"),
                block.chainid,
                address(requestContract)
            )),
            keccak256(abi.encodePacked(
                keccak256("Request(uint8 collateralCategory,address collateralAddress,uint256 collateralId,uint256 collateralAmount,bool checkCollateralStateFingerprint,bytes32 collateralStateFingerprint,address loanAssetAddress,uint256 loanAmount,uint256 availableCreditLimit,uint256 fixedInterestAmount,uint40 accruingInterestAPR,uint32 duration,uint40 expiration,address allowedLender,address borrower,uint256 refinancingLoanId,uint256 nonceSpace,uint256 nonce)"),
                abi.encode(_request)
            ))
        ));
    }

}


/*----------------------------------------------------------*|
|*  # MAKE REQUEST                                          *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanSimpleRequest_MakeRequest_Test is PWNSimpleLoanSimpleRequestTest {

    function testFuzz_shouldFail_whenCallerIsNotBorrower(address caller) external {
        vm.assume(caller != request.borrower);

        vm.expectRevert(abi.encodeWithSelector(CallerIsNotStatedBorrower.selector, borrower));
        vm.prank(caller);
        requestContract.makeRequest(request);
    }

    function test_shouldEmit_RequestMade() external {
        vm.expectEmit();
        emit RequestMade(_requestHash(request), request.borrower, request);

        vm.prank(request.borrower);
        requestContract.makeRequest(request);
    }

    function test_shouldMakeRequest() external {
        vm.prank(request.borrower);
        requestContract.makeRequest(request);

        assertTrue(requestContract.requestsMade(_requestHash(request)));
    }

}


/*----------------------------------------------------------*|
|*  # AVAILABLE CREDIT                                      *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanSimpleRequest_AvailableCredit_Test is PWNSimpleLoanSimpleRequestTest {

    function testFuzz_shouldReturnAvailableCredit(uint256 used, uint256 limit) external {
        limit = bound(limit, used, type(uint256).max);
        request.availableCreditLimit = limit;

        vm.store(address(requestContract), keccak256(abi.encode(_requestHash(request), CREDIT_USED_SLOT)), bytes32(used));

        assertEq(requestContract.availableCredit(request), limit - used);
    }

}


/*----------------------------------------------------------*|
|*  # CREDIT USED                                           *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanSimpleRequest_CreditUsed_Test is PWNSimpleLoanSimpleRequestTest {

    function testFuzz_shouldReturnUsedCredit(uint256 used) external {
        vm.store(address(requestContract), keccak256(abi.encode(_requestHash(request), CREDIT_USED_SLOT)), bytes32(used));

        assertEq(requestContract.creditUsed(request), used);
    }

}


/*----------------------------------------------------------*|
|*  # REVOKE REQUEST NONCE                                  *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanSimpleRequest_RevokeRequestNonce_Test is PWNSimpleLoanSimpleRequestTest {

    function testFuzz_shouldCallRevokeRequestNonce(uint256 nonceSpace, uint256 nonce) external {
        vm.expectCall(
            revokedRequestNonce,
            abi.encodeWithSignature("revokeNonce(address,uint256,uint256)", borrower, nonceSpace, nonce)
        );

        vm.prank(borrower);
        requestContract.revokeRequestNonce(nonceSpace, nonce);
    }

}


/*----------------------------------------------------------*|
|*  # CREATE LOAN TERMS                                     *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanSimpleRequest_CreateLOANTerms_Test is PWNSimpleLoanSimpleRequestTest {

    bytes signature;
    address lender = makeAddr("lender");
    address stateFingerprintComputer = makeAddr("stateFingerprintComputer");

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

        vm.mockCall(
            stateFingerprintComputerRegistry,
            abi.encodeWithSignature("getStateFingerprintComputer(address)", request.collateralAddress),
            abi.encode(stateFingerprintComputer)
        );
        vm.mockCall(
            stateFingerprintComputer,
            abi.encodeWithSignature("getStateFingerprint(uint256)", request.collateralId),
            abi.encode(request.collateralStateFingerprint)
        );
    }

    // Helpers

    function _signRequest(uint256 pk, PWNSimpleLoanSimpleRequest.Request memory _request) private view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _requestHash(_request));
        return abi.encodePacked(r, s, v);
    }

    function _signRequestCompact(uint256 pk, PWNSimpleLoanSimpleRequest.Request memory _request) private view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _requestHash(_request));
        return abi.encodePacked(r, bytes32(uint256(v) - 27) << 255 | s);
    }


    // Tests

    function test_shouldFail_whenCallerIsNotActiveLoan() external {
        vm.expectRevert(abi.encodeWithSelector(CallerMissingHubTag.selector, PWNHubTags.ACTIVE_LOAN));
        requestContract.createLOANTerms(lender, abi.encode(request), signature);
    }

    function test_shouldFail_whenPassingInvalidRequestData() external {
        vm.expectRevert();
        vm.prank(activeLoanContract);
        requestContract.createLOANTerms(lender, abi.encode(uint16(1), uint256(3213), address(0x01320), false, "whaaaaat?"), signature);
    }

    function test_shouldFail_whenInvalidSignature_whenEOA() external {
        signature = _signRequest(1, request);

        vm.expectRevert(abi.encodeWithSelector(InvalidSignature.selector));
        vm.prank(activeLoanContract);
        requestContract.createLOANTerms(lender, abi.encode(request), signature);
    }

    function test_shouldFail_whenInvalidSignature_whenContractAccount() external {
        vm.etch(borrower, bytes("data"));

        vm.expectRevert(abi.encodeWithSelector(InvalidSignature.selector));
        vm.prank(activeLoanContract);
        requestContract.createLOANTerms(lender, abi.encode(request), signature);
    }

    function test_shouldPass_whenRequestHasBeenMadeOnchain() external {
        vm.store(
            address(requestContract),
            keccak256(abi.encode(_requestHash(request), REQUESTS_MADE_SLOT)),
            bytes32(uint256(1))
        );

        vm.prank(activeLoanContract);
        requestContract.createLOANTerms(lender, abi.encode(request), signature);
    }

    function test_shouldPass_withValidSignature_whenEOA_whenStandardSignature() external {
        signature = _signRequest(borrowerPK, request);

        vm.prank(activeLoanContract);
        requestContract.createLOANTerms(lender, abi.encode(request), signature);
    }

    function test_shouldPass_withValidSignature_whenEOA_whenCompactEIP2098Signature() external {
        signature = _signRequestCompact(borrowerPK, request);

        vm.prank(activeLoanContract);
        requestContract.createLOANTerms(lender, abi.encode(request), signature);
    }

    function test_shouldPass_whenValidSignature_whenContractAccount() external {
        vm.etch(borrower, bytes("data"));

        vm.mockCall(
            borrower,
            abi.encodeWithSignature("isValidSignature(bytes32,bytes)"),
            abi.encode(bytes4(0x1626ba7e))
        );

        vm.prank(activeLoanContract);
        requestContract.createLOANTerms(lender, abi.encode(request), signature);
    }

    function test_shouldFail_whenRequestIsExpired() external {
        vm.warp(40303);
        request.expiration = 30303;
        signature = _signRequestCompact(borrowerPK, request);

        vm.expectRevert(abi.encodeWithSelector(RequestExpired.selector));
        vm.prank(activeLoanContract);
        requestContract.createLOANTerms(lender, abi.encode(request), signature);
    }

    function test_shouldPass_whenRequestIsNotExpired() external {
        vm.warp(40303);
        request.expiration = 50303;
        signature = _signRequestCompact(borrowerPK, request);

        vm.prank(activeLoanContract);
        requestContract.createLOANTerms(lender, abi.encode(request), signature);
    }

    function test_shouldFail_whenRequestNonceNotUsable() external {
        signature = _signRequestCompact(borrowerPK, request);

        vm.mockCall(
            revokedRequestNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)"),
            abi.encode(false)
        );
        vm.expectCall(
            revokedRequestNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)", request.borrower, request.nonceSpace, request.nonce)
        );

        vm.expectRevert(abi.encodeWithSelector(NonceNotUsable.selector));
        vm.prank(activeLoanContract);
        requestContract.createLOANTerms(lender, abi.encode(request), signature);
    }

    function test_shouldFail_whenCallerIsNotAllowedLender() external {
        request.allowedLender = address(0x50303);
        signature = _signRequestCompact(borrowerPK, request);

        vm.expectRevert(abi.encodeWithSelector(CallerIsNotStatedLender.selector, request.allowedLender));
        vm.prank(activeLoanContract);
        requestContract.createLOANTerms(lender, abi.encode(request), signature);
    }

    function testFuzz_shouldFail_whenLessThanMinDuration(uint32 duration) external {
        vm.assume(duration < requestContract.MIN_LOAN_DURATION());

        request.duration = duration;
        signature = _signRequestCompact(borrowerPK, request);

        vm.expectRevert(abi.encodeWithSelector(InvalidDuration.selector));
        vm.prank(activeLoanContract);
        requestContract.createLOANTerms(lender, abi.encode(request), signature);
    }

    function testFuzz_shouldFail_whenAccruingInterestAPROutOfBounds(uint40 interestAPR) external {
        uint40 maxInterest = requestContract.MAX_ACCRUING_INTEREST_APR();
        interestAPR = uint40(bound(interestAPR, maxInterest + 1, type(uint40).max));

        request.accruingInterestAPR = interestAPR;
        signature = _signRequestCompact(borrowerPK, request);

        vm.expectRevert(abi.encodeWithSelector(AccruingInterestAPROutOfBounds.selector, interestAPR, maxInterest));
        vm.prank(activeLoanContract);
        requestContract.createLOANTerms(lender, abi.encode(request), signature);
    }

    function test_shouldNotCallComputerRegistry_whenShouldNotCheckStateFingerprint() external {
        request.checkCollateralStateFingerprint = false;
        signature = _signRequestCompact(borrowerPK, request);

        vm.expectCall({
            callee: stateFingerprintComputerRegistry,
            data: abi.encodeWithSignature("getStateFingerprintComputer(address)", request.collateralAddress),
            count: 0
        });

        vm.prank(activeLoanContract);
        requestContract.createLOANTerms(lender, abi.encode(request), signature);
    }

    function test_shouldFail_whenComputerRegistryReturnsZeroAddress_whenShouldCheckStateFingerprint() external {
        signature = _signRequestCompact(borrowerPK, request);

        vm.mockCall(
            stateFingerprintComputerRegistry,
            abi.encodeWithSignature("getStateFingerprintComputer(address)", request.collateralAddress),
            abi.encode(address(0))
        );

        vm.expectCall(
            stateFingerprintComputerRegistry,
            abi.encodeWithSignature("getStateFingerprintComputer(address)", request.collateralAddress)
        );

        vm.expectRevert(abi.encodeWithSelector(MissingStateFingerprintComputer.selector));
        vm.prank(activeLoanContract);
        requestContract.createLOANTerms(lender, abi.encode(request), signature);
    }

    function testFuzz_shouldFail_whenComputerReturnsDifferentStateFingerprint_whenShouldCheckStateFingerprint(
        bytes32 stateFingerprint
    ) external {
        vm.assume(stateFingerprint != request.collateralStateFingerprint);

        signature = _signRequestCompact(borrowerPK, request);

        vm.mockCall(
            stateFingerprintComputer,
            abi.encodeWithSignature("getStateFingerprint(uint256)", request.collateralId),
            abi.encode(stateFingerprint)
        );

        vm.expectCall(
            stateFingerprintComputer,
            abi.encodeWithSignature("getStateFingerprint(uint256)", request.collateralId)
        );

        vm.expectRevert(abi.encodeWithSelector(
            InvalidCollateralStateFingerprint.selector, request.collateralStateFingerprint, stateFingerprint
        ));
        vm.prank(activeLoanContract);
        requestContract.createLOANTerms(lender, abi.encode(request), signature);
    }

    function test_shouldRevokeRequest_whenAvailableCreditLimitEqualToZero() external {
        request.availableCreditLimit = 0;
        signature = _signRequestCompact(borrowerPK, request);

        vm.expectCall(
            revokedRequestNonce,
            abi.encodeWithSignature("revokeNonce(address,uint256,uint256)", request.borrower, request.nonceSpace, request.nonce)
        );

        vm.prank(activeLoanContract);
        requestContract.createLOANTerms(lender, abi.encode(request), signature);
    }

    function testFuzz_shouldFail_whenUsedCreditExceedsAvailableCreditLimit(uint256 used, uint256 limit) external {
        used = bound(used, 1, type(uint256).max - request.loanAmount);
        limit = bound(limit, used, used + request.loanAmount - 1);
        request.availableCreditLimit = limit;
        signature = _signRequestCompact(borrowerPK, request);

        vm.store(address(requestContract), keccak256(abi.encode(_requestHash(request), CREDIT_USED_SLOT)), bytes32(used));

        vm.expectRevert(abi.encodeWithSelector(AvailableCreditLimitExceeded.selector, used + request.loanAmount, limit));
        vm.prank(activeLoanContract);
        requestContract.createLOANTerms(lender, abi.encode(request), signature);
    }

    function testFuzz_shouldIncreaseUsedCredit_whenUsedCreditNotExceedsAvailableCreditLimit(uint256 used, uint256 limit) external {
        used = bound(used, 1, type(uint256).max - request.loanAmount);
        limit = bound(limit, used + request.loanAmount, type(uint256).max);
        request.availableCreditLimit = limit;
        signature = _signRequestCompact(borrowerPK, request);

        vm.store(address(requestContract), keccak256(abi.encode(_requestHash(request), CREDIT_USED_SLOT)), bytes32(used));

        vm.prank(activeLoanContract);
        requestContract.createLOANTerms(lender, abi.encode(request), signature);

        assertEq(requestContract.creditUsed(request), used + request.loanAmount);
    }

    function testFuzz_shouldReturnCorrectValues(uint256 _refinancingLoanId) external {
        request.refinancingLoanId = _refinancingLoanId;

        uint256 currentTimestamp = 40303;
        vm.warp(currentTimestamp);
        signature = _signRequestCompact(borrowerPK, request);

        vm.prank(activeLoanContract);
        (PWNLOANTerms.Simple memory loanTerms, bytes32 requestHash)
            = requestContract.createLOANTerms(lender, abi.encode(request), signature);

        assertTrue(loanTerms.lender == lender);
        assertTrue(loanTerms.borrower == request.borrower);
        assertTrue(loanTerms.defaultTimestamp == currentTimestamp + request.duration);
        assertTrue(loanTerms.collateral.category == request.collateralCategory);
        assertTrue(loanTerms.collateral.assetAddress == request.collateralAddress);
        assertTrue(loanTerms.collateral.id == request.collateralId);
        assertTrue(loanTerms.collateral.amount == request.collateralAmount);
        assertTrue(loanTerms.asset.category == MultiToken.Category.ERC20);
        assertTrue(loanTerms.asset.assetAddress == request.loanAssetAddress);
        assertTrue(loanTerms.asset.id == 0);
        assertTrue(loanTerms.asset.amount == request.loanAmount);
        assertTrue(loanTerms.fixedInterestAmount == request.fixedInterestAmount);
        assertTrue(loanTerms.accruingInterestAPR == request.accruingInterestAPR);
        assertTrue(loanTerms.canCreate == (request.refinancingLoanId == 0));
        assertTrue(loanTerms.canRefinance == (request.refinancingLoanId != 0));
        assertTrue(loanTerms.refinancingLoanId == request.refinancingLoanId);

        assertTrue(requestHash == _requestHash(request));
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
|*  # LOAN TERMS FACTORY DATA ENCODING                      *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanSimpleRequest_EncodeLoanTermsFactoryData_Test is PWNSimpleLoanSimpleRequestTest {

    function test_shouldReturnEncodedLoanTermsFactoryData() external {
        assertEq(abi.encode(request), requestContract.encodeLoanTermsFactoryData(request));
    }

}