// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import { MultiToken } from "MultiToken/MultiToken.sol";

import { MerkleProof } from "openzeppelin/utils/cryptography/MerkleProof.sol";
import { IERC165 } from "openzeppelin/utils/introspection/IERC165.sol";
import { Math } from "openzeppelin/utils/math/Math.sol";

import {
    PWNSimpleLoanProposal,
    PWNHubTags,
    PWNSimpleLoan,
    PWNSignatureChecker,
    PWNRevokedNonce,
    AddressMissingHubTag,
    Expired,
    IERC5646
} from "pwn/loan/terms/simple/proposal/PWNSimpleLoanProposal.sol";


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
        bytes32[] proposalInclusionProof;
        bytes signature;
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
            abi.encodeWithSignature("computeStateFingerprint(address,uint256)"),
            abi.encode(params.base.collateralStateFingerprint)
        );
    }

    function _mockERC5646Support(address asset, bool result) internal {
        _mockERC165Call(asset, type(IERC165).interfaceId, true);
        _mockERC165Call(asset, hex"ffffffff", false);
        _mockERC165Call(asset, type(IERC5646).interfaceId, result);
    }

    function _mockERC165Call(address asset, bytes4 interfaceId, bool result) internal {
        vm.mockCall(
            asset,
            abi.encodeWithSignature("supportsInterface(bytes4)", interfaceId),
            abi.encode(result)
        );
    }

    function _sign(uint256 pk, bytes32 proposalHash) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, proposalHash);
        return abi.encodePacked(r, s, v);
    }

    function _signCompact(uint256 pk, bytes32 proposalHash) internal pure returns (bytes memory) {
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
        params.signature = _sign(proposerPK, _getProposalHashWith());

        vm.expectRevert(
            abi.encodeWithSelector(PWNSimpleLoanProposal.CallerNotLoanContract.selector, caller, activeLoanContract)
        );
        vm.prank(caller);
        _callAcceptProposalWith();
    }

    function testFuzz_shouldFail_whenCallerNotTagged_ACTIVE_LOAN(address caller) external {
        vm.assume(caller != activeLoanContract);
        params.base.loanContract = caller;
        params.signature = _sign(proposerPK, _getProposalHashWith());

        vm.expectRevert(abi.encodeWithSelector(AddressMissingHubTag.selector, caller, PWNHubTags.ACTIVE_LOAN));
        vm.prank(caller);
        _callAcceptProposalWith();
    }

    function testFuzz_shouldFail_whenInvalidSignature_whenEOA(uint256 randomPK) external {
        randomPK = boundPrivateKey(randomPK);
        vm.assume(randomPK != proposerPK);
        params.signature = _sign(randomPK, _getProposalHashWith());

        vm.expectRevert(
            abi.encodeWithSelector(PWNSignatureChecker.InvalidSignature.selector, proposer, _getProposalHashWith())
        );
        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function test_shouldFail_whenInvalidSignature_whenContractAccount() external {
        vm.etch(proposer, bytes("data"));
        params.signature = "";

        vm.expectRevert(
            abi.encodeWithSelector(PWNSignatureChecker.InvalidSignature.selector, proposer, _getProposalHashWith())
        );
        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function testFuzz_shouldFail_withInvalidSignature_whenEOA_whenMultiproposal(uint256 randomPK) external {
        randomPK = boundPrivateKey(randomPK);
        vm.assume(randomPK != proposerPK);

        bytes32 proposalHash = _getProposalHashWith();
        bytes32[] memory proposalInclusionProof = new bytes32[](1);
        proposalInclusionProof[0] = keccak256("leaf1");
        bytes32 root = keccak256(
            uint256(proposalHash) < uint256(proposalInclusionProof[0])
                ? abi.encode(proposalHash, proposalInclusionProof[0])
                : abi.encode(proposalInclusionProof[0], proposalHash)
        );
        bytes32 multiproposalHash = proposalContractAddr.getMultiproposalHash(PWNSimpleLoanProposal.Multiproposal(root));
        params.signature = _sign(randomPK, multiproposalHash);
        params.proposalInclusionProof = proposalInclusionProof;

        vm.expectRevert(abi.encodeWithSelector(PWNSignatureChecker.InvalidSignature.selector, proposer, multiproposalHash));
        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function test_shouldFail_whenInvalidSignature_whenContractAccount_whenMultiproposal() external {
        vm.etch(proposer, bytes("data"));
        bytes32 proposalHash = _getProposalHashWith();
        bytes32[] memory proposalInclusionProof = new bytes32[](1);
        proposalInclusionProof[0] = keccak256("leaf1");
        bytes32 root = keccak256(
            uint256(proposalHash) < uint256(proposalInclusionProof[0])
                ? abi.encode(proposalHash, proposalInclusionProof[0])
                : abi.encode(proposalInclusionProof[0], proposalHash)
        );
        bytes32 multiproposalHash = proposalContractAddr.getMultiproposalHash(PWNSimpleLoanProposal.Multiproposal(root));
        params.signature = "";
        params.proposalInclusionProof = proposalInclusionProof;

        vm.expectRevert(abi.encodeWithSelector(PWNSignatureChecker.InvalidSignature.selector, proposer, multiproposalHash));
        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function test_shouldFail_withInvalidInclusionProof() external {
        bytes32 proposalHash = _getProposalHashWith();
        bytes32[] memory proposalInclusionProof = new bytes32[](1);
        proposalInclusionProof[0] = keccak256("other leaf1");
        bytes32 leaf = keccak256("leaf1");
        bytes32 root = keccak256(
            uint256(proposalHash) < uint256(leaf)
                ? abi.encode(proposalHash, leaf)
                : abi.encode(leaf, proposalHash)
        );
        bytes32 multiproposalHash = proposalContractAddr.getMultiproposalHash(PWNSimpleLoanProposal.Multiproposal(root));
        params.signature = _sign(proposerPK, multiproposalHash);
        params.proposalInclusionProof = proposalInclusionProof;

        bytes32 actualRoot = keccak256(
            uint256(proposalHash) < uint256(proposalInclusionProof[0])
                ? abi.encode(proposalHash, proposalInclusionProof[0])
                : abi.encode(proposalInclusionProof[0], proposalHash)
        );
        bytes32 actualMultiproposalHash = proposalContractAddr.getMultiproposalHash(PWNSimpleLoanProposal.Multiproposal(actualRoot));
        vm.expectRevert(
            abi.encodeWithSelector(PWNSignatureChecker.InvalidSignature.selector, proposer, actualMultiproposalHash)
        );
        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function test_shouldPass_whenProposalMadeOnchain() external {
        vm.store(
            address(proposalContractAddr),
            keccak256(abi.encode(_getProposalHashWith(), PROPOSALS_MADE_SLOT)),
            bytes32(uint256(1))
        );
        params.signature = "";

        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function test_shouldPass_withValidSignature_whenEOA_whenStandardSignature() external {
        params.signature = _sign(proposerPK, _getProposalHashWith());

        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function test_shouldPass_withValidSignature_whenEOA_whenCompactEIP2098Signature() external {
        params.signature = _signCompact(proposerPK, _getProposalHashWith());

        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function test_shouldPass_whenValidSignature_whenContractAccount() external {
        vm.etch(proposer, bytes("data"));
        params.signature = bytes("some signature");

        bytes32 proposalHash = _getProposalHashWith();

        vm.mockCall(
            proposer,
            abi.encodeWithSignature("isValidSignature(bytes32,bytes)", proposalHash, params.signature),
            abi.encode(bytes4(0x1626ba7e))
        );

        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function test_shouldPass_withValidSignature_whenEOA_whenStandardSignature_whenMultiproposal() external {
        bytes32 proposalHash = _getProposalHashWith();
        bytes32[] memory proposalInclusionProof = new bytes32[](1);
        proposalInclusionProof[0] = keccak256("leaf1");
        bytes32 root = keccak256(
            uint256(proposalHash) < uint256(proposalInclusionProof[0])
                ? abi.encode(proposalHash, proposalInclusionProof[0])
                : abi.encode(proposalInclusionProof[0], proposalHash)
        );
        bytes32 multiproposalHash = proposalContractAddr.getMultiproposalHash(PWNSimpleLoanProposal.Multiproposal(root));
        params.signature = _sign(proposerPK, multiproposalHash);
        params.proposalInclusionProof = proposalInclusionProof;

        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function test_shouldPass_withValidSignature_whenEOA_whenCompactEIP2098Signature_whenMultiproposal() external {
        bytes32 proposalHash = _getProposalHashWith();
        bytes32[] memory proposalInclusionProof = new bytes32[](1);
        proposalInclusionProof[0] = keccak256("leaf1");
        bytes32 root = keccak256(
            uint256(proposalHash) < uint256(proposalInclusionProof[0])
                ? abi.encode(proposalHash, proposalInclusionProof[0])
                : abi.encode(proposalInclusionProof[0], proposalHash)
        );
        bytes32 multiproposalHash = proposalContractAddr.getMultiproposalHash(PWNSimpleLoanProposal.Multiproposal(root));
        params.signature = _signCompact(proposerPK, multiproposalHash);
        params.proposalInclusionProof = proposalInclusionProof;

        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function test_shouldPass_whenValidSignature_whenContractAccount_whenMultiproposal() external {
        vm.etch(proposer, bytes("data"));
        bytes32 proposalHash = _getProposalHashWith();
        bytes32[] memory proposalInclusionProof = new bytes32[](1);
        proposalInclusionProof[0] = keccak256("leaf1");
        bytes32 root = keccak256(
            uint256(proposalHash) < uint256(proposalInclusionProof[0])
                ? abi.encode(proposalHash, proposalInclusionProof[0])
                : abi.encode(proposalInclusionProof[0], proposalHash)
        );
        bytes32 multiproposalHash = proposalContractAddr.getMultiproposalHash(PWNSimpleLoanProposal.Multiproposal(root));
        params.signature = bytes("some random string");
        params.proposalInclusionProof = proposalInclusionProof;

        vm.mockCall(
            proposer,
            abi.encodeWithSignature("isValidSignature(bytes32,bytes)", multiproposalHash, params.signature),
            abi.encode(bytes4(0x1626ba7e))
        );

        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function test_shouldFail_whenProposerIsSameAsAcceptor() external {
        params.acceptor = proposer;
        params.signature = _sign(proposerPK, _getProposalHashWith());

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoanProposal.AcceptorIsProposer.selector, proposer));
        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function testFuzz_shouldFail_whenProposedRefinancingLoanIdNotZero_whenRefinancingLoanIdZero(uint256 proposedRefinancingLoanId) external {
        vm.assume(proposedRefinancingLoanId != 0);
        params.base.refinancingLoanId = proposedRefinancingLoanId;
        params.refinancingLoanId = 0;
        params.signature = _sign(proposerPK, _getProposalHashWith());

        vm.expectRevert(
            abi.encodeWithSelector(PWNSimpleLoanProposal.InvalidRefinancingLoanId.selector, proposedRefinancingLoanId)
        );
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
        params.signature = _sign(proposerPK, _getProposalHashWith());

        vm.expectRevert(
            abi.encodeWithSelector(PWNSimpleLoanProposal.InvalidRefinancingLoanId.selector, proposedRefinancingLoanId)
        );
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
        params.signature = _sign(proposerPK, _getProposalHashWith());

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
        params.signature = _sign(proposerPK, _getProposalHashWith());

        vm.expectRevert(
            abi.encodeWithSelector(PWNSimpleLoanProposal.InvalidRefinancingLoanId.selector, proposedRefinancingLoanId)
        );
        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function testFuzz_shouldFail_whenProposalExpired(uint256 timestamp) external {
        timestamp = bound(timestamp, params.base.expiration, type(uint256).max);
        vm.warp(timestamp);

        params.signature = _sign(proposerPK, _getProposalHashWith());

        vm.expectRevert(abi.encodeWithSelector(Expired.selector, timestamp, params.base.expiration));
        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function testFuzz_shouldFail_whenOfferNonceNotUsable(uint256 nonceSpace, uint256 nonce) external {
        params.base.nonceSpace = nonceSpace;
        params.base.nonce = nonce;
        params.signature = _sign(proposerPK, _getProposalHashWith());

        vm.mockCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)"),
            abi.encode(false)
        );
        vm.expectCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)", proposer, nonceSpace, nonce)
        );

        vm.expectRevert(abi.encodeWithSelector(PWNRevokedNonce.NonceNotUsable.selector, proposer, nonceSpace, nonce));
        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function testFuzz_shouldFail_whenCallerIsNotAllowedAcceptor(address caller) external {
        address allowedAcceptor = makeAddr("allowedAcceptor");
        vm.assume(caller != allowedAcceptor && caller != proposer);
        params.base.allowedAcceptor = allowedAcceptor;
        params.acceptor = caller;
        params.signature = _sign(proposerPK, _getProposalHashWith());

        vm.expectRevert(
            abi.encodeWithSelector(PWNSimpleLoanProposal.CallerNotAllowedAcceptor.selector, caller, allowedAcceptor)
        );
        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function test_shouldRevokeOffer_whenAvailableCreditLimitEqualToZero(uint256 nonceSpace, uint256 nonce) external {
        params.base.availableCreditLimit = 0;
        params.base.nonceSpace = nonceSpace;
        params.base.nonce = nonce;
        params.signature = _sign(proposerPK, _getProposalHashWith());

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
        params.signature = _sign(proposerPK, _getProposalHashWith());

        vm.store(
            address(proposalContractAddr),
            keccak256(abi.encode(_getProposalHashWith(), CREDIT_USED_SLOT)),
            bytes32(used)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNSimpleLoanProposal.AvailableCreditLimitExceeded.selector, used + params.base.creditAmount, limit
            )
        );
        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function testFuzz_shouldIncreaseUsedCredit_whenUsedCreditNotExceedsAvailableCreditLimit(uint256 used, uint256 limit) external {
        used = bound(used, 1, type(uint256).max - params.base.creditAmount);
        limit = bound(limit, used + params.base.creditAmount, type(uint256).max);

        params.base.availableCreditLimit = limit;
        params.signature = _sign(proposerPK, _getProposalHashWith());

        bytes32 proposalHash = _getProposalHashWith();

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
        params.signature = _sign(proposerPK, _getProposalHashWith());

        vm.expectCall({
            callee: config,
            data: abi.encodeWithSignature("getStateFingerprintComputer(address)"),
            count: 0
        });

        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function test_shouldCallComputerRegistry_whenShouldCheckStateFingerprint() external {
        params.base.checkCollateralStateFingerprint = true;
        params.signature = _sign(proposerPK, _getProposalHashWith());

        vm.expectCall(
            config,
            abi.encodeWithSignature("getStateFingerprintComputer(address)", params.base.collateralAddress)
        );

        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function test_shouldFail_whenComputerRegistryReturnsComputer_whenComputerFails() external {
        params.base.collateralAddress = token;
        params.signature = _sign(proposerPK, _getProposalHashWith());

        vm.mockCallRevert(
            stateFingerprintComputer,
            abi.encodeWithSignature("computeStateFingerprint(address,uint256)"),
            "some error"
        );

        vm.expectRevert("some error");
        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function testFuzz_shouldFail_whenComputerRegistryReturnsComputer_whenComputerReturnsDifferentStateFingerprint(
        bytes32 stateFingerprint
    ) external {
        vm.assume(stateFingerprint != params.base.collateralStateFingerprint);
        params.base.collateralAddress = token;
        params.signature = _sign(proposerPK, _getProposalHashWith());

        vm.mockCall(
            stateFingerprintComputer,
            abi.encodeWithSignature(
                "computeStateFingerprint(address,uint256)",
                params.base.collateralAddress, params.base.collateralId
            ),
            abi.encode(stateFingerprint)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNSimpleLoanProposal.InvalidCollateralStateFingerprint.selector,
                stateFingerprint,
                params.base.collateralStateFingerprint
            )
        );
        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function test_shouldFail_whenNoComputerRegistered_whenAssetDoesNotImplementERC165() external {
        params.base.collateralAddress = token;
        params.signature = _sign(proposerPK, _getProposalHashWith());

        vm.mockCall(
            config,
            abi.encodeWithSignature("getStateFingerprintComputer(address)"),
            abi.encode(address(0))
        );
        vm.mockCallRevert(
            params.base.collateralAddress,
            abi.encodeWithSignature("supportsInterface(bytes4)"),
            abi.encode("not implementing ERC165")
        );

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoanProposal.MissingStateFingerprintComputer.selector));
        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function test_shouldFail_whenNoComputerRegistered_whenAssetDoesNotImplementERC5646() external {
        params.signature = _sign(proposerPK, _getProposalHashWith());

        vm.mockCall(
            config,
            abi.encodeWithSignature("getStateFingerprintComputer(address)"),
            abi.encode(address(0))
        );
        _mockERC5646Support(params.base.collateralAddress, false);

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoanProposal.MissingStateFingerprintComputer.selector));
        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function testFuzz_shouldFail_whenAssetImplementsERC5646_whenComputerReturnsDifferentStateFingerprint(
        bytes32 stateFingerprint
    ) external {
        vm.assume(stateFingerprint != params.base.collateralStateFingerprint);
        params.signature = _sign(proposerPK, _getProposalHashWith());

        vm.mockCall(
            config,
            abi.encodeWithSignature("getStateFingerprintComputer(address)"),
            abi.encode(address(0))
        );
        _mockERC5646Support(params.base.collateralAddress, true);
        vm.mockCall(
            params.base.collateralAddress,
            abi.encodeWithSignature("getStateFingerprint(uint256)"),
            abi.encode(stateFingerprint)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNSimpleLoanProposal.InvalidCollateralStateFingerprint.selector,
                stateFingerprint,
                params.base.collateralStateFingerprint
            )
        );
        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function test_shouldPass_whenComputerReturnsMatchingFingerprint() external {
        params.signature = _sign(proposerPK, _getProposalHashWith());

        vm.mockCall(
            config,
            abi.encodeWithSignature("getStateFingerprintComputer(address)"),
            abi.encode(stateFingerprintComputer)
        );
        vm.mockCall(
            stateFingerprintComputer,
            abi.encodeWithSignature("computeStateFingerprint(address,uint256)"),
            abi.encode(params.base.collateralStateFingerprint)
        );

        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

    function test_shouldPass_whenAssetImplementsERC5646_whenReturnsMatchingFingerprint() external {
        params.signature = _sign(proposerPK, _getProposalHashWith());

        vm.mockCall(
            config,
            abi.encodeWithSignature("getStateFingerprintComputer(address)"),
            abi.encode(address(0))
        );
        _mockERC5646Support(params.base.collateralAddress, true);
        vm.mockCall(
            params.base.collateralAddress,
            abi.encodeWithSignature("getStateFingerprint(uint256)"),
            abi.encode(params.base.collateralStateFingerprint)
        );

        vm.prank(activeLoanContract);
        _callAcceptProposalWith();
    }

}
