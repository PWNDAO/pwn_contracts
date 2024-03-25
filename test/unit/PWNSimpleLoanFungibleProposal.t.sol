// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import { MultiToken } from "MultiToken/MultiToken.sol";

import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import { PWNHubTags } from "@pwn/hub/PWNHubTags.sol";
import { PWNSimpleLoanFungibleProposal, PWNSimpleLoanProposal, PWNSimpleLoan, Permit }
    from "@pwn/loan/terms/simple/proposal/PWNSimpleLoanFungibleProposal.sol";
import "@pwn/PWNErrors.sol";

import {
    PWNSimpleLoanProposalTest,
    PWNSimpleLoanProposal_AcceptProposal_Test,
    PWNSimpleLoanProposal_AcceptProposalAndRevokeCallersNonce_Test,
    PWNSimpleLoanProposal_AcceptRefinanceProposal_Test,
    PWNSimpleLoanProposal_AcceptRefinanceProposalAndRevokeCallersNonce_Test
} from "@pwn-test/unit/PWNSimpleLoanProposal.t.sol";


abstract contract PWNSimpleLoanFungibleProposalTest is PWNSimpleLoanProposalTest {

    PWNSimpleLoanFungibleProposal proposalContract;
    PWNSimpleLoanFungibleProposal.Proposal proposal;
    PWNSimpleLoanFungibleProposal.ProposalValues proposalValues;

    event ProposalMade(bytes32 indexed proposalHash, address indexed proposer, PWNSimpleLoanFungibleProposal.Proposal proposal);

    function setUp() virtual public override {
        super.setUp();

        proposalContract = new PWNSimpleLoanFungibleProposal(hub, revokedNonce, stateFingerprintComputerRegistry);
        proposalContractAddr = PWNSimpleLoanProposal(proposalContract);

        proposal = PWNSimpleLoanFungibleProposal.Proposal({
            collateralCategory: MultiToken.Category.ERC1155,
            collateralAddress: token,
            collateralId: 0,
            minCollateralAmount: 1,
            checkCollateralStateFingerprint: true,
            collateralStateFingerprint: keccak256("some state fingerprint"),
            creditAddress: token,
            creditPerCollateralUnit: 1 * proposalContract.CREDIT_PER_COLLATERAL_UNIT_DENOMINATOR(),
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

        proposalValues = PWNSimpleLoanFungibleProposal.ProposalValues({
            collateralAmount: 1000
        });
    }


    function _proposalHash(PWNSimpleLoanFungibleProposal.Proposal memory _proposal) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            "\x19\x01",
            keccak256(abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("PWNSimpleLoanFungibleProposal"),
                keccak256("1.0"),
                block.chainid,
                proposalContractAddr
            )),
            keccak256(abi.encodePacked(
                keccak256("Proposal(uint8 collateralCategory,address collateralAddress,uint256 collateralId,uint256 minCollateralAmount,bool checkCollateralStateFingerprint,bytes32 collateralStateFingerprint,address creditAddress,uint256 creditPerCollateralUnit,uint256 availableCreditLimit,uint256 fixedInterestAmount,uint40 accruingInterestAPR,uint32 duration,uint40 expiration,address allowedAcceptor,address proposer,bool isOffer,uint256 refinancingLoanId,uint256 nonceSpace,uint256 nonce,address loanContract)"),
                abi.encode(_proposal)
            ))
        ));
    }

    function _updateProposal(Params memory _params) internal {
        proposalValues.collateralAmount = _params.creditAmount;

        proposal.checkCollateralStateFingerprint = _params.checkCollateralStateFingerprint;
        proposal.collateralStateFingerprint = _params.collateralStateFingerprint;
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
        return proposalContract.acceptProposal(proposal, proposalValues, _proposalSignature(params), _permit, "");
    }

    function _callAcceptProposalWith(Params memory _params, Permit memory _permit, uint256 nonceSpace, uint256 nonce) internal override returns (uint256) {
        _updateProposal(_params);
        return proposalContract.acceptProposal(proposal, proposalValues, _proposalSignature(params), _permit, "", nonceSpace, nonce);
    }

    function _callAcceptRefinanceProposalWith(uint256 loanId, Params memory _params, Permit memory _permit) internal override returns (uint256) {
        _updateProposal(_params);
        return proposalContract.acceptRefinanceProposal(loanId, proposal, proposalValues, _proposalSignature(params), _permit, "");
    }

    function _callAcceptRefinanceProposalWith(uint256 loanId, Params memory _params, Permit memory _permit, uint256 nonceSpace, uint256 nonce) internal override returns (uint256) {
        _updateProposal(_params);
        return proposalContract.acceptRefinanceProposal(loanId, proposal, proposalValues, _proposalSignature(params), _permit, "", nonceSpace, nonce);
    }

    function _getProposalHashWith(Params memory _params) internal override returns (bytes32) {
        _updateProposal(_params);
        return _proposalHash(proposal);
    }

}


