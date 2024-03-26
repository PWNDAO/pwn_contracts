// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import { MultiToken } from "MultiToken/MultiToken.sol";

import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import { PWNHubTags } from "@pwn/hub/PWNHubTags.sol";
import { PWNSimpleLoanDutchAuctionProposal, PWNSimpleLoanProposal, PWNSimpleLoan, Permit }
    from "@pwn/loan/terms/simple/proposal/PWNSimpleLoanDutchAuctionProposal.sol";
import "@pwn/PWNErrors.sol";

import {
    PWNSimpleLoanProposalTest,
    PWNSimpleLoanProposal_AcceptProposal_Test,
    PWNSimpleLoanProposal_AcceptProposalAndRevokeCallersNonce_Test,
    PWNSimpleLoanProposal_AcceptRefinanceProposal_Test,
    PWNSimpleLoanProposal_AcceptRefinanceProposalAndRevokeCallersNonce_Test
} from "@pwn-test/unit/PWNSimpleLoanProposal.t.sol";


abstract contract PWNSimpleLoanDutchAuctionProposalTest is PWNSimpleLoanProposalTest {

    PWNSimpleLoanDutchAuctionProposal proposalContract;
    PWNSimpleLoanDutchAuctionProposal.Proposal proposal;
    PWNSimpleLoanDutchAuctionProposal.ProposalValues proposalValues;

    event ProposalMade(bytes32 indexed proposalHash, address indexed proposer, PWNSimpleLoanDutchAuctionProposal.Proposal proposal);

    function setUp() virtual public override {
        super.setUp();

        proposalContract = new PWNSimpleLoanDutchAuctionProposal(hub, revokedNonce, config);
        proposalContractAddr = PWNSimpleLoanProposal(proposalContract);

        proposal = PWNSimpleLoanDutchAuctionProposal.Proposal({
            collateralCategory: MultiToken.Category.ERC1155,
            collateralAddress: token,
            collateralId: 0,
            collateralAmount: 1,
            checkCollateralStateFingerprint: true,
            collateralStateFingerprint: keccak256("some state fingerprint"),
            creditAddress: token,
            minCreditAmount: 10000,
            maxCreditAmount: 100000,
            availableCreditLimit: 0,
            fixedInterestAmount: 1,
            accruingInterestAPR: 0,
            duration: 1000,
            auctionStart: 1,
            auctionDuration: 1 minutes,
            allowedAcceptor: address(0),
            proposer: proposer,
            isOffer: true,
            refinancingLoanId: 0,
            nonceSpace: 1,
            nonce: uint256(keccak256("nonce_1")),
            loanContract: activeLoanContract
        });

        proposalValues = PWNSimpleLoanDutchAuctionProposal.ProposalValues({
            intendedCreditAmount: 10000,
            slippage: 0
        });
    }


    function _proposalHash(PWNSimpleLoanDutchAuctionProposal.Proposal memory _proposal) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            "\x19\x01",
            keccak256(abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("PWNSimpleLoanDutchAuctionProposal"),
                keccak256("1.0"),
                block.chainid,
                proposalContractAddr
            )),
            keccak256(abi.encodePacked(
                keccak256("Proposal(uint8 collateralCategory,address collateralAddress,uint256 collateralId,uint256 collateralAmount,bool checkCollateralStateFingerprint,bytes32 collateralStateFingerprint,address creditAddress,uint256 minCreditAmount,uint256 maxCreditAmount,uint256 availableCreditLimit,uint256 fixedInterestAmount,uint40 accruingInterestAPR,uint32 duration,uint40 auctionStart,uint40 auctionDuration,address allowedAcceptor,address proposer,bool isOffer,uint256 refinancingLoanId,uint256 nonceSpace,uint256 nonce,address loanContract)"),
                abi.encode(_proposal)
            ))
        ));
    }

    function _updateProposal(Params memory _params) internal {
        proposal.checkCollateralStateFingerprint = _params.checkCollateralStateFingerprint;
        proposal.collateralStateFingerprint = _params.collateralStateFingerprint;
        if (proposal.isOffer) {
            proposal.minCreditAmount = _params.creditAmount;
            proposal.maxCreditAmount = proposal.minCreditAmount + 1000;
            proposalValues.intendedCreditAmount = proposal.minCreditAmount;
        } else {
            proposal.maxCreditAmount = _params.creditAmount;
            proposal.minCreditAmount = proposal.maxCreditAmount - 1000;
            proposalValues.intendedCreditAmount = proposal.maxCreditAmount;
        }
        proposal.availableCreditLimit = _params.availableCreditLimit;
        proposal.duration = _params.duration;
        proposal.accruingInterestAPR = _params.accruingInterestAPR;
        proposal.auctionDuration = _params.expiration - proposal.auctionStart - 1 minutes;
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

contract PWNSimpleLoanDutchAuctionProposal_CreditUsed_Test is PWNSimpleLoanDutchAuctionProposalTest {

    function testFuzz_shouldReturnUsedCredit(uint256 used) external {
        vm.store(address(proposalContract), keccak256(abi.encode(_proposalHash(proposal), CREDIT_USED_SLOT)), bytes32(used));

        assertEq(proposalContract.creditUsed(_proposalHash(proposal)), used);
    }

}


/*----------------------------------------------------------*|
|*  # REVOKE NONCE                                          *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanDutchAuctionProposal_RevokeNonce_Test is PWNSimpleLoanDutchAuctionProposalTest {

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

contract PWNSimpleLoanDutchAuctionProposal_GetProposalHash_Test is PWNSimpleLoanDutchAuctionProposalTest {

    function test_shouldReturnProposalHash() external {
        assertEq(_proposalHash(proposal), proposalContract.getProposalHash(proposal));
    }

}


/*----------------------------------------------------------*|
|*  # MAKE PROPOSAL                                         *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanDutchAuctionProposal_MakeProposal_Test is PWNSimpleLoanDutchAuctionProposalTest {

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

contract PWNSimpleLoanDutchAuctionProposal_GetCreditAmount_Test is PWNSimpleLoanDutchAuctionProposalTest {

    function testFuzz_shouldFail_whenInvalidAuctionDuration(uint40 auctionDuration) external {
        vm.assume(auctionDuration < 1 minutes);
        proposal.auctionDuration = auctionDuration;

        vm.expectRevert(abi.encodeWithSelector(InvalidAuctionDuration.selector, auctionDuration, 1 minutes));
        proposalContract.acceptProposal(
            proposal, proposalValues, _signProposalHash(proposerPK, _proposalHash(proposal)), permit, ""
        );
    }

    function testFuzz_shouldFail_whenAuctionDurationNotInFullMinutes(uint40 auctionDuration) external {
        vm.assume(auctionDuration > 1 minutes && auctionDuration % 1 minutes > 0);
        proposal.auctionDuration = auctionDuration;

        vm.expectRevert(abi.encodeWithSelector(AuctionDurationNotInFullMinutes.selector, auctionDuration));
        proposalContract.acceptProposal(
            proposal, proposalValues, _signProposalHash(proposerPK, _proposalHash(proposal)), permit, ""
        );
    }

    function testFuzz_shouldFail_whenInvalidCreditAmountRange(uint256 minCreditAmount, uint256 maxCreditAmount) external {
        vm.assume(minCreditAmount >= maxCreditAmount);
        proposal.minCreditAmount = minCreditAmount;
        proposal.maxCreditAmount = maxCreditAmount;

        vm.expectRevert(abi.encodeWithSelector(InvalidCreditAmountRange.selector, minCreditAmount, maxCreditAmount));
        proposalContract.acceptProposal(
            proposal, proposalValues, _signProposalHash(proposerPK, _proposalHash(proposal)), permit, ""
        );
    }

    function testFuzz_shouldFail_whenAuctionNotInProgress(uint40 auctionStart, uint256 time) external {
        auctionStart = uint40(bound(auctionStart, 1, type(uint40).max));
        time = bound(time, 0, auctionStart - 1);

        proposal.auctionStart = auctionStart;

        vm.expectRevert(abi.encodeWithSelector(AuctionNotInProgress.selector, time, auctionStart));
        proposalContract.getCreditAmount(proposal, time);
    }

    function testFuzz_shouldFail_whenProposalExpired(uint40 auctionDuration, uint256 time) external {
        auctionDuration = uint40(bound(auctionDuration, 1, (type(uint40).max / 1 minutes) - 2)) * 1 minutes;
        time = bound(time, auctionDuration + 1 minutes + 1, type(uint40).max);

        proposal.auctionStart = 0;
        proposal.auctionDuration = auctionDuration;

        vm.expectRevert(abi.encodeWithSelector(Expired.selector, time, auctionDuration + 1 minutes));
        proposalContract.getCreditAmount(proposal, time);
    }

    function testFuzz_shouldReturnCorrectEdgeValues(uint40 auctionDuration) external {
        proposal.auctionStart = 0;
        proposal.auctionDuration = uint40(bound(auctionDuration, 1, type(uint40).max / 1 minutes)) * 1 minutes;

        proposal.isOffer = true;
        assertEq(proposalContract.getCreditAmount(proposal, proposal.auctionStart), proposal.minCreditAmount);
        assertEq(proposalContract.getCreditAmount(proposal, proposal.auctionDuration), proposal.maxCreditAmount);
        assertEq(proposalContract.getCreditAmount(proposal, proposal.auctionDuration + 59), proposal.maxCreditAmount);

        proposal.isOffer = false;
        assertEq(proposalContract.getCreditAmount(proposal, proposal.auctionStart), proposal.maxCreditAmount);
        assertEq(proposalContract.getCreditAmount(proposal, proposal.auctionDuration), proposal.minCreditAmount);
        assertEq(proposalContract.getCreditAmount(proposal, proposal.auctionDuration + 59), proposal.minCreditAmount);
    }

    function testFuzz_shouldReturnCorrectCreditAmount_whenOffer(
        uint256 minCreditAmount, uint256 maxCreditAmount, uint256 timeInAuction, uint40 auctionDuration
    ) external {
        maxCreditAmount = bound(maxCreditAmount, 1, 1e40);
        minCreditAmount = bound(minCreditAmount, 0, maxCreditAmount - 1);
        auctionDuration = uint40(bound(auctionDuration, 1, 99999)) * 1 minutes;
        timeInAuction = bound(timeInAuction, 0, auctionDuration);

        proposal.isOffer = true;
        proposal.minCreditAmount = minCreditAmount;
        proposal.maxCreditAmount = maxCreditAmount;
        proposal.auctionStart = 0;
        proposal.auctionDuration = auctionDuration;

        assertEq(
            proposalContract.getCreditAmount(proposal, timeInAuction),
            minCreditAmount + (maxCreditAmount - minCreditAmount) * (timeInAuction / 1 minutes * 1 minutes) / auctionDuration
        );
    }

    function testFuzz_shouldReturnCorrectCreditAmount_whenRequest(
        uint256 minCreditAmount, uint256 maxCreditAmount, uint256 timeInAuction, uint40 auctionDuration
    ) external {
        maxCreditAmount = bound(maxCreditAmount, 1, 1e40);
        minCreditAmount = bound(minCreditAmount, 0, maxCreditAmount - 1);
        auctionDuration = uint40(bound(auctionDuration, 1, 99999)) * 1 minutes;
        timeInAuction = bound(timeInAuction, 0, auctionDuration);

        proposal.isOffer = false;
        proposal.minCreditAmount = minCreditAmount;
        proposal.maxCreditAmount = maxCreditAmount;
        proposal.auctionStart = 0;
        proposal.auctionDuration = auctionDuration;

        assertEq(
            proposalContract.getCreditAmount(proposal, timeInAuction),
            maxCreditAmount - (maxCreditAmount - minCreditAmount) * (timeInAuction / 1 minutes * 1 minutes) / auctionDuration
        );
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT PROPOSAL                                       *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanDutchAuctionProposal_AcceptProposal_Test is PWNSimpleLoanDutchAuctionProposalTest, PWNSimpleLoanProposal_AcceptProposal_Test {

    function setUp() virtual public override(PWNSimpleLoanDutchAuctionProposalTest, PWNSimpleLoanProposalTest) {
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

    function testFuzz_shouldFail_whenCurrentAuctionCreditAmountNotInIntendedCreditAmountRange_whenOffer(
        uint256 intendedCreditAmount
    ) external {
        proposal.isOffer = true;
        proposal.minCreditAmount = 0;
        proposal.maxCreditAmount = 100000;
        proposal.auctionStart = 1;
        proposal.auctionDuration = 100 minutes;

        vm.warp(proposal.auctionStart + proposal.auctionDuration / 2);

        proposalValues.slippage = 500;
        intendedCreditAmount = bound(intendedCreditAmount, 0, type(uint256).max - proposalValues.slippage);
        proposalValues.intendedCreditAmount = intendedCreditAmount;

        uint256 auctionCreditAmount = proposalContract.getCreditAmount(proposal, block.timestamp);

        vm.assume(
            intendedCreditAmount < auctionCreditAmount - proposalValues.slippage
            || intendedCreditAmount > auctionCreditAmount
        );

        vm.expectRevert(abi.encodeWithSelector(
            InvalidCreditAmount.selector, auctionCreditAmount, proposalValues.intendedCreditAmount, proposalValues.slippage
        ));
        proposalContract.acceptProposal(
            proposal, proposalValues, _signProposalHash(proposerPK, _proposalHash(proposal)), permit, ""
        );
    }

    function testFuzz_shouldFail_whenCurrentAuctionCreditAmountNotInIntendedCreditAmountRange_whenRequest(
        uint256 intendedCreditAmount
    ) external {
        proposal.isOffer = false;
        proposal.minCreditAmount = 0;
        proposal.maxCreditAmount = 100000;
        proposal.auctionStart = 1;
        proposal.auctionDuration = 100 minutes;

        vm.warp(proposal.auctionStart + proposal.auctionDuration / 2);

        proposalValues.slippage = 500;
        intendedCreditAmount = bound(intendedCreditAmount, proposalValues.slippage, type(uint256).max);
        proposalValues.intendedCreditAmount = intendedCreditAmount;

        uint256 auctionCreditAmount = proposalContract.getCreditAmount(proposal, block.timestamp);

        vm.assume(
            intendedCreditAmount < auctionCreditAmount
            || intendedCreditAmount - proposalValues.slippage > auctionCreditAmount
        );

        vm.expectRevert(abi.encodeWithSelector(
            InvalidCreditAmount.selector, auctionCreditAmount, proposalValues.intendedCreditAmount, proposalValues.slippage
        ));
        proposalContract.acceptProposal(
            proposal, proposalValues, _signProposalHash(proposerPK, _proposalHash(proposal)), permit, ""
        );
    }

    function testFuzz_shouldCallLoanContractWithLoanTerms(
        uint256 minCreditAmount, uint256 maxCreditAmount, uint40 auctionDuration, uint256 timeInAuction, bool isOffer
    ) external {
        vm.assume(minCreditAmount < maxCreditAmount);
        auctionDuration = uint40(bound(auctionDuration, 1, type(uint40).max / 1 minutes - 1)) * 1 minutes;
        timeInAuction = bound(timeInAuction, 0, auctionDuration - 1);

        proposal.isOffer = isOffer;
        proposal.minCreditAmount = minCreditAmount;
        proposal.maxCreditAmount = maxCreditAmount;
        proposal.auctionStart = 1;
        proposal.auctionDuration = auctionDuration;

        vm.warp(proposal.auctionStart + timeInAuction);

        proposalValues.intendedCreditAmount = proposalContract.getCreditAmount(proposal, block.timestamp);
        proposalValues.slippage = 0;

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
                amount: proposalValues.intendedCreditAmount
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

contract PWNSimpleLoanDutchAuctionProposal_AcceptProposalAndRevokeCallersNonce_Test is PWNSimpleLoanDutchAuctionProposalTest, PWNSimpleLoanProposal_AcceptProposalAndRevokeCallersNonce_Test {

    function setUp() virtual public override(PWNSimpleLoanDutchAuctionProposalTest, PWNSimpleLoanProposalTest) {
        super.setUp();
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT REFINANCE PROPOSAL                             *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanDutchAuctionProposal_AcceptRefinanceProposal_Test is PWNSimpleLoanDutchAuctionProposalTest, PWNSimpleLoanProposal_AcceptRefinanceProposal_Test {

    function setUp() virtual public override(PWNSimpleLoanDutchAuctionProposalTest, PWNSimpleLoanProposalTest) {
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

    function testFuzz_shouldFail_whenCurrentAuctionCreditAmountNotInIntendedCreditAmountRange_whenOffer(
        uint256 intendedCreditAmount
    ) external {
        proposal.isOffer = true;
        proposal.minCreditAmount = 0;
        proposal.maxCreditAmount = 100000;
        proposal.auctionStart = 1;
        proposal.auctionDuration = 100 minutes;

        vm.warp(proposal.auctionStart + proposal.auctionDuration / 2);

        proposalValues.slippage = 500;
        intendedCreditAmount = bound(intendedCreditAmount, 0, type(uint256).max - proposalValues.slippage);
        proposalValues.intendedCreditAmount = intendedCreditAmount;

        uint256 auctionCreditAmount = proposalContract.getCreditAmount(proposal, block.timestamp);

        vm.assume(
            intendedCreditAmount < auctionCreditAmount - proposalValues.slippage
            || intendedCreditAmount > auctionCreditAmount
        );

        vm.expectRevert(abi.encodeWithSelector(
            InvalidCreditAmount.selector, auctionCreditAmount, proposalValues.intendedCreditAmount, proposalValues.slippage
        ));
        proposalContract.acceptRefinanceProposal(
            loanId, proposal, proposalValues, _signProposalHash(proposerPK, _proposalHash(proposal)), permit, extra
        );
    }

    function testFuzz_shouldFail_whenCurrentAuctionCreditAmountNotInIntendedCreditAmountRange_whenRequest(
        uint256 intendedCreditAmount
    ) external {
        proposal.isOffer = false;
        proposal.minCreditAmount = 0;
        proposal.maxCreditAmount = 100000;
        proposal.auctionStart = 1;
        proposal.auctionDuration = 100 minutes;

        vm.warp(proposal.auctionStart + proposal.auctionDuration / 2);

        proposalValues.slippage = 500;
        intendedCreditAmount = bound(intendedCreditAmount, proposalValues.slippage, type(uint256).max);
        proposalValues.intendedCreditAmount = intendedCreditAmount;

        uint256 auctionCreditAmount = proposalContract.getCreditAmount(proposal, block.timestamp);

        vm.assume(
            intendedCreditAmount < auctionCreditAmount
            || intendedCreditAmount - proposalValues.slippage > auctionCreditAmount
        );

        vm.expectRevert(abi.encodeWithSelector(
            InvalidCreditAmount.selector, auctionCreditAmount, proposalValues.intendedCreditAmount, proposalValues.slippage
        ));
        proposalContract.acceptRefinanceProposal(
            loanId, proposal, proposalValues, _signProposalHash(proposerPK, _proposalHash(proposal)), permit, extra
        );
    }

    function testFuzz_shouldCallLoanContractWithLoanTerms(
        uint256 minCreditAmount, uint256 maxCreditAmount, uint40 auctionDuration, uint256 timeInAuction, bool isOffer
    ) external {
        vm.assume(minCreditAmount < maxCreditAmount);
        auctionDuration = uint40(bound(auctionDuration, 1, type(uint40).max / 1 minutes - 1)) * 1 minutes;
        timeInAuction = bound(timeInAuction, 0, auctionDuration - 1);

        proposal.isOffer = isOffer;
        proposal.minCreditAmount = minCreditAmount;
        proposal.maxCreditAmount = maxCreditAmount;
        proposal.auctionStart = 1;
        proposal.auctionDuration = auctionDuration;

        vm.warp(proposal.auctionStart + timeInAuction);

        proposalValues.intendedCreditAmount = proposalContract.getCreditAmount(proposal, block.timestamp);
        proposalValues.slippage = 0;

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
                amount: proposalValues.intendedCreditAmount
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

contract PWNSimpleLoanDutchAuctionProposal_AcceptRefinanceProposalAndRevokeCallersNonce_Test is PWNSimpleLoanDutchAuctionProposalTest, PWNSimpleLoanProposal_AcceptRefinanceProposalAndRevokeCallersNonce_Test {

    function setUp() virtual public override(PWNSimpleLoanDutchAuctionProposalTest, PWNSimpleLoanProposalTest) {
        super.setUp();
    }

}
