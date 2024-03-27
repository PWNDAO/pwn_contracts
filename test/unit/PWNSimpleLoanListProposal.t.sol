// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import { MultiToken } from "MultiToken/MultiToken.sol";

import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import { PWNHubTags } from "@pwn/hub/PWNHubTags.sol";
import { PWNSimpleLoanListProposal, PWNSimpleLoanProposal, PWNSimpleLoan, Permit }
    from "@pwn/loan/terms/simple/proposal/PWNSimpleLoanListProposal.sol";
import "@pwn/PWNErrors.sol";

import {
    PWNSimpleLoanProposalTest,
    PWNSimpleLoanProposal_AcceptProposal_Test,
    PWNSimpleLoanProposal_AcceptProposalAndRevokeCallersNonce_Test
} from "@pwn-test/unit/PWNSimpleLoanProposal.t.sol";


abstract contract PWNSimpleLoanListProposalTest is PWNSimpleLoanProposalTest {

    PWNSimpleLoanListProposal proposalContract;
    PWNSimpleLoanListProposal.Proposal proposal;
    PWNSimpleLoanListProposal.ProposalValues proposalValues;

    event ProposalMade(bytes32 indexed proposalHash, address indexed proposer, PWNSimpleLoanListProposal.Proposal proposal);

    function setUp() virtual public override {
        super.setUp();

        proposalContract = new PWNSimpleLoanListProposal(hub, revokedNonce, config);
        proposalContractAddr = PWNSimpleLoanProposal(proposalContract);

        proposal = PWNSimpleLoanListProposal.Proposal({
            collateralCategory: MultiToken.Category.ERC721,
            collateralAddress: token,
            collateralIdsWhitelistMerkleRoot: bytes32(0),
            collateralAmount: 1032,
            checkCollateralStateFingerprint: true,
            collateralStateFingerprint: keccak256("some state fingerprint"),
            creditAddress: token,
            creditAmount: 1101001,
            availableCreditLimit: 0,
            fixedInterestAmount: 1,
            accruingInterestAPR: 0,
            duration: 1000,
            expiration: 60303,
            allowedAcceptor: address(0),
            proposer: proposer,
            isOffer: true,
            refinancingLoanId: 0,
            nonceSpace: 1,
            nonce: uint256(keccak256("nonce_1")),
            loanContract: activeLoanContract
        });

        proposalValues = PWNSimpleLoanListProposal.ProposalValues({
            collateralId: 32,
            merkleInclusionProof: new bytes32[](0)
        });
    }


    function _proposalHash(PWNSimpleLoanListProposal.Proposal memory _proposal) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            "\x19\x01",
            keccak256(abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("PWNSimpleLoanListProposal"),
                keccak256("1.2"),
                block.chainid,
                proposalContractAddr
            )),
            keccak256(abi.encodePacked(
                keccak256("Proposal(uint8 collateralCategory,address collateralAddress,bytes32 collateralIdsWhitelistMerkleRoot,uint256 collateralAmount,bool checkCollateralStateFingerprint,bytes32 collateralStateFingerprint,address creditAddress,uint256 creditAmount,uint256 availableCreditLimit,uint256 fixedInterestAmount,uint40 accruingInterestAPR,uint32 duration,uint40 expiration,address allowedAcceptor,address proposer,bool isOffer,uint256 refinancingLoanId,uint256 nonceSpace,uint256 nonce,address loanContract)"),
                abi.encode(_proposal)
            ))
        ));
    }

    function _updateProposal(Params memory _params) internal {
        proposal.checkCollateralStateFingerprint = _params.checkCollateralStateFingerprint;
        proposal.collateralStateFingerprint = _params.collateralStateFingerprint;
        proposal.creditAmount = _params.creditAmount;
        proposal.availableCreditLimit = _params.availableCreditLimit;
        proposal.duration = _params.duration;
        proposal.accruingInterestAPR = _params.accruingInterestAPR;
        proposal.expiration = _params.expiration;
        proposal.allowedAcceptor = _params.allowedAcceptor;
        proposal.proposer = _params.proposer;
        proposal.loanContract = _params.loanContract;
        proposal.nonceSpace = _params.nonceSpace;
        proposal.nonce = _params.nonce;
    }

    function _proposalSignature(Params memory _params) internal view returns (bytes memory signature) {
        if (_params.signerPK != 0) {
            if (_params.compactSignature) {
                signature = _signProposalHashCompact(_params.signerPK, _proposalHash(proposal));
            } else {
                signature = _signProposalHash(_params.signerPK, _proposalHash(proposal));
            }
        }
    }


    function _callAcceptProposalWith(Params memory _params, Permit memory _permit) internal override returns (uint256) {
        _updateProposal(_params);
        return proposalContract.acceptProposal(proposal, proposalValues, _proposalSignature(params), 0, _permit, "");
    }

    function _callAcceptProposalWith(Params memory _params, Permit memory _permit, uint256 nonceSpace, uint256 nonce) internal override returns (uint256) {
        _updateProposal(_params);
        return proposalContract.acceptProposal(proposal, proposalValues, _proposalSignature(params), 0, _permit, "", nonceSpace, nonce);
    }

    function _getProposalHashWith(Params memory _params) internal override returns (bytes32) {
        _updateProposal(_params);
        return _proposalHash(proposal);
    }

}