/*----------------------------------------------------------*|
|*  # CREDIT USED                                           *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanFungibleProposal_CreditUsed_Test is PWNSimpleLoanFungibleProposalTest {

    function testFuzz_shouldReturnUsedCredit(uint256 used) external {
        vm.store(address(proposalContract), keccak256(abi.encode(_proposalHash(proposal), CREDIT_USED_SLOT)), bytes32(used));

        assertEq(proposalContract.creditUsed(_proposalHash(proposal)), used);
    }

}


/*----------------------------------------------------------*|
|*  # REVOKE NONCE                                          *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanFungibleProposal_RevokeNonce_Test is PWNSimpleLoanFungibleProposalTest {

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

contract PWNSimpleLoanFungibleProposal_GetProposalHash_Test is PWNSimpleLoanFungibleProposalTest {

    function test_shouldReturnProposalHash() external {
        assertEq(_proposalHash(proposal), proposalContract.getProposalHash(proposal));
    }

}


/*----------------------------------------------------------*|
|*  # MAKE PROPOSAL                                         *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanFungibleProposal_MakeProposal_Test is PWNSimpleLoanFungibleProposalTest {

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
|*  # GET CREDIT AMOUNT                                     *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanFungibleProposal_GetCreditAmount_Test is PWNSimpleLoanFungibleProposalTest {

    function testFuzz_shouldReturnCreditAmount(uint256 collateralAmount, uint256 creditPerCollateralUnit) external {
        collateralAmount = bound(collateralAmount, 0, 1e70);
        creditPerCollateralUnit = bound(
            creditPerCollateralUnit, 1, collateralAmount == 0 ? type(uint256).max : type(uint256).max / collateralAmount
        );

        assertEq(
            proposalContract.getCreditAmount(collateralAmount, creditPerCollateralUnit),
            Math.mulDiv(collateralAmount, creditPerCollateralUnit, proposalContract.CREDIT_PER_COLLATERAL_UNIT_DENOMINATOR())
        );
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT PROPOSAL                                       *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanFungibleProposal_AcceptProposal_Test is PWNSimpleLoanFungibleProposalTest, PWNSimpleLoanProposal_AcceptProposal_Test {

    function setUp() virtual public override(PWNSimpleLoanFungibleProposalTest, PWNSimpleLoanProposalTest) {
        super.setUp();
    }


    function testFuzz_shouldFail_whenRefinancingLoanIdNotZero(uint256 refinancingLoanId) external {
        vm.assume(refinancingLoanId != 0);
        proposal.refinancingLoanId = refinancingLoanId;

        vm.expectRevert(abi.encodeWithSelector(InvalidRefinancingLoanId.selector, refinancingLoanId));
        proposalContract.acceptProposal(
            proposal, proposalValues, _signProposalHash(proposerPK, _proposalHash(proposal)), permit, ""
        );
    }

    function test_shouldFail_whenZeroMinCollateralAmount() external {
        proposal.minCollateralAmount = 0;

        vm.expectRevert(abi.encodeWithSelector(MinCollateralAmountNotSet.selector));
        proposalContract.acceptProposal(
            proposal, proposalValues, _signProposalHash(proposerPK, _proposalHash(proposal)), permit, ""
        );
    }

    function testFuzz_shouldFail_whenCollateralAmountLessThanMinCollateralAmount(
        uint256 minCollateralAmount, uint256 collateralAmount
    ) external {
        proposal.minCollateralAmount = bound(minCollateralAmount, 1, type(uint256).max);
        proposalValues.collateralAmount = bound(collateralAmount, 0, proposal.minCollateralAmount - 1);

        vm.expectRevert(abi.encodeWithSelector(
            InsufficientCollateralAmount.selector, proposalValues.collateralAmount, proposal.minCollateralAmount
        ));
        proposalContract.acceptProposal(
            proposal, proposalValues, _signProposalHash(proposerPK, _proposalHash(proposal)), permit, ""
        );
    }

    function testFuzz_shouldCallLoanContractWithLoanTerms(
        uint256 collateralAmount, uint256 creditPerCollateralUnit, bool isOffer
    ) external {
        proposalValues.collateralAmount = bound(collateralAmount, proposal.minCollateralAmount, 1e40);
        proposal.creditPerCollateralUnit = bound(creditPerCollateralUnit, 1, type(uint256).max / proposalValues.collateralAmount);
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
                amount: proposalValues.collateralAmount
            }),
            credit: MultiToken.Asset({
                category: MultiToken.Category.ERC20,
                assetAddress: proposal.creditAddress,
                id: 0,
                amount: proposalContract.getCreditAmount(proposalValues.collateralAmount, proposal.creditPerCollateralUnit)
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
            proposal, proposalValues, _signProposalHash(proposerPK, _proposalHash(proposal)), permit, extra
        );
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT PROPOSAL AND REVOKE CALLERS NONCE              *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanFungibleProposal_AcceptProposalAndRevokeCallersNonce_Test is PWNSimpleLoanFungibleProposalTest, PWNSimpleLoanProposal_AcceptProposalAndRevokeCallersNonce_Test {

    function setUp() virtual public override(PWNSimpleLoanFungibleProposalTest, PWNSimpleLoanProposalTest) {
        super.setUp();
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT REFINANCE PROPOSAL                             *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanFungibleProposal_AcceptRefinanceProposal_Test is PWNSimpleLoanFungibleProposalTest, PWNSimpleLoanProposal_AcceptRefinanceProposal_Test {

    function setUp() virtual public override(PWNSimpleLoanFungibleProposalTest, PWNSimpleLoanProposalTest) {
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
            _loanId, proposal, proposalValues, _signProposalHash(proposerPK, _proposalHash(proposal)), permit, extra
        );
    }

    function testFuzz_shouldPass_whenRefinancingLoanIdIsNotEqualToLoanId_whenRefinanceingLoanIdZero_whenOffer(
        uint256 _loanId
    ) external {
        vm.assume(_loanId != 0);
        proposal.refinancingLoanId = 0;
        proposal.isOffer = true;

        proposalContract.acceptRefinanceProposal(
            _loanId, proposal, proposalValues, _signProposalHash(proposerPK, _proposalHash(proposal)), permit, extra
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
            _loanId, proposal, proposalValues, _signProposalHash(proposerPK, _proposalHash(proposal)), permit, extra
        );
    }

    function test_shouldFail_whenZeroMinCollateralAmount() external {
        proposal.minCollateralAmount = 0;

        vm.expectRevert(abi.encodeWithSelector(MinCollateralAmountNotSet.selector));
        proposalContract.acceptRefinanceProposal(
            loanId, proposal, proposalValues, _signProposalHash(proposerPK, _proposalHash(proposal)), permit, ""
        );
    }

    function testFuzz_shouldFail_whenCollateralAmountLessThanMinCollateralAmount(
        uint256 minCollateralAmount, uint256 collateralAmount
    ) external {
        proposal.minCollateralAmount = bound(minCollateralAmount, 1, type(uint256).max);
        proposalValues.collateralAmount = bound(collateralAmount, 0, proposal.minCollateralAmount - 1);

        vm.expectRevert(abi.encodeWithSelector(
            InsufficientCollateralAmount.selector, proposalValues.collateralAmount, proposal.minCollateralAmount
        ));
        proposalContract.acceptRefinanceProposal(
            loanId, proposal, proposalValues, _signProposalHash(proposerPK, _proposalHash(proposal)), permit, ""
        );
    }

    function testFuzz_shouldCallLoanContractWithLoanTerms(
        uint256 collateralAmount, uint256 creditPerCollateralUnit, bool isOffer
    ) external {
        proposalValues.collateralAmount = bound(collateralAmount, proposal.minCollateralAmount, 1e40);
        proposal.creditPerCollateralUnit = bound(creditPerCollateralUnit, 1, type(uint256).max / proposalValues.collateralAmount);
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
                amount: proposalValues.collateralAmount
            }),
            credit: MultiToken.Asset({
                category: MultiToken.Category.ERC20,
                assetAddress: proposal.creditAddress,
                id: 0,
                amount: proposalContract.getCreditAmount(proposalValues.collateralAmount, proposal.creditPerCollateralUnit)
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
            loanId, proposal, proposalValues, _signProposalHash(proposerPK, _proposalHash(proposal)), permit, extra
        );
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT REFINANCE PROPOSAL AND REVOKE CALLERS NONCE    *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanFungibleProposal_AcceptRefinanceProposalAndRevokeCallersNonce_Test is PWNSimpleLoanFungibleProposalTest, PWNSimpleLoanProposal_AcceptRefinanceProposalAndRevokeCallersNonce_Test {

    function setUp() virtual public override(PWNSimpleLoanFungibleProposalTest, PWNSimpleLoanProposalTest) {
        super.setUp();
    }

}
