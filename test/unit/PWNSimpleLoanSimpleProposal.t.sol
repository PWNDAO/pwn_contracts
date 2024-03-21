// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import { MultiToken } from "MultiToken/MultiToken.sol";

import { PWNHubTags } from "@pwn/hub/PWNHubTags.sol";
import { PWNSimpleLoanSimpleProposal, PWNSimpleLoanProposal, PWNSimpleLoan, Permit }
    from "@pwn/loan/terms/simple/proposal/PWNSimpleLoanSimpleProposal.sol";
import "@pwn/PWNErrors.sol";

import {
    PWNSimpleLoanProposalTest,
    PWNSimpleLoanProposal_AcceptProposal_Test,
    PWNSimpleLoanProposal_AcceptProposalAndRevokeCallersNonce_Test,
    PWNSimpleLoanProposal_AcceptRefinanceProposal_Test,
    PWNSimpleLoanProposal_AcceptRefinanceProposalAndRevokeCallersNonce_Test
} from "@pwn-test/unit/PWNSimpleLoanProposal.t.sol";


abstract contract PWNSimpleLoanSimpleProposalTest is PWNSimpleLoanProposalTest {

    PWNSimpleLoanSimpleProposal proposalContract;
    PWNSimpleLoanSimpleProposal.Proposal proposal;

    event ProposalMade(bytes32 indexed proposalHash, address indexed proposer, PWNSimpleLoanSimpleProposal.Proposal proposal);

    function setUp() virtual public override {
        super.setUp();

        proposalContract = new PWNSimpleLoanSimpleProposal(hub, revokedNonce, stateFingerprintComputerRegistry);
        proposalContractAddr = PWNSimpleLoanProposal(proposalContract);

        proposal = PWNSimpleLoanSimpleProposal.Proposal({
            collateralCategory: MultiToken.Category.ERC1155,
            collateralAddress: token,
            collateralId: 0,
            collateralAmount: 1,
            checkCollateralStateFingerprint: true,
            collateralStateFingerprint: keccak256("some state fingerprint"),
            creditAddress: token,
            creditAmount: 10000,
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
    }


    function _proposalHash(PWNSimpleLoanSimpleProposal.Proposal memory _proposal) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            "\x19\x01",
            keccak256(abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("PWNSimpleLoanSimpleProposal"),
                keccak256("1.2"),
                block.chainid,
                proposalContractAddr
            )),
            keccak256(abi.encodePacked(
                keccak256("Proposal(uint8 collateralCategory,address collateralAddress,uint256 collateralId,uint256 collateralAmount,bool checkCollateralStateFingerprint,bytes32 collateralStateFingerprint,address creditAddress,uint256 creditAmount,uint256 availableCreditLimit,uint256 fixedInterestAmount,uint40 accruingInterestAPR,uint32 duration,uint40 expiration,address allowedAcceptor,address proposer,bool isOffer,uint256 refinancingLoanId,uint256 nonceSpace,uint256 nonce,address loanContract)"),
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
        return proposalContract.acceptProposal(proposal, _proposalSignature(params), _permit, "");
    }

    function _callAcceptProposalWith(Params memory _params, Permit memory _permit, uint256 nonceSpace, uint256 nonce) internal override returns (uint256) {
        _updateProposal(_params);
        return proposalContract.acceptProposal(proposal, _proposalSignature(params), _permit, "", nonceSpace, nonce);
    }

    function _callAcceptRefinanceProposalWith(uint256 loanId, Params memory _params, Permit memory _permit) internal override returns (uint256) {
        _updateProposal(_params);
        return proposalContract.acceptRefinanceProposal(loanId, proposal, _proposalSignature(params), _permit, "");
    }

    function _callAcceptRefinanceProposalWith(uint256 loanId, Params memory _params, Permit memory _permit, uint256 nonceSpace, uint256 nonce) internal override returns (uint256) {
        _updateProposal(_params);
        return proposalContract.acceptRefinanceProposal(loanId, proposal, _proposalSignature(params), _permit, "", nonceSpace, nonce);
    }

    function _getProposalHashWith(Params memory _params) internal override returns (bytes32) {
        _updateProposal(_params);
        return _proposalHash(proposal);
    }

}


/*----------------------------------------------------------*|
|*  # CREDIT USED                                           *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanSimpleProposal_CreditUsed_Test is PWNSimpleLoanSimpleProposalTest {

    function testFuzz_shouldReturnUsedCredit(uint256 used) external {
        vm.store(address(proposalContract), keccak256(abi.encode(_proposalHash(proposal), CREDIT_USED_SLOT)), bytes32(used));

        assertEq(proposalContract.creditUsed(_proposalHash(proposal)), used);
    }

}


/*----------------------------------------------------------*|
|*  # REVOKE NONCE                                          *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanSimpleProposal_RevokeNonce_Test is PWNSimpleLoanSimpleProposalTest {

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

contract PWNSimpleLoanSimpleProposal_GetProposalHash_Test is PWNSimpleLoanSimpleProposalTest {

    function test_shouldReturnOfferHash() external {
        assertEq(_proposalHash(proposal), proposalContract.getProposalHash(proposal));
    }

}


/*----------------------------------------------------------*|
|*  # MAKE PROPOSAL                                         *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanSimpleProposal_MakeProposal_Test is PWNSimpleLoanSimpleProposalTest {

    function testFuzz_shouldFail_whenCallerIsNotProposer(address caller) external {
        vm.assume(caller != proposal.proposer);

        vm.expectRevert(abi.encodeWithSelector(CallerIsNotStatedProposer.selector, proposal.proposer));
        vm.prank(caller);
        proposalContract.makeProposal(proposal);
    }

    function test_shouldEmit_OfferMade() external {
        vm.expectEmit();
        emit ProposalMade(_proposalHash(proposal), proposal.proposer, proposal);

        vm.prank(proposal.proposer);
        proposalContract.makeProposal(proposal);
    }

    function test_shouldMakeOffer() external {
        vm.prank(proposal.proposer);
        proposalContract.makeProposal(proposal);

        assertTrue(proposalContract.proposalsMade(_proposalHash(proposal)));
    }

    function test_shouldReturnOfferHash() external {
        vm.prank(proposal.proposer);
        assertEq(proposalContract.makeProposal(proposal), _proposalHash(proposal));
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT PROPOSAL                                       *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanSimpleProposal_AcceptProposal_Test is PWNSimpleLoanSimpleProposalTest, PWNSimpleLoanProposal_AcceptProposal_Test {

    function setUp() virtual public override(PWNSimpleLoanSimpleProposalTest, PWNSimpleLoanProposalTest) {
        super.setUp();
    }


    function testFuzz_shouldFail_whenRefinancingLoanIdNotZero(uint256 refinancingLoanId) external {
        vm.assume(refinancingLoanId != 0);
        proposal.refinancingLoanId = refinancingLoanId;

        vm.expectRevert(abi.encodeWithSelector(InvalidRefinancingLoanId.selector, refinancingLoanId));
        proposalContract.acceptProposal(
            proposal, _signProposalHash(proposerPK, _proposalHash(proposal)), permit, ""
        );
    }

    function testFuzz_shouldCallLoanContractWithLoanTerms(bool isOffer) external {
        proposal.isOffer = isOffer;

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
                id: proposal.collateralId,
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
            abi.encodeWithSelector(
                PWNSimpleLoan.createLOAN.selector,
                _proposalHash(proposal), loanTerms, permit, extra
            )
        );

        vm.prank(acceptor);
        proposalContract.acceptProposal(
            proposal, _signProposalHash(proposerPK, _proposalHash(proposal)), permit, extra
        );
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT PROPOSAL AND REVOKE CALLERS NONCE              *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanSimpleProposal_AcceptProposalAndRevokeCallersNonce_Test is PWNSimpleLoanSimpleProposalTest, PWNSimpleLoanProposal_AcceptProposalAndRevokeCallersNonce_Test {

    function setUp() virtual public override(PWNSimpleLoanSimpleProposalTest, PWNSimpleLoanProposalTest) {
        super.setUp();
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT REFINANCE PROPOSAL                             *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanSimpleProposal_AcceptRefinanceProposal_Test is PWNSimpleLoanSimpleProposalTest, PWNSimpleLoanProposal_AcceptRefinanceProposal_Test {

    function setUp() virtual public override(PWNSimpleLoanSimpleProposalTest, PWNSimpleLoanProposalTest) {
        super.setUp();

        proposal.refinancingLoanId = loanId;
    }


    function testFuzz_shouldFail_whenRefinancingLoanIdIsNotEqualToLoanId_whenRefinanceingLoanIdNotZero_whenOffer(
        uint256 _loanId, uint256 _refinancingLoanId
    ) external {
        vm.assume(_refinancingLoanId != 0);
        vm.assume(_loanId != _refinancingLoanId);
        proposal.refinancingLoanId = _refinancingLoanId;
        proposal.isOffer = true;

        vm.expectRevert(abi.encodeWithSelector(InvalidRefinancingLoanId.selector, _refinancingLoanId));
        proposalContract.acceptRefinanceProposal(
            _loanId, proposal, _signProposalHash(proposerPK, _proposalHash(proposal)), permit, extra
        );
    }

    function testFuzz_shouldPass_whenRefinancingLoanIdIsNotEqualToLoanId_whenRefinanceingLoanIdZero_whenOffer(
        uint256 _loanId
    ) external {
        vm.assume(_loanId != 0);
        proposal.refinancingLoanId = 0;
        proposal.isOffer = true;

        proposalContract.acceptRefinanceProposal(
            _loanId, proposal, _signProposalHash(proposerPK, _proposalHash(proposal)), permit, extra
        );
    }

    function testFuzz_shouldFail_whenRefinancingLoanIdIsNotEqualToLoanId_whenNotOffer(
        uint256 _loanId, uint256 _refinancingLoanId
    ) external {
        vm.assume(_loanId != _refinancingLoanId);
        proposal.refinancingLoanId = _refinancingLoanId;
        proposal.isOffer = false;

        vm.expectRevert(abi.encodeWithSelector(InvalidRefinancingLoanId.selector, _refinancingLoanId));
        proposalContract.acceptRefinanceProposal(
            _loanId, proposal, _signProposalHash(proposerPK, _proposalHash(proposal)), permit, extra
        );
    }

    function testFuzz_shouldCallLoanContractWithLoanTerms(bool isOffer) external {
        proposal.isOffer = isOffer;

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
                id: proposal.collateralId,
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
            abi.encodeWithSelector(
                PWNSimpleLoan.refinanceLOAN.selector,
                loanId, _proposalHash(proposal), loanTerms, permit, extra
            )
        );

        vm.prank(acceptor);
        proposalContract.acceptRefinanceProposal(
            loanId, proposal, _signProposalHash(proposerPK, _proposalHash(proposal)), permit, extra
        );
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT REFINANCE PROPOSAL AND REVOKE CALLERS NONCE    *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanSimpleProposal_AcceptRefinanceProposalAndRevokeCallersNonce_Test is PWNSimpleLoanSimpleProposalTest, PWNSimpleLoanProposal_AcceptRefinanceProposalAndRevokeCallersNonce_Test {

    function setUp() virtual public override(PWNSimpleLoanSimpleProposalTest, PWNSimpleLoanProposalTest) {
        super.setUp();
    }

}
