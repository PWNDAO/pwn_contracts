// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import { MultiToken } from "MultiToken/MultiToken.sol";

import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import { PWNHubTags } from "@pwn/hub/PWNHubTags.sol";
import { PWNSimpleLoan, Permit } from "@pwn/loan/terms/simple/loan/PWNSimpleLoan.sol";
import { PWNSimpleLoanProposal } from "@pwn/loan/terms/simple/proposal/PWNSimpleLoanProposal.sol";
import "@pwn/PWNErrors.sol";


abstract contract PWNSimpleLoanProposalTest is Test {

    bytes32 public constant PROPOSALS_MADE_SLOT = bytes32(uint256(0)); // `proposalsMade` mapping position
    bytes32 public constant CREDIT_USED_SLOT = bytes32(uint256(1)); // `creditUsed` mapping position

    address public hub = makeAddr("hub");
    address public revokedNonce = makeAddr("revokedNonce");
    address public config = makeAddr("config");
    address public stateFingerprintComputer = makeAddr("stateFingerprintComputer");
    address public activeLoanContract = makeAddr("activeLoanContract");
    address public token = makeAddr("token");
    uint256 public proposerPK = 73661723;
    address public proposer = vm.addr(proposerPK);
    uint256 public acceptorPK = 32716637;
    address public acceptor = vm.addr(acceptorPK);
    uint256 public loanId = 421;
    uint256 public refinancedLoanId = 123;

    Params public params;
    Permit public permit;
    bytes public extra;

    PWNSimpleLoanProposal public proposalContractAddr; // Need to set in the inheriting contract

    struct Params {
        bool checkCollateralStateFingerprint;
        bytes32 collateralStateFingerprint;
        uint256 creditAmount;
        uint256 availableCreditLimit;
        uint32 duration;
        uint40 accruingInterestAPR;
        uint40 expiration;
        address allowedAcceptor;
        address proposer;
        address loanContract;
        uint256 nonceSpace;
        uint256 nonce;
        uint256 signerPK;
        bool compactSignature;
        // cannot add anymore fields b/c of stack too deep error
    }

    function setUp() virtual public {
        vm.etch(hub, bytes("data"));
        vm.etch(revokedNonce, bytes("data"));
        vm.etch(token, bytes("data"));

        params.creditAmount = 1e10;
        params.checkCollateralStateFingerprint = true;
        params.collateralStateFingerprint = keccak256("some state fingerprint");
        params.duration = 1 hours;
        params.expiration = uint40(block.timestamp + 20 minutes);
        params.proposer = proposer;
        params.loanContract = activeLoanContract;
        params.signerPK = proposerPK;
        params.compactSignature = false;

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
            config,
            abi.encodeWithSignature("getStateFingerprintComputer(address)"),
            abi.encode(stateFingerprintComputer)
        );
        vm.mockCall(
            stateFingerprintComputer,
            abi.encodeWithSignature("getStateFingerprint(uint256)"),
            abi.encode(params.collateralStateFingerprint)
        );

        vm.mockCall(
            activeLoanContract, abi.encodeWithSelector(PWNSimpleLoan.createLOAN.selector), abi.encode(loanId)
        );
        vm.mockCall(
            activeLoanContract, abi.encodeWithSelector(PWNSimpleLoan.refinanceLOAN.selector), abi.encode(refinancedLoanId)
        );
    }

    function _signProposalHash(uint256 pk, bytes32 proposalHash) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, proposalHash);
        return abi.encodePacked(r, s, v);
    }

    function _signProposalHashCompact(uint256 pk, bytes32 proposalHash) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, proposalHash);
        return abi.encodePacked(r, bytes32(uint256(v) - 27) << 255 | s);
    }


    function _callAcceptProposalWith(Params memory _params, Permit memory _permit) internal virtual returns (uint256);
    function _callAcceptProposalWith(Params memory _params, Permit memory _permit, uint256 nonceSpace, uint256 nonce) internal virtual returns (uint256);
    function _callAcceptRefinanceProposalWith(uint256 loanId, Params memory _params, Permit memory _permit) internal virtual returns (uint256);
    function _callAcceptRefinanceProposalWith(uint256 loanId, Params memory _params, Permit memory _permit, uint256 nonceSpace, uint256 nonce) internal virtual returns (uint256);
    function _getProposalHashWith(Params memory _params) internal virtual returns (bytes32);


    function _callAcceptProposalWith() internal returns (uint256) {
        return _callAcceptProposalWith(params, permit);
    }

    function _callAcceptRefinanceProposalWith() internal returns (uint256) {
        return _callAcceptRefinanceProposalWith(loanId, params, permit);
    }

    function _getProposalHashWith() internal returns (bytes32) {
        return _getProposalHashWith(params);
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT PROPOSAL                                       *|
|*----------------------------------------------------------*/

abstract contract PWNSimpleLoanProposal_AcceptProposal_Test is PWNSimpleLoanProposalTest {

    function testFuzz_shouldFail_whenLoanContractNotTagged_ACTIVE_LOAN(address loanContract) external {
        vm.assume(loanContract != activeLoanContract);
        params.loanContract = loanContract;

        vm.expectRevert(abi.encodeWithSelector(AddressMissingHubTag.selector, loanContract, PWNHubTags.ACTIVE_LOAN));
        _callAcceptProposalWith();
    }

    function test_shouldNotCallComputerRegistry_whenShouldNotCheckStateFingerprint() external {
        params.checkCollateralStateFingerprint = false;

        vm.expectCall({
            callee: config,
            data: abi.encodeWithSignature("getStateFingerprintComputer(address)"),
            count: 0
        });

        _callAcceptProposalWith();
    }

    function test_shouldFail_whenComputerRegistryReturnsZeroAddress_whenShouldCheckStateFingerprint() external {
        vm.mockCall(
            config,
            abi.encodeWithSignature("getStateFingerprintComputer(address)", token), // test expects `token` being used as collateral asset
            abi.encode(address(0))
        );

        vm.expectRevert(abi.encodeWithSelector(MissingStateFingerprintComputer.selector));
        _callAcceptProposalWith();
    }

    function testFuzz_shouldFail_whenComputerReturnsDifferentStateFingerprint_whenShouldCheckStateFingerprint(
        bytes32 stateFingerprint
    ) external {
        vm.assume(stateFingerprint != params.collateralStateFingerprint);

        vm.mockCall(
            stateFingerprintComputer,
            abi.encodeWithSignature("getStateFingerprint(uint256)"),
            abi.encode(stateFingerprint)
        );

        vm.expectRevert(abi.encodeWithSelector(
            InvalidCollateralStateFingerprint.selector, stateFingerprint, params.collateralStateFingerprint
        ));
        _callAcceptProposalWith();
    }

    function test_shouldFail_whenInvalidSignature_whenEOA() external {
        params.signerPK = 1;

        vm.expectRevert(abi.encodeWithSelector(InvalidSignature.selector, proposer, _getProposalHashWith(params)));
        _callAcceptProposalWith();
    }

    function test_shouldFail_whenInvalidSignature_whenContractAccount() external {
        vm.etch(proposer, bytes("data"));
        params.signerPK = 0;

        vm.expectRevert(abi.encodeWithSelector(InvalidSignature.selector, proposer, _getProposalHashWith(params)));
        _callAcceptProposalWith();
    }

    function test_shouldPass_whenProposalMadeOnchain() external {
        vm.store(
            address(proposalContractAddr),
            keccak256(abi.encode(_getProposalHashWith(params), PROPOSALS_MADE_SLOT)),
            bytes32(uint256(1))
        );
        params.signerPK = 0;

        _callAcceptProposalWith();
    }

    function test_shouldPass_withValidSignature_whenEOA_whenStandardSignature() external {
        params.compactSignature = false;
        _callAcceptProposalWith();
    }

    function test_shouldPass_withValidSignature_whenEOA_whenCompactEIP2098Signature() external {
        params.compactSignature = true;
        _callAcceptProposalWith();
    }

    function test_shouldPass_whenValidSignature_whenContractAccount() external {
        vm.etch(proposer, bytes("data"));
        params.signerPK = 0;

        vm.mockCall(
            proposer,
            abi.encodeWithSignature("isValidSignature(bytes32,bytes)"),
            abi.encode(bytes4(0x1626ba7e))
        );

        _callAcceptProposalWith();
    }

    function testFuzz_shouldFail_whenProposalExpired(uint256 timestamp) external {
        timestamp = bound(timestamp, params.expiration, type(uint256).max);
        vm.warp(timestamp);

        vm.expectRevert(abi.encodeWithSelector(Expired.selector, timestamp, params.expiration));
        _callAcceptProposalWith();
    }

    function testFuzz_shouldFail_whenOfferNonceNotUsable(uint256 nonceSpace, uint256 nonce) external {
        params.nonceSpace = nonceSpace;
        params.nonce = nonce;

        vm.mockCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)"),
            abi.encode(false)
        );
        vm.expectCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)", proposer, nonceSpace, nonce)
        );

        vm.expectRevert(abi.encodeWithSelector(
            NonceNotUsable.selector, proposer, nonceSpace, nonce
        ));
        _callAcceptProposalWith();
    }

    function testFuzz_shouldFail_whenCallerIsNotAllowedAcceptor(address caller) external {
        address allowedAcceptor = makeAddr("allowedAcceptor");
        vm.assume(caller != allowedAcceptor);
        params.allowedAcceptor = allowedAcceptor;

        vm.expectRevert(abi.encodeWithSelector(CallerNotAllowedAcceptor.selector, caller, allowedAcceptor));
        vm.prank(caller);
        _callAcceptProposalWith();
    }

    function testFuzz_shouldFail_whenLessThanMinDuration(uint256 duration) external {
        uint256 minDuration = proposalContractAddr.MIN_LOAN_DURATION();
        vm.assume(duration < minDuration);
        duration = bound(duration, 0, minDuration - 1);
        params.duration = uint32(duration);

        vm.expectRevert(abi.encodeWithSelector(InvalidDuration.selector, duration, minDuration));
        _callAcceptProposalWith();
    }

    function testFuzz_shouldFail_whenAccruingInterestAPROutOfBounds(uint256 interestAPR) external {
        uint256 maxInterest = proposalContractAddr.MAX_ACCRUING_INTEREST_APR();
        interestAPR = bound(interestAPR, maxInterest + 1, type(uint40).max);
        params.accruingInterestAPR = uint40(interestAPR);

        vm.expectRevert(abi.encodeWithSelector(AccruingInterestAPROutOfBounds.selector, interestAPR, maxInterest));
        _callAcceptProposalWith();
    }

    function test_shouldRevokeOffer_whenAvailableCreditLimitEqualToZero(uint256 nonceSpace, uint256 nonce) external {
        params.availableCreditLimit = 0;
        params.nonceSpace = nonceSpace;
        params.nonce = nonce;

        vm.expectCall(
            revokedNonce,
            abi.encodeWithSignature("revokeNonce(address,uint256,uint256)", proposer, nonceSpace, nonce)
        );

        _callAcceptProposalWith();
    }

    function testFuzz_shouldFail_whenUsedCreditExceedsAvailableCreditLimit(uint256 used, uint256 limit) external {
        used = bound(used, 1, type(uint256).max - params.creditAmount);
        limit = bound(limit, used, used + params.creditAmount - 1);

        params.availableCreditLimit = limit;

        vm.store(
            address(proposalContractAddr),
            keccak256(abi.encode(_getProposalHashWith(params), CREDIT_USED_SLOT)),
            bytes32(used)
        );

        vm.expectRevert(abi.encodeWithSelector(AvailableCreditLimitExceeded.selector, used + params.creditAmount, limit));
        _callAcceptProposalWith();
    }

    function testFuzz_shouldIncreaseUsedCredit_whenUsedCreditNotExceedsAvailableCreditLimit(uint256 used, uint256 limit) external {
        used = bound(used, 1, type(uint256).max - params.creditAmount);
        limit = bound(limit, used + params.creditAmount, type(uint256).max);

        params.availableCreditLimit = limit;

        bytes32 proposalHash = _getProposalHashWith(params);

        vm.store(
            address(proposalContractAddr),
            keccak256(abi.encode(proposalHash, CREDIT_USED_SLOT)),
            bytes32(used)
        );

        _callAcceptProposalWith();

        assertEq(proposalContractAddr.creditUsed(proposalHash), used + params.creditAmount);
    }

    function testFuzz_shouldFail_whenPermitOwnerNotCaller(address owner, address caller) external {
        vm.assume(owner != caller && owner != address(0) && caller != address(0));

        permit.owner = owner;
        permit.asset = token; // test expects `token` being used as credit asset

        vm.expectRevert(abi.encodeWithSelector(InvalidPermitOwner.selector, owner, caller));
        vm.prank(caller);
        _callAcceptProposalWith();
    }

    function testFuzz_shouldFail_whenPermitAssetNotCreditAsset(address asset, address caller) external {
        vm.assume(asset != token && asset != address(0) && caller != address(0));

        permit.owner = caller;
        permit.asset = asset; // test expects `token` being used as credit asset

        vm.expectRevert(abi.encodeWithSelector(InvalidPermitAsset.selector, asset, token));
        vm.prank(caller);
        _callAcceptProposalWith();
    }

    function test_shouldReturnNewLoanId() external {
        assertEq(_callAcceptProposalWith(), loanId);
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT PROPOSAL AND REVOKE CALLERS NONCE              *|
|*----------------------------------------------------------*/

abstract contract PWNSimpleLoanProposal_AcceptProposalAndRevokeCallersNonce_Test is PWNSimpleLoanProposalTest {

    function testFuzz_shouldFail_whenNonceIsNotUsable(address caller, uint256 nonceSpace, uint256 nonce) external {
        vm.mockCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)", caller, nonceSpace, nonce),
            abi.encode(false)
        );

        vm.expectRevert(abi.encodeWithSelector(NonceNotUsable.selector, caller, nonceSpace, nonce));
        vm.prank(caller);
        _callAcceptProposalWith(params, permit, nonceSpace, nonce);
    }

    function testFuzz_shouldRevokeCallersNonce(address caller, uint256 nonceSpace, uint256 nonce) external {
        vm.expectCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)", caller, nonceSpace, nonce)
        );

        vm.prank(caller);
        _callAcceptProposalWith(params, permit, nonceSpace, nonce);
    }

    // function is calling `acceptProposal`, no need to test it again
    function test_shouldCallLoanContract() external {
        assertEq(_callAcceptProposalWith(params, permit, 1, 2), loanId);
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT REFINANCE PROPOSAL                             *|
|*----------------------------------------------------------*/

abstract contract PWNSimpleLoanProposal_AcceptRefinanceProposal_Test is PWNSimpleLoanProposalTest {

    function testFuzz_shouldFail_whenLoanContractNotTagged_ACTIVE_LOAN(address loanContract) external {
        vm.assume(loanContract != activeLoanContract);
        params.loanContract = loanContract;

        vm.expectRevert(abi.encodeWithSelector(AddressMissingHubTag.selector, loanContract, PWNHubTags.ACTIVE_LOAN));
        _callAcceptRefinanceProposalWith();
    }

    function test_shouldNotCallComputerRegistry_whenShouldNotCheckStateFingerprint() external {
        params.checkCollateralStateFingerprint = false;

        vm.expectCall({
            callee: config,
            data: abi.encodeWithSignature("getStateFingerprintComputer(address)"),
            count: 0
        });

        _callAcceptRefinanceProposalWith();
    }

    function test_shouldFail_whenComputerRegistryReturnsZeroAddress_whenShouldCheckStateFingerprint() external {
        vm.mockCall(
            config,
            abi.encodeWithSignature("getStateFingerprintComputer(address)", token), // test expects `token` being used as collateral asset
            abi.encode(address(0))
        );

        vm.expectRevert(abi.encodeWithSelector(MissingStateFingerprintComputer.selector));
        _callAcceptRefinanceProposalWith();
    }

    function testFuzz_shouldFail_whenComputerReturnsDifferentStateFingerprint_whenShouldCheckStateFingerprint(
        bytes32 stateFingerprint
    ) external {
        vm.assume(stateFingerprint != params.collateralStateFingerprint);

        vm.mockCall(
            stateFingerprintComputer,
            abi.encodeWithSignature("getStateFingerprint(uint256)"),
            abi.encode(stateFingerprint)
        );

        vm.expectRevert(abi.encodeWithSelector(
            InvalidCollateralStateFingerprint.selector, stateFingerprint, params.collateralStateFingerprint
        ));
        _callAcceptRefinanceProposalWith();
    }

    function test_shouldFail_whenInvalidSignature_whenEOA() external {
        params.signerPK = 1;

        vm.expectRevert(abi.encodeWithSelector(InvalidSignature.selector, proposer, _getProposalHashWith(params)));
        _callAcceptRefinanceProposalWith();
    }

    function test_shouldFail_whenInvalidSignature_whenContractAccount() external {
        vm.etch(proposer, bytes("data"));
        params.signerPK = 0;

        vm.expectRevert(abi.encodeWithSelector(InvalidSignature.selector, proposer, _getProposalHashWith(params)));
        _callAcceptRefinanceProposalWith();
    }

    function test_shouldPass_whenProposalMadeOnchain() external {
        vm.store(
            address(proposalContractAddr),
            keccak256(abi.encode(_getProposalHashWith(params), PROPOSALS_MADE_SLOT)),
            bytes32(uint256(1))
        );
        params.signerPK = 0;

        _callAcceptRefinanceProposalWith();
    }

    function test_shouldPass_withValidSignature_whenEOA_whenStandardSignature() external {
        params.compactSignature = false;
        _callAcceptRefinanceProposalWith();
    }

    function test_shouldPass_withValidSignature_whenEOA_whenCompactEIP2098Signature() external {
        params.compactSignature = true;
        _callAcceptRefinanceProposalWith();
    }

    function test_shouldPass_whenValidSignature_whenContractAccount() external {
        vm.etch(proposer, bytes("data"));
        params.signerPK = 0;

        vm.mockCall(
            proposer,
            abi.encodeWithSignature("isValidSignature(bytes32,bytes)"),
            abi.encode(bytes4(0x1626ba7e))
        );

        _callAcceptRefinanceProposalWith();
    }

    function testFuzz_shouldFail_whenProposalExpired(uint256 timestamp) external {
        timestamp = bound(timestamp, params.expiration, type(uint256).max);
        vm.warp(timestamp);

        vm.expectRevert(abi.encodeWithSelector(Expired.selector, timestamp, params.expiration));
        _callAcceptRefinanceProposalWith();
    }

    function testFuzz_shouldFail_whenOfferNonceNotUsable(uint256 nonceSpace, uint256 nonce) external {
        params.nonceSpace = nonceSpace;
        params.nonce = nonce;

        vm.mockCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)"),
            abi.encode(false)
        );
        vm.expectCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)", proposer, nonceSpace, nonce)
        );

        vm.expectRevert(abi.encodeWithSelector(
            NonceNotUsable.selector, proposer, nonceSpace, nonce
        ));
        _callAcceptRefinanceProposalWith();
    }

    function testFuzz_shouldFail_whenCallerIsNotAllowedAcceptor(address caller) external {
        address allowedAcceptor = makeAddr("allowedAcceptor");
        vm.assume(caller != allowedAcceptor);
        params.allowedAcceptor = allowedAcceptor;

        vm.expectRevert(abi.encodeWithSelector(CallerNotAllowedAcceptor.selector, caller, allowedAcceptor));
        vm.prank(caller);
        _callAcceptRefinanceProposalWith();
    }

    function testFuzz_shouldFail_whenLessThanMinDuration(uint256 duration) external {
        uint256 minDuration = proposalContractAddr.MIN_LOAN_DURATION();
        vm.assume(duration < minDuration);
        duration = bound(duration, 0, minDuration - 1);
        params.duration = uint32(duration);

        vm.expectRevert(abi.encodeWithSelector(InvalidDuration.selector, duration, minDuration));
        _callAcceptRefinanceProposalWith();
    }

    function testFuzz_shouldFail_whenAccruingInterestAPROutOfBounds(uint256 interestAPR) external {
        uint256 maxInterest = proposalContractAddr.MAX_ACCRUING_INTEREST_APR();
        interestAPR = bound(interestAPR, maxInterest + 1, type(uint40).max);
        params.accruingInterestAPR = uint40(interestAPR);

        vm.expectRevert(abi.encodeWithSelector(AccruingInterestAPROutOfBounds.selector, interestAPR, maxInterest));
        _callAcceptRefinanceProposalWith();
    }

    function test_shouldRevokeOffer_whenAvailableCreditLimitEqualToZero(uint256 nonceSpace, uint256 nonce) external {
        params.availableCreditLimit = 0;
        params.nonceSpace = nonceSpace;
        params.nonce = nonce;

        vm.expectCall(
            revokedNonce,
            abi.encodeWithSignature("revokeNonce(address,uint256,uint256)", proposer, nonceSpace, nonce)
        );

        _callAcceptRefinanceProposalWith();
    }

    function testFuzz_shouldFail_whenUsedCreditExceedsAvailableCreditLimit(uint256 used, uint256 limit) external {
        used = bound(used, 1, type(uint256).max - params.creditAmount);
        limit = bound(limit, used, used + params.creditAmount - 1);

        params.availableCreditLimit = limit;

        vm.store(
            address(proposalContractAddr),
            keccak256(abi.encode(_getProposalHashWith(params), CREDIT_USED_SLOT)),
            bytes32(used)
        );

        vm.expectRevert(abi.encodeWithSelector(AvailableCreditLimitExceeded.selector, used + params.creditAmount, limit));
        _callAcceptRefinanceProposalWith();
    }

    function testFuzz_shouldIncreaseUsedCredit_whenUsedCreditNotExceedsAvailableCreditLimit(uint256 used, uint256 limit) external {
        used = bound(used, 1, type(uint256).max - params.creditAmount);
        limit = bound(limit, used + params.creditAmount, type(uint256).max);

        params.availableCreditLimit = limit;

        bytes32 proposalHash = _getProposalHashWith(params);

        vm.store(
            address(proposalContractAddr),
            keccak256(abi.encode(proposalHash, CREDIT_USED_SLOT)),
            bytes32(used)
        );

        _callAcceptRefinanceProposalWith();

        assertEq(proposalContractAddr.creditUsed(proposalHash), used + params.creditAmount);
    }

    function testFuzz_shouldFail_whenPermitOwnerNotCaller(address owner, address caller) external {
        vm.assume(owner != caller && owner != address(0) && caller != address(0));

        permit.owner = owner;
        permit.asset = token; // test expects `token` being used as credit asset

        vm.expectRevert(abi.encodeWithSelector(InvalidPermitOwner.selector, owner, caller));
        vm.prank(caller);
        _callAcceptRefinanceProposalWith();
    }

    function testFuzz_shouldFail_whenPermitAssetNotCreditAsset(address asset, address caller) external {
        vm.assume(asset != token && asset != address(0) && caller != address(0));

        permit.owner = caller;
        permit.asset = asset; // test expects `token` being used as credit asset

        vm.expectRevert(abi.encodeWithSelector(InvalidPermitAsset.selector, asset, token));
        vm.prank(caller);
        _callAcceptRefinanceProposalWith();
    }

    function test_shouldReturnRefinancedLoanId() external {
        assertEq(_callAcceptRefinanceProposalWith(), refinancedLoanId);
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT REFINANCE PROPOSAL AND REVOKE CALLERS NONCE    *|
|*----------------------------------------------------------*/

abstract contract PWNSimpleLoanProposal_AcceptRefinanceProposalAndRevokeCallersNonce_Test is PWNSimpleLoanProposalTest {

    function testFuzz_shouldFail_whenNonceIsNotUsable(address caller, uint256 nonceSpace, uint256 nonce) external {
        vm.mockCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)", caller, nonceSpace, nonce),
            abi.encode(false)
        );

        vm.expectRevert(abi.encodeWithSelector(NonceNotUsable.selector, caller, nonceSpace, nonce));
        vm.prank(caller);
        _callAcceptRefinanceProposalWith(loanId, params, permit, nonceSpace, nonce);
    }

    function testFuzz_shouldRevokeCallersNonce(address caller, uint256 nonceSpace, uint256 nonce) external {
        vm.expectCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)", caller, nonceSpace, nonce)
        );

        vm.prank(caller);
        _callAcceptRefinanceProposalWith(loanId, params, permit, nonceSpace, nonce);
    }

    // function is calling `acceptRefinanceProposal`, no need to test it again
    function test_shouldCallLoanContract() external {
        assertEq(_callAcceptRefinanceProposalWith(loanId, params, permit, 1, 2), refinancedLoanId);
    }

}
