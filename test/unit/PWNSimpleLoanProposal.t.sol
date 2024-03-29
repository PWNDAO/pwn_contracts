// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import { MultiToken } from "MultiToken/MultiToken.sol";

import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import { PWNHubTags } from "@pwn/hub/PWNHubTags.sol";
import { PWNSimpleLoan } from "@pwn/loan/terms/simple/loan/PWNSimpleLoan.sol";
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

    Params public params;
    bytes public extra;

    PWNSimpleLoanProposal public proposalContractAddr; // Need to set in the inheriting contract

    struct Params {
        PWNSimpleLoanProposal.ProposalBase base;
        address acceptor;
        uint256 refinancingLoanId;
        uint256 signerPK;
        bool compactSignature;
    }

    function setUp() virtual public {
        vm.etch(hub, bytes("data"));
        vm.etch(revokedNonce, bytes("data"));
        vm.etch(token, bytes("data"));

        params.base.creditAmount = 1e10;
        params.base.checkCollateralStateFingerprint = true;
        params.base.collateralStateFingerprint = keccak256("some state fingerprint");
        params.base.expiration = uint40(block.timestamp + 20 minutes);
        params.base.proposer = proposer;
        params.base.loanContract = activeLoanContract;
        params.acceptor = acceptor;
        params.refinancingLoanId = 0;
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
            abi.encode(params.base.collateralStateFingerprint)
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

    function _callAcceptProposalWith() internal returns (bytes32, PWNSimpleLoan.Terms memory) {
        return _callAcceptProposalWith(params);
    }

    function _getProposalHashWith() internal returns (bytes32) {
        return _getProposalHashWith(params);
    }

    // Virtual functions to be implemented in inheriting contract
    function _callAcceptProposalWith(Params memory _params) internal virtual returns (bytes32, PWNSimpleLoan.Terms memory);
    function _getProposalHashWith(Params memory _params) internal virtual returns (bytes32);

}


/*----------------------------------------------------------*|
|*  # ACCEPT PROPOSAL                                       *|
|*----------------------------------------------------------*/

