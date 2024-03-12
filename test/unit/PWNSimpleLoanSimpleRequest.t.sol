// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import { MultiToken } from "MultiToken/MultiToken.sol";

import { PWNHubTags } from "@pwn/hub/PWNHubTags.sol";
import { PWNSimpleLoanSimpleRequest, PWNSimpleLoan }
    from "@pwn/loan/terms/simple/proposal/request/PWNSimpleLoanSimpleRequest.sol";
import "@pwn/PWNErrors.sol";


abstract contract PWNSimpleLoanSimpleRequestTest is Test {

    bytes32 internal constant PROPOSALS_MADE_SLOT = bytes32(uint256(0)); // `proposalsMade` mapping position
    bytes32 internal constant CREDIT_USED_SLOT = bytes32(uint256(1)); // `creditUsed` mapping position

    PWNSimpleLoanSimpleRequest requestContract;
    address hub = makeAddr("hub");
    address revokedNonce = makeAddr("revokedNonce");
    address stateFingerprintComputerRegistry = makeAddr("stateFingerprintComputerRegistry");
    address activeLoanContract = makeAddr("activeLoanContract");
    PWNSimpleLoanSimpleRequest.Request request;
    address token = makeAddr("token");
    uint256 borrowerPK = 73661723;
    address borrower = vm.addr(borrowerPK);
    address lender = makeAddr("lender");
    address stateFingerprintComputer = makeAddr("stateFingerprintComputer");
    uint256 loanId = 421;
    uint256 refinancedLoanId = 123;

    event ProposalMade(bytes32 indexed proposalHash, address indexed proposer, bytes proposal);

    function setUp() virtual public {
        vm.etch(hub, bytes("data"));
        vm.etch(revokedNonce, bytes("data"));
        vm.etch(token, bytes("data"));

        requestContract = new PWNSimpleLoanSimpleRequest(hub, revokedNonce, stateFingerprintComputerRegistry);

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
            nonce: uint256(keccak256("nonce_1")),
            loanContract: activeLoanContract
        });

        vm.mockCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)"),
            abi.encode(true)
        );

        vm.mockCall(address(hub), abi.encodeWithSignature("hasTag(address,bytes32)"), abi.encode(false));
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

        vm.mockCall(
            activeLoanContract, abi.encodeWithSelector(PWNSimpleLoan.createLOAN.selector), abi.encode(loanId)
        );
        vm.mockCall(
            activeLoanContract, abi.encodeWithSelector(PWNSimpleLoan.refinanceLOAN.selector), abi.encode(refinancedLoanId)
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
                keccak256("Request(uint8 collateralCategory,address collateralAddress,uint256 collateralId,uint256 collateralAmount,bool checkCollateralStateFingerprint,bytes32 collateralStateFingerprint,address loanAssetAddress,uint256 loanAmount,uint256 availableCreditLimit,uint256 fixedInterestAmount,uint40 accruingInterestAPR,uint32 duration,uint40 expiration,address allowedLender,address borrower,uint256 refinancingLoanId,uint256 nonceSpace,uint256 nonce,address loanContract)"),
                abi.encode(_request)
            ))
        ));
    }

    function _signRequest(
        uint256 pk, PWNSimpleLoanSimpleRequest.Request memory _request
    ) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _requestHash(_request));
        return abi.encodePacked(r, s, v);
    }

    function _signRequestCompact(
        uint256 pk, PWNSimpleLoanSimpleRequest.Request memory _request
    ) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _requestHash(_request));
        return abi.encodePacked(r, bytes32(uint256(v) - 27) << 255 | s);
    }

}