/*----------------------------------------------------------*|
|*  # CREDIT USED                                           *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanListProposal_CreditUsed_Test is PWNSimpleLoanListProposalTest {

    function testFuzz_shouldReturnUsedCredit(uint256 used) external {
        vm.store(address(proposalContract), keccak256(abi.encode(_proposalHash(proposal), CREDIT_USED_SLOT)), bytes32(used));

        assertEq(proposalContract.creditUsed(_proposalHash(proposal)), used);
    }

}


/*----------------------------------------------------------*|
|*  # REVOKE NONCE                                          *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanListProposal_RevokeNonce_Test is PWNSimpleLoanListProposalTest {

    function testFuzz_shouldCallRevokeNonce(address caller, uint256 nonceSpace, uint256 nonce) external {
        vm.expectCall(
            revokedNonce,
            abi.encodeWithSignature("revokeNonce(address,uint256,uint256)", caller, nonceSpace, nonce)
        );

        vm.prank(caller);
        proposalContract.revokeNonce(nonceSpace, nonce);
    }

}


/*----------------------------------------------------------*|
|*  # GET PROPOSAL HASH                                     *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanListProposal_GetProposalHash_Test is PWNSimpleLoanListProposalTest {

    function test_shouldReturnProposalHash() external {
        assertEq(_proposalHash(proposal), proposalContract.getProposalHash(proposal));
    }

}


/*----------------------------------------------------------*|
|*  # MAKE PROPOSAL                                         *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanListProposal_MakeProposal_Test is PWNSimpleLoanListProposalTest {

    function testFuzz_shouldFail_whenCallerIsNotProposer(address caller) external {
        vm.assume(caller != proposal.proposer);

        vm.expectRevert(abi.encodeWithSelector(CallerIsNotStatedProposer.selector, proposal.proposer));
        vm.prank(caller);
        proposalContract.makeProposal(proposal);
    }

    function test_shouldEmit_ProposalMade() external {
        vm.expectEmit();
        emit ProposalMade(_proposalHash(proposal), proposal.proposer, proposal);

        vm.prank(proposal.proposer);
        proposalContract.makeProposal(proposal);
    }

    function test_shouldMakeProposal() external {
        vm.prank(proposal.proposer);
        proposalContract.makeProposal(proposal);

        assertTrue(proposalContract.proposalsMade(_proposalHash(proposal)));
    }

    function test_shouldReturnProposalHash() external {
        vm.prank(proposal.proposer);
        assertEq(proposalContract.makeProposal(proposal), _proposalHash(proposal));
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT PROPOSAL AND REVOKE CALLERS NONCE              *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanListProposal_AcceptProposalAndRevokeCallersNonce_Test is PWNSimpleLoanListProposalTest, PWNSimpleLoanProposal_AcceptProposalAndRevokeCallersNonce_Test {

    function setUp() virtual public override(PWNSimpleLoanListProposalTest, PWNSimpleLoanProposalTest) {
        super.setUp();
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT PROPOSAL                                       *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanListProposal_AcceptProposal_Test is PWNSimpleLoanListProposalTest, PWNSimpleLoanProposal_AcceptProposal_Test {

    function setUp() virtual public override(PWNSimpleLoanListProposalTest, PWNSimpleLoanProposalTest) {
        super.setUp();
    }


    function testFuzz_shouldFail_whenProposedRefinancingLoanIdNotZero_whenRefinancingLoanIdZero(uint256 proposedRefinancingLoanId) external {
        vm.assume(proposedRefinancingLoanId != 0);
        proposal.refinancingLoanId = proposedRefinancingLoanId;

        vm.expectRevert(abi.encodeWithSelector(InvalidRefinancingLoanId.selector, proposedRefinancingLoanId));
        proposalContract.acceptProposal(
            proposal, proposalValues, _signProposalHash(proposerPK, _proposalHash(proposal)), 0, permit, ""
        );
    }

    function testFuzz_shouldFail_whenRefinancingLoanIdsIsNotEqual_whenProposedRefinanceingLoanIdNotZero_whenRefinancingLoanIdNotZero_whenOffer(
        uint256 refinancingLoanId, uint256 proposedRefinancingLoanId
    ) external {
        vm.assume(proposedRefinancingLoanId != 0);
        vm.assume(refinancingLoanId != proposedRefinancingLoanId);
        proposal.refinancingLoanId = proposedRefinancingLoanId;
        proposal.isOffer = true;

        vm.expectRevert(abi.encodeWithSelector(InvalidRefinancingLoanId.selector, proposedRefinancingLoanId));
        proposalContract.acceptProposal(
            proposal, proposalValues, _signProposalHash(proposerPK, _proposalHash(proposal)), refinancingLoanId, permit, extra
        );
    }

    function testFuzz_shouldPass_whenRefinancingLoanIdsNotEqual_whenProposedRefinanceingLoanIdZero_whenRefinancingLoanIdNotZero_whenOffer(
        uint256 refinancingLoanId
    ) external {
        vm.assume(refinancingLoanId != 0);
        proposal.refinancingLoanId = 0;
        proposal.isOffer = true;

        proposalContract.acceptProposal(
            proposal, proposalValues, _signProposalHash(proposerPK, _proposalHash(proposal)), refinancingLoanId, permit, extra
        );
    }

    function testFuzz_shouldFail_whenRefinancingLoanIdsNotEqual_whenRefinancingLoanIdNotZero_whenRequest(
        uint256 refinancingLoanId, uint256 proposedRefinancingLoanId
    ) external {
        vm.assume(refinancingLoanId != proposedRefinancingLoanId);
        proposal.refinancingLoanId = proposedRefinancingLoanId;
        proposal.isOffer = false;

        vm.expectRevert(abi.encodeWithSelector(InvalidRefinancingLoanId.selector, proposedRefinancingLoanId));
        proposalContract.acceptProposal(
            proposal, proposalValues, _signProposalHash(proposerPK, _proposalHash(proposal)), refinancingLoanId, permit, extra
        );
    }

    function test_shouldAcceptAnyCollateralId_whenMerkleRootIsZero() external {
        proposalValues.collateralId = 331;
        proposal.collateralIdsWhitelistMerkleRoot = bytes32(0);

        proposalContract.acceptProposal(
            proposal, proposalValues, _signProposalHash(proposerPK, _proposalHash(proposal)), 0, permit, ""
        );
    }

    function test_shouldPass_whenGivenCollateralIdIsWhitelisted() external {
        bytes32 id1Hash = keccak256(abi.encodePacked(uint256(331)));
        bytes32 id2Hash = keccak256(abi.encodePacked(uint256(133)));
        proposal.collateralIdsWhitelistMerkleRoot = keccak256(abi.encodePacked(id1Hash, id2Hash));

        proposalValues.collateralId = 331;
        proposalValues.merkleInclusionProof = new bytes32[](1);
        proposalValues.merkleInclusionProof[0] = id2Hash;

        proposalContract.acceptProposal(
            proposal, proposalValues, _signProposalHash(proposerPK, _proposalHash(proposal)), 0, permit, ""
        );
    }

    function test_shouldFail_whenGivenCollateralIdIsNotWhitelisted() external {
        bytes32 id1Hash = keccak256(abi.encodePacked(uint256(331)));
        bytes32 id2Hash = keccak256(abi.encodePacked(uint256(133)));
        proposal.collateralIdsWhitelistMerkleRoot = keccak256(abi.encodePacked(id1Hash, id2Hash));

        proposalValues.collateralId = 333;
        proposalValues.merkleInclusionProof = new bytes32[](1);
        proposalValues.merkleInclusionProof[0] = id2Hash;

        vm.expectRevert(abi.encodeWithSelector(CollateralIdNotWhitelisted.selector, proposalValues.collateralId));
        proposalContract.acceptProposal(
            proposal, proposalValues, _signProposalHash(proposerPK, _proposalHash(proposal)), 0, permit, ""
        );
    }

    function testFuzz_shouldCallLoanContractWithLoanTerms(bool isOffer, uint256 refinancingLoanId) external {
        proposal.isOffer = isOffer;
        proposal.refinancingLoanId = refinancingLoanId;

        permit = Permit({
            asset: token,
            owner: acceptor,
            amount: 100,
            deadline: 1000,
            v: 27,
            r: bytes32(uint256(1)),
            s: bytes32(uint256(2))
        });
        extra = "lil extra";

        PWNSimpleLoan.Terms memory loanTerms = PWNSimpleLoan.Terms({
            lender: isOffer ? proposal.proposer : acceptor,
            borrower: isOffer ? acceptor : proposal.proposer,
            duration: proposal.duration,
            collateral: MultiToken.Asset({
                category: proposal.collateralCategory,
                assetAddress: proposal.collateralAddress,
                id: proposalValues.collateralId,
                amount: proposal.collateralAmount
            }),
            credit: MultiToken.Asset({
                category: MultiToken.Category.ERC20,
                assetAddress: proposal.creditAddress,
                id: 0,
                amount: proposal.creditAmount
            }),
            fixedInterestAmount: proposal.fixedInterestAmount,
            accruingInterestAPR: proposal.accruingInterestAPR
        });

        vm.expectCall(
            activeLoanContract,
            refinancingLoanId == 0
            ? abi.encodeWithSelector(
                PWNSimpleLoan.createLOAN.selector, _proposalHash(proposal), loanTerms, permit, extra
            )
            : abi.encodeWithSelector(
                PWNSimpleLoan.refinanceLOAN.selector, refinancingLoanId, _proposalHash(proposal), loanTerms, permit, extra
            )
        );

        vm.prank(acceptor);
        proposalContract.acceptProposal(
            proposal, proposalValues, _signProposalHash(proposerPK, _proposalHash(proposal)), refinancingLoanId, permit, extra
        );
    }

}