abstract contract PWNSimpleLoanProposal_AcceptProposal_Test is PWNSimpleLoanProposalTest {

    function testFuzz_shouldFail_whenCallerIsNotProposedLoanContract(address caller) external {
        vm.assume(caller != activeLoanContract);
        params.base.loanContract = activeLoanContract;

        vm.expectRevert(abi.encodeWithSelector(CallerNotLoanContract.selector, caller, activeLoanContract));
        vm.prank(caller);
        _callAcceptProposalWith();
    }

    function testFuzz_shouldFail_whenCallerNotTagged_ACTIVE_LOAN(address caller) external {
        vm.assume(caller != activeLoanContract);
        params.base.loanContract = caller;

        vm.expectRevert(abi.encodeWithSelector(AddressMissingHubTag.selector, caller, PWNHubTags.ACTIVE_LOAN));
        vm.prank(caller);
        _callAcceptProposalWith();
    }

    function test_shouldFail_whenInvalidSignature_whenEOA() external {
        params.signerPK = 1;

        vm.expectRevert(abi.encodeWithSelector(InvalidSignature.selector, proposer, _getProposalHashWith(params)));
        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function test_shouldFail_whenInvalidSignature_whenContractAccount() external {
        vm.etch(proposer, bytes("data"));
        params.signerPK = 0;

        vm.expectRevert(abi.encodeWithSelector(InvalidSignature.selector, proposer, _getProposalHashWith(params)));
        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function test_shouldPass_whenProposalMadeOnchain() external {
        vm.store(
            address(proposalContractAddr),
            keccak256(abi.encode(_getProposalHashWith(params), PROPOSALS_MADE_SLOT)),
            bytes32(uint256(1))
        );
        params.signerPK = 0;

        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function test_shouldPass_withValidSignature_whenEOA_whenStandardSignature() external {
        params.compactSignature = false;

        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function test_shouldPass_withValidSignature_whenEOA_whenCompactEIP2098Signature() external {
        params.compactSignature = true;

        vm.prank(activeLoanContract);
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

        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function testFuzz_shouldFail_whenProposedRefinancingLoanIdNotZero_whenRefinancingLoanIdZero(uint256 proposedRefinancingLoanId) external {
        vm.assume(proposedRefinancingLoanId != 0);
        params.base.refinancingLoanId = proposedRefinancingLoanId;
        params.refinancingLoanId = 0;

        vm.expectRevert(abi.encodeWithSelector(InvalidRefinancingLoanId.selector, proposedRefinancingLoanId));
        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function testFuzz_shouldFail_whenRefinancingLoanIdsIsNotEqual_whenProposedRefinanceingLoanIdNotZero_whenRefinancingLoanIdNotZero_whenOffer(
        uint256 refinancingLoanId, uint256 proposedRefinancingLoanId
    ) external {
        vm.assume(proposedRefinancingLoanId != 0);
        vm.assume(refinancingLoanId != proposedRefinancingLoanId);
        params.base.refinancingLoanId = proposedRefinancingLoanId;
        params.base.isOffer = true;
        params.refinancingLoanId = refinancingLoanId;

        vm.expectRevert(abi.encodeWithSelector(InvalidRefinancingLoanId.selector, proposedRefinancingLoanId));
        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function testFuzz_shouldPass_whenRefinancingLoanIdsNotEqual_whenProposedRefinanceingLoanIdZero_whenRefinancingLoanIdNotZero_whenOffer(
        uint256 refinancingLoanId
    ) external {
        vm.assume(refinancingLoanId != 0);
        params.base.refinancingLoanId = 0;
        params.base.isOffer = true;
        params.refinancingLoanId = refinancingLoanId;

        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function testFuzz_shouldFail_whenRefinancingLoanIdsNotEqual_whenRefinancingLoanIdNotZero_whenRequest(
        uint256 refinancingLoanId, uint256 proposedRefinancingLoanId
    ) external {
        vm.assume(refinancingLoanId != proposedRefinancingLoanId);
        params.base.refinancingLoanId = proposedRefinancingLoanId;
        params.base.isOffer = false;
        params.refinancingLoanId = refinancingLoanId;

        vm.expectRevert(abi.encodeWithSelector(InvalidRefinancingLoanId.selector, proposedRefinancingLoanId));
        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function testFuzz_shouldFail_whenProposalExpired(uint256 timestamp) external {
        timestamp = bound(timestamp, params.base.expiration, type(uint256).max);
        vm.warp(timestamp);

        vm.expectRevert(abi.encodeWithSelector(Expired.selector, timestamp, params.base.expiration));
        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function testFuzz_shouldFail_whenOfferNonceNotUsable(uint256 nonceSpace, uint256 nonce) external {
        params.base.nonceSpace = nonceSpace;
        params.base.nonce = nonce;

        vm.mockCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)"),
            abi.encode(false)
        );
        vm.expectCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)", proposer, nonceSpace, nonce)
        );

        vm.expectRevert(abi.encodeWithSelector(NonceNotUsable.selector, proposer, nonceSpace, nonce));
        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function testFuzz_shouldFail_whenCallerIsNotAllowedAcceptor(address caller) external {
        address allowedAcceptor = makeAddr("allowedAcceptor");
        vm.assume(caller != allowedAcceptor);
        params.base.allowedAcceptor = allowedAcceptor;
        params.acceptor = caller;

        vm.expectRevert(abi.encodeWithSelector(CallerNotAllowedAcceptor.selector, caller, allowedAcceptor));
        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function test_shouldRevokeOffer_whenAvailableCreditLimitEqualToZero(uint256 nonceSpace, uint256 nonce) external {
        params.base.availableCreditLimit = 0;
        params.base.nonceSpace = nonceSpace;
        params.base.nonce = nonce;

        vm.expectCall(
            revokedNonce,
            abi.encodeWithSignature("revokeNonce(address,uint256,uint256)", proposer, nonceSpace, nonce)
        );

        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function testFuzz_shouldFail_whenUsedCreditExceedsAvailableCreditLimit(uint256 used, uint256 limit) external {
        used = bound(used, 1, type(uint256).max - params.base.creditAmount);
        limit = bound(limit, used, used + params.base.creditAmount - 1);

        params.base.availableCreditLimit = limit;

        vm.store(
            address(proposalContractAddr),
            keccak256(abi.encode(_getProposalHashWith(params), CREDIT_USED_SLOT)),
            bytes32(used)
        );

        vm.expectRevert(abi.encodeWithSelector(
            AvailableCreditLimitExceeded.selector, used + params.base.creditAmount, limit
        ));
        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function testFuzz_shouldIncreaseUsedCredit_whenUsedCreditNotExceedsAvailableCreditLimit(uint256 used, uint256 limit) external {
        used = bound(used, 1, type(uint256).max - params.base.creditAmount);
        limit = bound(limit, used + params.base.creditAmount, type(uint256).max);

        params.base.availableCreditLimit = limit;

        bytes32 proposalHash = _getProposalHashWith(params);

        vm.store(
            address(proposalContractAddr),
            keccak256(abi.encode(proposalHash, CREDIT_USED_SLOT)),
            bytes32(used)
        );

        vm.prank(activeLoanContract);
        _callAcceptProposalWith();

        assertEq(proposalContractAddr.creditUsed(proposalHash), used + params.base.creditAmount);
    }

    function test_shouldNotCallComputerRegistry_whenShouldNotCheckStateFingerprint() external {
        params.base.checkCollateralStateFingerprint = false;

        vm.expectCall({
            callee: config,
            data: abi.encodeWithSignature("getStateFingerprintComputer(address)"),
            count: 0
        });

        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function test_shouldFail_whenComputerRegistryReturnsZeroAddress_whenShouldCheckStateFingerprint() external {
        params.base.collateralAddress = token;

        vm.mockCall(
            config,
            abi.encodeWithSignature("getStateFingerprintComputer(address)", token),
            abi.encode(address(0))
        );

        vm.expectRevert(abi.encodeWithSelector(MissingStateFingerprintComputer.selector));
        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function testFuzz_shouldFail_whenComputerReturnsDifferentStateFingerprint_whenShouldCheckStateFingerprint(
        bytes32 stateFingerprint
    ) external {
        vm.assume(stateFingerprint != params.base.collateralStateFingerprint);

        vm.mockCall(
            stateFingerprintComputer,
            abi.encodeWithSignature("getStateFingerprint(uint256)"),
            abi.encode(stateFingerprint)
        );

        vm.expectRevert(abi.encodeWithSelector(
            InvalidCollateralStateFingerprint.selector, stateFingerprint, params.base.collateralStateFingerprint
        ));
        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

}