/*----------------------------------------------------------*|
|*  # CREDIT USED                                           *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanSimpleRequest_CreditUsed_Test is PWNSimpleLoanSimpleRequestTest {

    function testFuzz_shouldReturnUsedCredit(uint256 used) external {
        vm.store(address(requestContract), keccak256(abi.encode(_requestHash(request), CREDIT_USED_SLOT)), bytes32(used));

        assertEq(requestContract.creditUsed(_requestHash(request)), used);
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
|*  # MAKE REQUEST                                          *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanSimpleRequest_MakeRequest_Test is PWNSimpleLoanSimpleRequestTest {

    function testFuzz_shouldFail_whenCallerIsNotBorrower(address caller) external {
        vm.assume(caller != request.borrower);

        vm.expectRevert(abi.encodeWithSelector(CallerIsNotStatedProposer.selector, borrower));
        vm.prank(caller);
        requestContract.makeRequest(request);
    }

    function test_shouldEmit_RequestMade() external {
        vm.expectEmit();
        emit ProposalMade(_requestHash(request), request.borrower, abi.encode(request));

        vm.prank(request.borrower);
        requestContract.makeRequest(request);
    }

    function test_shouldMakeRequest() external {
        vm.prank(request.borrower);
        requestContract.makeRequest(request);

        assertTrue(requestContract.proposalsMade(_requestHash(request)));
    }

}


/*----------------------------------------------------------*|
|*  # REVOKE NONCE                                          *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanSimpleRequest_RevokeNonce_Test is PWNSimpleLoanSimpleRequestTest {

    function testFuzz_shouldCallRevokeNonce(address caller, uint256 nonceSpace, uint256 nonce) external {
        vm.expectCall(
            revokedNonce,
            abi.encodeWithSignature("revokeNonce(address,uint256,uint256)", caller, nonceSpace, nonce)
        );

        vm.prank(caller);
        requestContract.revokeNonce(nonceSpace, nonce);
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT REQUEST                                        *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanSimpleRequest_AcceptRequest_Test is PWNSimpleLoanSimpleRequestTest {

    function testFuzz_shouldFail_whenRefinancingLoanIdNotZero(uint256 refinancingLoanId) external {
        vm.assume(refinancingLoanId != 0);
        request.refinancingLoanId = refinancingLoanId;

        vm.expectRevert(abi.encodeWithSelector(InvalidRefinancingLoanId.selector, refinancingLoanId));
        requestContract.acceptRequest(request, _signRequest(borrowerPK, request), "", "");
    }

    function testFuzz_shouldFail_whenLoanContractNotTagged_ACTIVE_LOAN(address loanContract) external {
        vm.assume(loanContract != activeLoanContract);
        request.loanContract = loanContract;

        vm.expectRevert(abi.encodeWithSelector(AddressMissingHubTag.selector, loanContract, PWNHubTags.ACTIVE_LOAN));
        requestContract.acceptRequest(request, _signRequest(borrowerPK, request), "", "");
    }

    function test_shouldNotCallComputerRegistry_whenShouldNotCheckStateFingerprint() external {
        request.checkCollateralStateFingerprint = false;

        vm.expectCall({
            callee: stateFingerprintComputerRegistry,
            data: abi.encodeWithSignature("getStateFingerprintComputer(address)", request.collateralAddress),
            count: 0
        });

        requestContract.acceptRequest(request, _signRequest(borrowerPK, request), "", "");
    }

    function test_shouldFail_whenComputerRegistryReturnsZeroAddress_whenShouldCheckStateFingerprint() external {
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
        requestContract.acceptRequest(request, _signRequest(borrowerPK, request), "", "");
    }

    function testFuzz_shouldFail_whenComputerReturnsDifferentStateFingerprint_whenShouldCheckStateFingerprint(
        bytes32 stateFingerprint
    ) external {
        vm.assume(stateFingerprint != request.collateralStateFingerprint);

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
            InvalidCollateralStateFingerprint.selector, stateFingerprint, request.collateralStateFingerprint
        ));
        requestContract.acceptRequest(request, _signRequest(borrowerPK, request), "", "");
    }

    function test_shouldFail_whenInvalidSignature_whenEOA() external {
        vm.expectRevert(abi.encodeWithSelector(InvalidSignature.selector, request.borrower, _requestHash(request)));
        requestContract.acceptRequest(request, _signRequest(1, request), "", "");
    }

    function test_shouldFail_whenInvalidSignature_whenContractAccount() external {
        vm.etch(borrower, bytes("data"));

        vm.expectRevert(abi.encodeWithSelector(InvalidSignature.selector, request.borrower, _requestHash(request)));
        requestContract.acceptRequest(request, "", "", "");
    }

    function test_shouldPass_whenRequestHasBeenMadeOnchain() external {
        vm.store(
            address(requestContract),
            keccak256(abi.encode(_requestHash(request), PROPOSALS_MADE_SLOT)),
            bytes32(uint256(1))
        );

        requestContract.acceptRequest(request, "", "", "");
    }

    function test_shouldPass_withValidSignature_whenEOA_whenStandardSignature() external {
        requestContract.acceptRequest(request, _signRequest(borrowerPK, request), "", "");
    }

    function test_shouldPass_withValidSignature_whenEOA_whenCompactEIP2098Signature() external {
        requestContract.acceptRequest(request, _signRequestCompact(borrowerPK, request), "", "");
    }

    function test_shouldPass_whenValidSignature_whenContractAccount() external {
        vm.etch(borrower, bytes("data"));

        vm.mockCall(
            borrower,
            abi.encodeWithSignature("isValidSignature(bytes32,bytes)"),
            abi.encode(bytes4(0x1626ba7e))
        );

        requestContract.acceptRequest(request, "", "", "");
    }

    function testFuzz_shouldFail_whenRequestIsExpired(uint256 timestamp) external {
        timestamp = bound(timestamp, request.expiration, type(uint256).max);
        vm.warp(timestamp);

        vm.expectRevert(abi.encodeWithSelector(Expired.selector, timestamp, request.expiration));
        requestContract.acceptRequest(request, _signRequest(borrowerPK, request), "", "");
    }

    function test_shouldFail_whenRequestNonceNotUsable() external {
        vm.mockCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)"),
            abi.encode(false)
        );
        vm.expectCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)", request.borrower, request.nonceSpace, request.nonce)
        );

        vm.expectRevert(abi.encodeWithSelector(
            NonceNotUsable.selector, request.borrower, request.nonceSpace, request.nonce
        ));
        requestContract.acceptRequest(request, _signRequest(borrowerPK, request), "", "");
    }

    function testFuzz_shouldFail_whenCallerIsNotAllowedLender(address caller) external {
        address allowedLender = makeAddr("allowedLender");
        vm.assume(caller != allowedLender);
        request.allowedLender = allowedLender;

        vm.expectRevert(abi.encodeWithSelector(CallerNotAllowedAcceptor.selector, caller, request.allowedLender));
        vm.prank(caller);
        requestContract.acceptRequest(request, _signRequest(borrowerPK, request), "", "");
    }

    function testFuzz_shouldFail_whenLessThanMinDuration(uint256 duration) external {
        vm.assume(duration < requestContract.MIN_LOAN_DURATION());
        duration = bound(duration, 0, requestContract.MIN_LOAN_DURATION() - 1);
        request.duration = uint32(duration);

        vm.expectRevert(abi.encodeWithSelector(InvalidDuration.selector, duration, requestContract.MIN_LOAN_DURATION()));
        requestContract.acceptRequest(request, _signRequest(borrowerPK, request), "", "");
    }

    function testFuzz_shouldFail_whenAccruingInterestAPROutOfBounds(uint256 interestAPR) external {
        uint256 maxInterest = requestContract.MAX_ACCRUING_INTEREST_APR();
        interestAPR = bound(interestAPR, maxInterest + 1, type(uint40).max);
        request.accruingInterestAPR = uint40(interestAPR);

        vm.expectRevert(abi.encodeWithSelector(AccruingInterestAPROutOfBounds.selector, interestAPR, maxInterest));
        requestContract.acceptRequest(request, _signRequest(borrowerPK, request), "", "");
    }

    function test_shouldRevokeRequest_whenAvailableCreditLimitEqualToZero() external {
        request.availableCreditLimit = 0;

        vm.expectCall(
            revokedNonce,
            abi.encodeWithSignature(
                "revokeNonce(address,uint256,uint256)", request.borrower, request.nonceSpace, request.nonce
            )
        );

        requestContract.acceptRequest(request, _signRequest(borrowerPK, request), "", "");
    }

    function testFuzz_shouldFail_whenUsedCreditExceedsAvailableCreditLimit(uint256 used, uint256 limit) external {
        used = bound(used, 1, type(uint256).max - request.loanAmount);
        limit = bound(limit, used, used + request.loanAmount - 1);
        request.availableCreditLimit = limit;

        vm.store(address(requestContract), keccak256(abi.encode(_requestHash(request), CREDIT_USED_SLOT)), bytes32(used));

        vm.expectRevert(abi.encodeWithSelector(AvailableCreditLimitExceeded.selector, used + request.loanAmount, limit));
        requestContract.acceptRequest(request, _signRequest(borrowerPK, request), "", "");
    }

    function testFuzz_shouldIncreaseUsedCredit_whenUsedCreditNotExceedsAvailableCreditLimit(uint256 used, uint256 limit) external {
        used = bound(used, 1, type(uint256).max - request.loanAmount);
        limit = bound(limit, used + request.loanAmount, type(uint256).max);
        request.availableCreditLimit = limit;

        vm.store(address(requestContract), keccak256(abi.encode(_requestHash(request), CREDIT_USED_SLOT)), bytes32(used));

        requestContract.acceptRequest(request, _signRequest(borrowerPK, request), "", "");

        assertEq(requestContract.creditUsed(_requestHash(request)), used + request.loanAmount);
    }

    function test_shouldCallLoanContractWithLoanTerms() external {
        bytes memory loanAssetPermit = "loanAssetPermit";
        bytes memory collateralPermit = "collateralPermit";

        PWNSimpleLoan.Terms memory loanTerms = PWNSimpleLoan.Terms({
            lender: lender,
            borrower: request.borrower,
            duration: request.duration,
            collateral: MultiToken.Asset({
                category: request.collateralCategory,
                assetAddress: request.collateralAddress,
                id: request.collateralId,
                amount: request.collateralAmount
            }),
            asset: MultiToken.Asset({
                category: MultiToken.Category.ERC20,
                assetAddress: request.loanAssetAddress,
                id: 0,
                amount: request.loanAmount
            }),
            fixedInterestAmount: request.fixedInterestAmount,
            accruingInterestAPR: request.accruingInterestAPR
        });

        vm.expectCall(
            activeLoanContract,
            abi.encodeWithSelector(
                PWNSimpleLoan.createLOAN.selector,
                _requestHash(request), loanTerms, loanAssetPermit, collateralPermit
            )
        );

        vm.prank(lender);
        requestContract.acceptRequest(request, _signRequest(borrowerPK, request), loanAssetPermit, collateralPermit);
    }

    function test_shouldReturnNewLoanId() external {
        assertEq(
            requestContract.acceptRequest(request, _signRequest(borrowerPK, request), "", ""),
            loanId
        );
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT REQUEST AND REVOKE CALLERS NONCE               *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanSimpleRequest_AcceptRequestAndRevokeCallersNonce_Test is PWNSimpleLoanSimpleRequestTest {

    function testFuzz_shouldFail_whenNonceIsNotUsable(address caller, uint256 nonceSpace, uint256 nonce) external {
        vm.mockCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)", caller, nonceSpace, nonce),
            abi.encode(false)
        );

        vm.expectRevert(abi.encodeWithSelector(NonceNotUsable.selector, caller, nonceSpace, nonce));
        vm.prank(caller);
        requestContract.acceptRequest({
            request: request,
            signature: _signRequest(borrowerPK, request),
            loanAssetPermit: "",
            collateralPermit: "",
            callersNonceSpace: nonceSpace,
            callersNonceToRevoke: nonce
        });
    }

    function testFuzz_shouldRevokeCallersNonce(address caller, uint256 nonceSpace, uint256 nonce) external {
        vm.expectCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)", caller, nonceSpace, nonce)
        );

        vm.prank(caller);
        requestContract.acceptRequest({
            request: request,
            signature: _signRequest(borrowerPK, request),
            loanAssetPermit: "",
            collateralPermit: "",
            callersNonceSpace: nonceSpace,
            callersNonceToRevoke: nonce
        });
    }

    // function is calling `acceptRequest`, no need to test it again
    function test_shouldCallLoanContract() external {
        uint256 newLoanId = requestContract.acceptRequest({
            request: request,
            signature: _signRequest(borrowerPK, request),
            loanAssetPermit: "",
            collateralPermit: "",
            callersNonceSpace: 1,
            callersNonceToRevoke: 2
        });

        assertEq(newLoanId, loanId);
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT REFINANCE REQUEST                              *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanSimpleRequest_AcceptRefinanceRequest_Test is PWNSimpleLoanSimpleRequestTest {

    function setUp() public override {
        super.setUp();
        request.refinancingLoanId = loanId;
    }


    function test_shouldFail_whenRefinancingLoanIdZero() external {
        request.refinancingLoanId = 0;

        vm.expectRevert(abi.encodeWithSelector(InvalidRefinancingLoanId.selector, request.refinancingLoanId));
        requestContract.acceptRefinanceRequest(0, request, _signRequest(borrowerPK, request), "", "");
    }

    function testFuzz_shouldFail_whenRefinancingLoanIdIsNotEqualToLoanId(uint256 _loanId, uint256 _refinancingLoanId) external {
        vm.assume(_loanId != _refinancingLoanId);
        vm.assume(_loanId != 0);
        request.refinancingLoanId = _refinancingLoanId;

        vm.expectRevert(abi.encodeWithSelector(InvalidRefinancingLoanId.selector, request.refinancingLoanId));
        requestContract.acceptRefinanceRequest(_loanId, request, _signRequest(borrowerPK, request), "", "");
    }

    function testFuzz_shouldFail_whenLoanContractNotTagged_ACTIVE_LOAN(address loanContract) external {
        vm.assume(loanContract != activeLoanContract);
        request.loanContract = loanContract;

        vm.expectRevert(abi.encodeWithSelector(AddressMissingHubTag.selector, loanContract, PWNHubTags.ACTIVE_LOAN));
        requestContract.acceptRefinanceRequest(loanId, request, _signRequest(borrowerPK, request), "", "");
    }

    function test_shouldNotCallComputerRegistry_whenShouldNotCheckStateFingerprint() external {
        request.checkCollateralStateFingerprint = false;

        vm.expectCall({
            callee: stateFingerprintComputerRegistry,
            data: abi.encodeWithSignature("getStateFingerprintComputer(address)", request.collateralAddress),
            count: 0
        });

        requestContract.acceptRefinanceRequest(loanId, request, _signRequest(borrowerPK, request), "", "");
    }

    function test_shouldFail_whenComputerRegistryReturnsZeroAddress_whenShouldCheckStateFingerprint() external {
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
        requestContract.acceptRefinanceRequest(loanId, request, _signRequest(borrowerPK, request), "", "");
    }

    function testFuzz_shouldFail_whenComputerReturnsDifferentStateFingerprint_whenShouldCheckStateFingerprint(
        bytes32 stateFingerprint
    ) external {
        vm.assume(stateFingerprint != request.collateralStateFingerprint);

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
            InvalidCollateralStateFingerprint.selector, stateFingerprint, request.collateralStateFingerprint
        ));
        requestContract.acceptRefinanceRequest(loanId, request, _signRequest(borrowerPK, request), "", "");
    }

    function test_shouldFail_whenInvalidSignature_whenEOA() external {
        vm.expectRevert(abi.encodeWithSelector(InvalidSignature.selector, request.borrower, _requestHash(request)));
        requestContract.acceptRefinanceRequest(loanId, request, _signRequest(1, request), "", "");
    }

    function test_shouldFail_whenInvalidSignature_whenContractAccount() external {
        vm.etch(borrower, bytes("data"));

        vm.expectRevert(abi.encodeWithSelector(InvalidSignature.selector, request.borrower, _requestHash(request)));
        requestContract.acceptRefinanceRequest(loanId, request, "", "", "");
    }

    function test_shouldPass_whenRequestHasBeenMadeOnchain() external {
        vm.store(
            address(requestContract),
            keccak256(abi.encode(_requestHash(request), PROPOSALS_MADE_SLOT)),
            bytes32(uint256(1))
        );

        requestContract.acceptRefinanceRequest(loanId, request, "", "", "");
    }

    function test_shouldPass_withValidSignature_whenEOA_whenStandardSignature() external {
        requestContract.acceptRefinanceRequest(loanId, request, _signRequest(borrowerPK, request), "", "");
    }

    function test_shouldPass_withValidSignature_whenEOA_whenCompactEIP2098Signature() external {
        requestContract.acceptRefinanceRequest(loanId, request, _signRequestCompact(borrowerPK, request), "", "");
    }

    function test_shouldPass_whenValidSignature_whenContractAccount() external {
        vm.etch(borrower, bytes("data"));

        vm.mockCall(
            borrower,
            abi.encodeWithSignature("isValidSignature(bytes32,bytes)"),
            abi.encode(bytes4(0x1626ba7e))
        );

        requestContract.acceptRefinanceRequest(loanId, request, "", "", "");
    }

    function testFuzz_shouldFail_whenRequestIsExpired(uint256 timestamp) external {
        timestamp = bound(timestamp, request.expiration, type(uint256).max);
        vm.warp(timestamp);

        vm.expectRevert(abi.encodeWithSelector(Expired.selector, timestamp, request.expiration));
        requestContract.acceptRefinanceRequest(loanId, request, _signRequest(borrowerPK, request), "", "");
    }

    function test_shouldFail_whenRequestNonceNotUsable() external {
        vm.mockCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)"),
            abi.encode(false)
        );
        vm.expectCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)", request.borrower, request.nonceSpace, request.nonce)
        );

        vm.expectRevert(abi.encodeWithSelector(
            NonceNotUsable.selector, request.borrower, request.nonceSpace, request.nonce
        ));
        requestContract.acceptRefinanceRequest(loanId, request, _signRequest(borrowerPK, request), "", "");
    }

    function testFuzz_shouldFail_whenCallerIsNotAllowedLender(address caller) external {
        address allowedLender = makeAddr("allowedLender");
        vm.assume(caller != allowedLender);
        request.allowedLender = allowedLender;

        vm.expectRevert(abi.encodeWithSelector(CallerNotAllowedAcceptor.selector, caller, request.allowedLender));
        vm.prank(caller);
        requestContract.acceptRefinanceRequest(loanId, request, _signRequest(borrowerPK, request), "", "");
    }

    function testFuzz_shouldFail_whenLessThanMinDuration(uint256 duration) external {
        vm.assume(duration < requestContract.MIN_LOAN_DURATION());
        duration = bound(duration, 0, requestContract.MIN_LOAN_DURATION() - 1);
        request.duration = uint32(duration);

        vm.expectRevert(abi.encodeWithSelector(InvalidDuration.selector, duration, requestContract.MIN_LOAN_DURATION()));
        requestContract.acceptRefinanceRequest(loanId, request, _signRequest(borrowerPK, request), "", "");
    }

    function testFuzz_shouldFail_whenAccruingInterestAPROutOfBounds(uint256 interestAPR) external {
        uint256 maxInterest = requestContract.MAX_ACCRUING_INTEREST_APR();
        interestAPR = bound(interestAPR, maxInterest + 1, type(uint40).max);
        request.accruingInterestAPR = uint40(interestAPR);

        vm.expectRevert(abi.encodeWithSelector(AccruingInterestAPROutOfBounds.selector, interestAPR, maxInterest));
        requestContract.acceptRefinanceRequest(loanId, request, _signRequest(borrowerPK, request), "", "");
    }

    function test_shouldRevokeRequest_whenAvailableCreditLimitEqualToZero() external {
        request.availableCreditLimit = 0;

        vm.expectCall(
            revokedNonce,
            abi.encodeWithSignature(
                "revokeNonce(address,uint256,uint256)", request.borrower, request.nonceSpace, request.nonce
            )
        );

        requestContract.acceptRefinanceRequest(loanId, request, _signRequest(borrowerPK, request), "", "");
    }

    function testFuzz_shouldFail_whenUsedCreditExceedsAvailableCreditLimit(uint256 used, uint256 limit) external {
        used = bound(used, 1, type(uint256).max - request.loanAmount);
        limit = bound(limit, used, used + request.loanAmount - 1);
        request.availableCreditLimit = limit;

        vm.store(address(requestContract), keccak256(abi.encode(_requestHash(request), CREDIT_USED_SLOT)), bytes32(used));

        vm.expectRevert(abi.encodeWithSelector(AvailableCreditLimitExceeded.selector, used + request.loanAmount, limit));
        requestContract.acceptRefinanceRequest(loanId, request, _signRequest(borrowerPK, request), "", "");
    }

    function testFuzz_shouldIncreaseUsedCredit_whenUsedCreditNotExceedsAvailableCreditLimit(uint256 used, uint256 limit) external {
        used = bound(used, 1, type(uint256).max - request.loanAmount);
        limit = bound(limit, used + request.loanAmount, type(uint256).max);
        request.availableCreditLimit = limit;

        vm.store(address(requestContract), keccak256(abi.encode(_requestHash(request), CREDIT_USED_SLOT)), bytes32(used));

        requestContract.acceptRefinanceRequest(loanId, request, _signRequest(borrowerPK, request), "", "");

        assertEq(requestContract.creditUsed(_requestHash(request)), used + request.loanAmount);
    }

    function test_shouldCallLoanContract() external {
        bytes memory loanAssetPermit = "loanAssetPermit";
        bytes memory collateralPermit = "collateralPermit";

        PWNSimpleLoan.Terms memory loanTerms = PWNSimpleLoan.Terms({
            lender: lender,
            borrower: request.borrower,
            duration: request.duration,
            collateral: MultiToken.Asset({
                category: request.collateralCategory,
                assetAddress: request.collateralAddress,
                id: request.collateralId,
                amount: request.collateralAmount
            }),
            asset: MultiToken.Asset({
                category: MultiToken.Category.ERC20,
                assetAddress: request.loanAssetAddress,
                id: 0,
                amount: request.loanAmount
            }),
            fixedInterestAmount: request.fixedInterestAmount,
            accruingInterestAPR: request.accruingInterestAPR
        });

        vm.expectCall(
            activeLoanContract,
            abi.encodeWithSelector(
                PWNSimpleLoan.refinanceLOAN.selector,
                loanId, _requestHash(request), loanTerms, loanAssetPermit, collateralPermit
            )
        );

        vm.prank(lender);
        requestContract.acceptRefinanceRequest(
            loanId, request, _signRequest(borrowerPK, request), loanAssetPermit, collateralPermit
        );
    }

    function test_shouldReturnRefinancedLoanId() external {
        assertEq(
            requestContract.acceptRefinanceRequest(loanId, request, _signRequest(borrowerPK, request), "", ""),
            refinancedLoanId
        );
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT REFINANCE REQUEST AND REVOKE CALLERS NONCE     *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanSimpleRequest_AcceptRefinanceRequestAndRevokeCallersNonce_Test is PWNSimpleLoanSimpleRequestTest {

    function setUp() public override {
        super.setUp();
        request.refinancingLoanId = loanId;
    }


    function testFuzz_shouldFail_whenNonceIsNotUsable(address caller, uint256 nonceSpace, uint256 nonce) external {
        vm.mockCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)", caller, nonceSpace, nonce),
            abi.encode(false)
        );

        vm.expectRevert(abi.encodeWithSelector(NonceNotUsable.selector, caller, nonceSpace, nonce));
        vm.prank(caller);
        requestContract.acceptRefinanceRequest({
            loanId: loanId,
            request: request,
            signature: _signRequest(borrowerPK, request),
            lenderLoanAssetPermit: "",
            borrowerLoanAssetPermit: "",
            callersNonceSpace: nonceSpace,
            callersNonceToRevoke: nonce
        });
    }

    function testFuzz_shouldRevokeCallersNonce(address caller, uint256 nonceSpace, uint256 nonce) external {
        vm.expectCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)", caller, nonceSpace, nonce)
        );

        vm.prank(caller);
        requestContract.acceptRefinanceRequest({
            loanId: loanId,
            request: request,
            signature: _signRequest(borrowerPK, request),
            lenderLoanAssetPermit: "",
            borrowerLoanAssetPermit: "",
            callersNonceSpace: nonceSpace,
            callersNonceToRevoke: nonce
        });
    }

    // function is calling `acceptRefinanceRequest`, no need to test it again
    function test_shouldCallLoanContract() external {
        uint256 newLoanId = requestContract.acceptRefinanceRequest({
            loanId: loanId,
            request: request,
            signature: _signRequest(borrowerPK, request),
            lenderLoanAssetPermit: "",
            borrowerLoanAssetPermit: "",
            callersNonceSpace: 1,
            callersNonceToRevoke: 2
        });

        assertEq(newLoanId, refinancedLoanId);
    }

}


/*----------------------------------------------------------*|
|*  # DECODE PROPOSAL                                       *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanSimpleRequest_DecodeProposal_Test is PWNSimpleLoanSimpleRequestTest {

    function test_shouldReturnDecodedRequestData() external {
        PWNSimpleLoanSimpleRequest.Request memory decodedRequest = requestContract.decodeProposal(abi.encode(request));

        assertEq(_requestHash(decodedRequest), _requestHash(request));
    }

}
