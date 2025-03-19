// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { PWNHubTags } from "pwn/hub/PWNHubTags.sol";
import {
    PWNSimpleLoanDutchAuctionProposal,
    PWNSimpleLoanProposal,
    PWNSimpleLoan
} from "pwn/loan/terms/simple/proposal/PWNSimpleLoanDutchAuctionProposal.sol";

import { PWNSimpleLoanDutchAuctionProposalHarness } from "test/harness/PWNSimpleLoanDutchAuctionProposalHarness.sol";
import {
    MultiToken,
    Math,
    PWNSimpleLoanProposalTest,
    PWNSimpleLoanProposal_AcceptProposal_Test,
    Expired
} from "test/unit/PWNSimpleLoanProposal.t.sol";


abstract contract PWNSimpleLoanDutchAuctionProposalTest is PWNSimpleLoanProposalTest {

    PWNSimpleLoanDutchAuctionProposalHarness proposalContract;
    PWNSimpleLoanDutchAuctionProposal.Proposal proposal;
    PWNSimpleLoanDutchAuctionProposal.ProposalValues proposalValues;

    event ProposalMade(bytes32 indexed proposalHash, address indexed proposer, PWNSimpleLoanDutchAuctionProposal.Proposal proposal);

    function setUp() virtual public override {
        super.setUp();

        proposalContract = new PWNSimpleLoanDutchAuctionProposalHarness(hub, revokedNonce, config, utilizedCredit);
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
            utilizedCreditId: 0,
            fixedInterestAmount: 1,
            accruingInterestAPR: 0,
            durationOrDate: 1 days,
            auctionStart: uint40(block.timestamp),
            auctionDuration: 100 minutes,
            acceptorController: address(0),
            acceptorControllerData: "",
            proposer: proposer,
            proposerSpecHash: keccak256("proposer spec"),
            isOffer: true,
            refinancingLoanId: 0,
            nonceSpace: 1,
            nonce: uint256(keccak256("nonce_1")),
            loanContract: activeLoanContract
        });

        proposalValues = PWNSimpleLoanDutchAuctionProposal.ProposalValues({
            intendedCreditAmount: 10000,
            slippage: 0,
            acceptorControllerData: ""
        });
    }


    function _proposalHash(PWNSimpleLoanDutchAuctionProposal.Proposal memory _proposal) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            "\x19\x01",
            keccak256(abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("PWNSimpleLoanDutchAuctionProposal"),
                keccak256("1.2"),
                block.chainid,
                proposalContractAddr
            )),
            keccak256(abi.encodePacked(
                keccak256("Proposal(uint8 collateralCategory,address collateralAddress,uint256 collateralId,uint256 collateralAmount,bool checkCollateralStateFingerprint,bytes32 collateralStateFingerprint,address creditAddress,uint256 minCreditAmount,uint256 maxCreditAmount,uint256 availableCreditLimit,bytes32 utilizedCreditId,uint256 fixedInterestAmount,uint24 accruingInterestAPR,uint32 durationOrDate,uint40 auctionStart,uint40 auctionDuration,address acceptorController,bytes acceptorControllerData,address proposer,bytes32 proposerSpecHash,bool isOffer,uint256 refinancingLoanId,uint256 nonceSpace,uint256 nonce,address loanContract)"),
                proposalContract.exposed_erc712EncodeProposal(_proposal)
            ))
        ));
    }

    function _updateProposal(CommonParams memory _params) internal {
        if (_params.isOffer) {
            proposal.minCreditAmount = _params.creditAmount;
            proposal.maxCreditAmount = proposal.minCreditAmount * 10;
            proposalValues.intendedCreditAmount = proposal.minCreditAmount;
        } else {
            proposal.maxCreditAmount = _params.creditAmount;
            proposal.minCreditAmount = proposal.maxCreditAmount / 10;
            proposalValues.intendedCreditAmount = proposal.maxCreditAmount;
        }

        proposal.collateralAddress = _params.collateralAddress;
        proposal.collateralId = _params.collateralId;
        proposal.checkCollateralStateFingerprint = _params.checkCollateralStateFingerprint;
        proposal.collateralStateFingerprint = _params.collateralStateFingerprint;
        proposal.availableCreditLimit = _params.availableCreditLimit;
        proposal.utilizedCreditId = _params.utilizedCreditId;
        proposal.durationOrDate = _params.durationOrDate;
        proposal.auctionDuration = _params.expiration - proposal.auctionStart - 1 minutes;
        proposal.acceptorController = _params.acceptorController;
        proposal.acceptorControllerData = _params.acceptorControllerProposerData;
        proposal.proposer = _params.proposer;
        proposal.isOffer = _params.isOffer;
        proposal.refinancingLoanId = _params.refinancingLoanId;
        proposal.nonceSpace = _params.nonceSpace;
        proposal.nonce = _params.nonce;
        proposal.loanContract = _params.loanContract;

        proposalValues.acceptorControllerData = _params.acceptorControllerAcceptorData;
    }


    function _callAcceptProposalWith(Params memory _params) internal override returns (bytes32, PWNSimpleLoan.Terms memory) {
        _updateProposal(_params.common);
        return proposalContract.acceptProposal({
            acceptor: _params.acceptor,
            refinancingLoanId: _params.refinancingLoanId,
            proposalData: abi.encode(proposal, proposalValues),
            proposalInclusionProof: _params.proposalInclusionProof,
            signature: _params.signature
        });
    }

    function _getProposalHashWith(Params memory _params) internal override returns (bytes32) {
        _updateProposal(_params.common);
        return _proposalHash(proposal);
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

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoanProposal.CallerIsNotStatedProposer.selector, proposal.proposer));
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
|*  # ENCODE PROPOSAL DATA                                  *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanDutchAuctionProposal_EncodeProposalData_Test is PWNSimpleLoanDutchAuctionProposalTest {

    function test_shouldReturnEncodedProposalData() external {
        assertEq(
            proposalContract.encodeProposalData(proposal, proposalValues),
            abi.encode(proposal, proposalValues)
        );
    }

}


/*----------------------------------------------------------*|
|*  # DECODE PROPOSAL DATA                                  *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanDutchAuctionProposal_DecodeProposalData_Test is PWNSimpleLoanDutchAuctionProposalTest {

    function test_shouldReturnDecodedProposalData() external {
        (
            PWNSimpleLoanDutchAuctionProposal.Proposal memory _proposal,
            PWNSimpleLoanDutchAuctionProposal.ProposalValues memory _proposalValues
        ) = proposalContract.decodeProposalData(abi.encode(proposal, proposalValues));

        assertEq(uint8(_proposal.collateralCategory), uint8(proposal.collateralCategory));
        assertEq(_proposal.collateralAddress, proposal.collateralAddress);
        assertEq(_proposal.collateralId, proposal.collateralId);
        assertEq(_proposal.collateralAmount, proposal.collateralAmount);
        assertEq(_proposal.checkCollateralStateFingerprint, proposal.checkCollateralStateFingerprint);
        assertEq(_proposal.collateralStateFingerprint, proposal.collateralStateFingerprint);
        assertEq(_proposal.creditAddress, proposal.creditAddress);
        assertEq(_proposal.minCreditAmount, proposal.minCreditAmount);
        assertEq(_proposal.maxCreditAmount, proposal.maxCreditAmount);
        assertEq(_proposal.availableCreditLimit, proposal.availableCreditLimit);
        assertEq(_proposal.utilizedCreditId, proposal.utilizedCreditId);
        assertEq(_proposal.fixedInterestAmount, proposal.fixedInterestAmount);
        assertEq(_proposal.accruingInterestAPR, proposal.accruingInterestAPR);
        assertEq(_proposal.durationOrDate, proposal.durationOrDate);
        assertEq(_proposal.auctionStart, proposal.auctionStart);
        assertEq(_proposal.auctionDuration, proposal.auctionDuration);
        assertEq(_proposal.acceptorController, proposal.acceptorController);
        assertEq(_proposal.acceptorControllerData, proposal.acceptorControllerData);
        assertEq(_proposal.proposer, proposal.proposer);
        assertEq(_proposal.isOffer, proposal.isOffer);
        assertEq(_proposal.refinancingLoanId, proposal.refinancingLoanId);
        assertEq(_proposal.nonceSpace, proposal.nonceSpace);
        assertEq(_proposal.nonce, proposal.nonce);
        assertEq(_proposal.loanContract, proposal.loanContract);

        assertEq(_proposalValues.intendedCreditAmount, proposalValues.intendedCreditAmount);
        assertEq(_proposalValues.slippage, proposalValues.slippage);
        assertEq(_proposalValues.acceptorControllerData, proposalValues.acceptorControllerData);
    }

}


/*----------------------------------------------------------*|
|*  # GET CREDIT AMOUNT                                     *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanDutchAuctionProposal_GetCreditAmount_Test is PWNSimpleLoanDutchAuctionProposalTest {

    function testFuzz_shouldFail_whenInvalidAuctionDuration(uint40 auctionDuration) external {
        vm.assume(auctionDuration < 1 minutes);
        proposal.auctionDuration = auctionDuration;

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNSimpleLoanDutchAuctionProposal.InvalidAuctionDuration.selector, auctionDuration, 1 minutes
            )
        );
        proposalContract.getCreditAmount(proposal, 0);
    }

    function testFuzz_shouldFail_whenAuctionDurationNotInFullMinutes(uint40 auctionDuration) external {
        vm.assume(auctionDuration > 1 minutes && auctionDuration % 1 minutes > 0);
        proposal.auctionDuration = auctionDuration;

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNSimpleLoanDutchAuctionProposal.AuctionDurationNotInFullMinutes.selector, auctionDuration
            )
        );
        proposalContract.getCreditAmount(proposal, 0);
    }

    function testFuzz_shouldFail_whenInvalidCreditAmountRange(uint256 minCreditAmount, uint256 maxCreditAmount) external {
        vm.assume(minCreditAmount >= maxCreditAmount);
        proposal.minCreditAmount = minCreditAmount;
        proposal.maxCreditAmount = maxCreditAmount;

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNSimpleLoanDutchAuctionProposal.InvalidCreditAmountRange.selector, minCreditAmount, maxCreditAmount
            )
        );
        proposalContract.getCreditAmount(proposal, 0);
    }

    function testFuzz_shouldFail_whenAuctionNotInProgress(uint40 auctionStart, uint256 time) external {
        auctionStart = uint40(bound(auctionStart, 1, type(uint40).max));
        time = bound(time, 0, auctionStart - 1);

        proposal.auctionStart = auctionStart;

        vm.expectRevert(
            abi.encodeWithSelector(PWNSimpleLoanDutchAuctionProposal.AuctionNotInProgress.selector, time, auctionStart)
        );
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

contract PWNSimpleLoanDutchAuctionProposal_AcceptProposal_Test is PWNSimpleLoanDutchAuctionProposalTest, PWNSimpleLoanProposal_AcceptProposal_Test(0) {

    function setUp() virtual public override(PWNSimpleLoanDutchAuctionProposalTest, PWNSimpleLoanProposalTest) {
        super.setUp();
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

        bytes32 proposalHash = _proposalHash(proposal);

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNSimpleLoanDutchAuctionProposal.InvalidCreditAmount.selector,
                auctionCreditAmount,
                proposalValues.intendedCreditAmount,
                proposalValues.slippage
            )
        );
        vm.prank(activeLoanContract);
        proposalContract.acceptProposal({
            acceptor: acceptor,
            refinancingLoanId: 0,
            proposalData: abi.encode(proposal, proposalValues),
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, proposalHash)
        });
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

        bytes32 proposalHash = _proposalHash(proposal);

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNSimpleLoanDutchAuctionProposal.InvalidCreditAmount.selector,
                auctionCreditAmount,
                proposalValues.intendedCreditAmount,
                proposalValues.slippage
            )
        );
        vm.prank(activeLoanContract);
        proposalContract.acceptProposal({
            acceptor: acceptor,
            refinancingLoanId: 0,
            proposalData: abi.encode(proposal, proposalValues),
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, proposalHash)
        });
    }

    function testFuzz_shouldReturnDuration_whenPassedAsDate(uint32 timestamp) public override {
        proposal.auctionStart = 1e9;
        super.testFuzz_shouldReturnDuration_whenPassedAsDate(timestamp);
    }

    function testFuzz_shouldFail_whenDefaultDateInPast(uint32 timestamp) public override {
        proposal.auctionStart = 1.7e9;
        super.testFuzz_shouldFail_whenDefaultDateInPast(timestamp);
    }

    function testFuzz_shouldCallLoanContractWithLoanTerms(
        uint256 minCreditAmount,
        uint256 maxCreditAmount,
        uint40 auctionDuration,
        uint256 timeInAuction,
        bool isOffer
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

        uint256 creditAmount = proposalContract.getCreditAmount(proposal, block.timestamp);
        proposalValues.intendedCreditAmount = creditAmount;
        proposalValues.slippage = 0;

        bytes32 proposalHash = _proposalHash(proposal);

        vm.prank(activeLoanContract);
        (bytes32 proposalHash_, PWNSimpleLoan.Terms memory terms) = proposalContract.acceptProposal({
            acceptor: acceptor,
            refinancingLoanId: 0,
            proposalData: abi.encode(proposal, proposalValues),
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, proposalHash)
        });

        assertEq(proposalHash_, proposalHash);
        assertEq(terms.lender, isOffer ? proposal.proposer : acceptor);
        assertEq(terms.borrower, isOffer ? acceptor : proposal.proposer);
        assertEq(terms.duration, proposal.durationOrDate);
        assertEq(uint8(terms.collateral.category), uint8(proposal.collateralCategory));
        assertEq(terms.collateral.assetAddress, proposal.collateralAddress);
        assertEq(terms.collateral.id, proposal.collateralId);
        assertEq(terms.collateral.amount, proposal.collateralAmount);
        assertEq(uint8(terms.credit.category), uint8(MultiToken.Category.ERC20));
        assertEq(terms.credit.assetAddress, proposal.creditAddress);
        assertEq(terms.credit.id, 0);
        assertEq(terms.credit.amount, creditAmount);
        assertEq(terms.fixedInterestAmount, proposal.fixedInterestAmount);
        assertEq(terms.accruingInterestAPR, proposal.accruingInterestAPR);
        assertEq(terms.lenderSpecHash, isOffer ? proposal.proposerSpecHash : bytes32(0));
        assertEq(terms.borrowerSpecHash, isOffer ? bytes32(0) : proposal.proposerSpecHash);
    }

}


/*----------------------------------------------------------*|
|*  # ERC712 ENCODE PROPOSAL                                *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanDutchAuctionProposalTest_Erc712EncodeProposal_Test is PWNSimpleLoanDutchAuctionProposalTest {

    function test_shouldERC712EncodeProposal() external {
        PWNSimpleLoanDutchAuctionProposal.ERC712Proposal memory proposalErc712 = PWNSimpleLoanDutchAuctionProposal.ERC712Proposal(
            uint8(proposal.collateralCategory),
            proposal.collateralAddress,
            proposal.collateralId,
            proposal.collateralAmount,
            proposal.checkCollateralStateFingerprint,
            proposal.collateralStateFingerprint,
            proposal.creditAddress,
            proposal.minCreditAmount,
            proposal.maxCreditAmount,
            proposal.availableCreditLimit,
            proposal.utilizedCreditId,
            proposal.fixedInterestAmount,
            proposal.accruingInterestAPR,
            proposal.durationOrDate,
            proposal.auctionStart,
            proposal.auctionDuration,
            proposal.acceptorController,
            keccak256(proposal.acceptorControllerData),
            proposal.proposer,
            proposal.proposerSpecHash,
            proposal.isOffer,
            proposal.refinancingLoanId,
            proposal.nonceSpace,
            proposal.nonce,
            proposal.loanContract
        );

        assertEq(
            keccak256(abi.encode(proposalErc712)),
            keccak256(proposalContract.exposed_erc712EncodeProposal(proposal))
        );
    }

}
