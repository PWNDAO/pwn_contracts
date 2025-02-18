// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { PWNHubTags } from "pwn/hub/PWNHubTags.sol";
import {
    PWNSimpleLoanElasticProposal,
    PWNSimpleLoanProposal,
    SimpleTerms
} from "pwn/loan/terms/simple/proposal/PWNSimpleLoanElasticProposal.sol";

import {
    MultiToken,
    Math,
    PWNSimpleLoanProposalTest,
    PWNSimpleLoanProposal_AcceptProposal_Test
} from "test/unit/PWNSimpleLoanProposal.t.sol";


abstract contract PWNSimpleLoanElasticProposalTest is PWNSimpleLoanProposalTest {

    PWNSimpleLoanElasticProposal proposalContract;
    PWNSimpleLoanElasticProposal.Proposal proposal;
    PWNSimpleLoanElasticProposal.ProposalValues proposalValues;

    event ProposalMade(bytes32 indexed proposalHash, address indexed proposer, PWNSimpleLoanElasticProposal.Proposal proposal);

    function setUp() virtual public override {
        super.setUp();

        proposalContract = new PWNSimpleLoanElasticProposal(hub, revokedNonce, config, utilizedCredit);
        proposalContractAddr = PWNSimpleLoanProposal(proposalContract);

        proposal = PWNSimpleLoanElasticProposal.Proposal({
            collateralCategory: MultiToken.Category.ERC1155,
            collateralAddress: token,
            collateralId: 0,
            checkCollateralStateFingerprint: true,
            collateralStateFingerprint: keccak256("some state fingerprint"),
            creditAddress: token,
            creditPerCollateralUnit: 1 * proposalContract.CREDIT_PER_COLLATERAL_UNIT_DENOMINATOR(),
            minCreditAmount: 1,
            availableCreditLimit: 0,
            utilizedCreditId: 0,
            fixedInterestAmount: 1,
            accruingInterestAPR: 0,
            durationOrDate: 1 days,
            expiration: 60303,
            allowedAcceptor: address(0),
            proposer: proposer,
            proposerSpecHash: keccak256("proposer spec"),
            isOffer: true,
            refinancingLoanId: 0,
            nonceSpace: 1,
            nonce: uint256(keccak256("nonce_1")),
            loanContract: activeLoanContract
        });

        proposalValues = PWNSimpleLoanElasticProposal.ProposalValues({
            creditAmount: 1000
        });
    }


    function _proposalHash(PWNSimpleLoanElasticProposal.Proposal memory _proposal) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            "\x19\x01",
            keccak256(abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("PWNSimpleLoanElasticProposal"),
                keccak256("1.1"),
                block.chainid,
                proposalContractAddr
            )),
            keccak256(abi.encodePacked(
                keccak256("Proposal(uint8 collateralCategory,address collateralAddress,uint256 collateralId,bool checkCollateralStateFingerprint,bytes32 collateralStateFingerprint,address creditAddress,uint256 creditPerCollateralUnit,uint256 minCreditAmount,uint256 availableCreditLimit,bytes32 utilizedCreditId,uint256 fixedInterestAmount,uint24 accruingInterestAPR,uint32 durationOrDate,uint40 expiration,address allowedAcceptor,address proposer,bytes32 proposerSpecHash,bool isOffer,uint256 refinancingLoanId,uint256 nonceSpace,uint256 nonce,address loanContract)"),
                abi.encode(_proposal)
            ))
        ));
    }

    function _updateProposal(CommonParams memory _params) internal {
        proposal.collateralAddress = _params.collateralAddress;
        proposal.collateralId = _params.collateralId;
        proposal.checkCollateralStateFingerprint = _params.checkCollateralStateFingerprint;
        proposal.collateralStateFingerprint = _params.collateralStateFingerprint;
        proposal.availableCreditLimit = _params.availableCreditLimit;
        proposal.utilizedCreditId = _params.utilizedCreditId;
        proposal.durationOrDate = _params.durationOrDate;
        proposal.expiration = _params.expiration;
        proposal.allowedAcceptor = _params.allowedAcceptor;
        proposal.proposer = _params.proposer;
        proposal.isOffer = _params.isOffer;
        proposal.refinancingLoanId = _params.refinancingLoanId;
        proposal.nonceSpace = _params.nonceSpace;
        proposal.nonce = _params.nonce;
        proposal.loanContract = _params.loanContract;

        proposalValues.creditAmount = _params.creditAmount;
    }


    function _callAcceptProposalWith(Params memory _params) internal override returns (bytes32, SimpleTerms memory) {
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

contract PWNSimpleLoanElasticProposal_RevokeNonce_Test is PWNSimpleLoanElasticProposalTest {

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

contract PWNSimpleLoanElasticProposal_GetProposalHash_Test is PWNSimpleLoanElasticProposalTest {

    function test_shouldReturnProposalHash() external {
        assertEq(_proposalHash(proposal), proposalContract.getProposalHash(proposal));
    }

}


/*----------------------------------------------------------*|
|*  # MAKE PROPOSAL                                         *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanElasticProposal_MakeProposal_Test is PWNSimpleLoanElasticProposalTest {

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

contract PWNSimpleLoanElasticProposal_EncodeProposalData_Test is PWNSimpleLoanElasticProposalTest {

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

contract PWNSimpleLoanElasticProposal_DecodeProposalData_Test is PWNSimpleLoanElasticProposalTest {

    function test_shouldReturnDecodedProposalData() external {
        (
            PWNSimpleLoanElasticProposal.Proposal memory _proposal,
            PWNSimpleLoanElasticProposal.ProposalValues memory _proposalValues
        ) = proposalContract.decodeProposalData(abi.encode(proposal, proposalValues));

        assertEq(uint8(_proposal.collateralCategory), uint8(proposal.collateralCategory));
        assertEq(_proposal.collateralAddress, proposal.collateralAddress);
        assertEq(_proposal.collateralId, proposal.collateralId);
        assertEq(_proposal.checkCollateralStateFingerprint, proposal.checkCollateralStateFingerprint);
        assertEq(_proposal.collateralStateFingerprint, proposal.collateralStateFingerprint);
        assertEq(_proposal.creditAddress, proposal.creditAddress);
        assertEq(_proposal.creditPerCollateralUnit, proposal.creditPerCollateralUnit);
        assertEq(_proposal.minCreditAmount, proposal.minCreditAmount);
        assertEq(_proposal.availableCreditLimit, proposal.availableCreditLimit);
        assertEq(_proposal.utilizedCreditId, proposal.utilizedCreditId);
        assertEq(_proposal.fixedInterestAmount, proposal.fixedInterestAmount);
        assertEq(_proposal.accruingInterestAPR, proposal.accruingInterestAPR);
        assertEq(_proposal.durationOrDate, proposal.durationOrDate);
        assertEq(_proposal.expiration, proposal.expiration);
        assertEq(_proposal.allowedAcceptor, proposal.allowedAcceptor);
        assertEq(_proposal.proposer, proposal.proposer);
        assertEq(_proposal.isOffer, proposal.isOffer);
        assertEq(_proposal.refinancingLoanId, proposal.refinancingLoanId);
        assertEq(_proposal.nonceSpace, proposal.nonceSpace);
        assertEq(_proposal.nonce, proposal.nonce);
        assertEq(_proposal.loanContract, proposal.loanContract);

        assertEq(_proposalValues.creditAmount, proposalValues.creditAmount);
    }

}


/*----------------------------------------------------------*|
|*  # GET COLLATERAL AMOUNT                                 *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanElasticProposal_GetCollateralAmount_Test is PWNSimpleLoanElasticProposalTest {

    function test_shouldFail_whenZeroCreditPerCollateralUnit() external {
        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoanElasticProposal.ZeroCreditPerCollateralUnit.selector));
        proposalContract.getCollateralAmount(100e18, 0);
    }

    function test_shouldReturnCollateralAmount() external {
        uint256 CREDIT_PER_COLLATERAL_UNIT_DENOMINATOR = proposalContract.CREDIT_PER_COLLATERAL_UNIT_DENOMINATOR();

        assertEq(
            proposalContract.getCollateralAmount(100e18, 100 * CREDIT_PER_COLLATERAL_UNIT_DENOMINATOR),
            1e18
        );
        assertEq(
            proposalContract.getCollateralAmount(50, 25 * CREDIT_PER_COLLATERAL_UNIT_DENOMINATOR),
            2
        );
        assertEq(
            proposalContract.getCollateralAmount(1033220e18, 10e18 * CREDIT_PER_COLLATERAL_UNIT_DENOMINATOR),
            103322
        );
        assertEq(
            proposalContract.getCollateralAmount(5e50, 1e30 * CREDIT_PER_COLLATERAL_UNIT_DENOMINATOR),
            5e20
        );
        assertEq(
            proposalContract.getCollateralAmount(0, 1e30 * CREDIT_PER_COLLATERAL_UNIT_DENOMINATOR),
            0
        );
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT PROPOSAL                                       *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanElasticProposal_AcceptProposal_Test is PWNSimpleLoanElasticProposalTest, PWNSimpleLoanProposal_AcceptProposal_Test {

    function setUp() virtual public override(PWNSimpleLoanElasticProposalTest, PWNSimpleLoanProposalTest) {
        super.setUp();
    }


    function test_shouldFail_whenZeroMinCreditAmount() external {
        proposal.minCreditAmount = 0;

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoanElasticProposal.MinCreditAmountNotSet.selector));
        vm.prank(activeLoanContract);
        proposalContract.acceptProposal({
            acceptor: acceptor,
            refinancingLoanId: 0,
            proposalData: abi.encode(proposal, proposalValues),
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, _proposalHash(proposal))
        });
    }

    function testFuzz_shouldFail_whenCreditAmountLessThanMinCreditAmount(
        uint256 minCreditAmount, uint256 creditAmount
    ) external {
        proposal.creditPerCollateralUnit = 1 * proposalContract.CREDIT_PER_COLLATERAL_UNIT_DENOMINATOR();
        proposal.minCreditAmount = bound(minCreditAmount, 1, type(uint256).max);
        proposalValues.creditAmount = bound(creditAmount, 0, proposal.minCreditAmount - 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNSimpleLoanElasticProposal.InsufficientCreditAmount.selector,
                proposalValues.creditAmount,
                proposal.minCreditAmount
            )
        );
        vm.prank(activeLoanContract);
        proposalContract.acceptProposal({
            acceptor: acceptor,
            refinancingLoanId: 0,
            proposalData: abi.encode(proposal, proposalValues),
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, _proposalHash(proposal))
        });
    }

    function test_shouldFail_whenZeroCreditPerCollateralUnit() external {
        proposal.creditPerCollateralUnit = 0;

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoanElasticProposal.ZeroCreditPerCollateralUnit.selector));
        vm.prank(activeLoanContract);
        proposalContract.acceptProposal({
            acceptor: acceptor,
            refinancingLoanId: 0,
            proposalData: abi.encode(proposal, proposalValues),
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, _proposalHash(proposal))
        });
    }

    function testFuzz_shouldCallLoanContractWithLoanTerms(uint256 creditAmount, bool isOffer) external {
        proposalValues.creditAmount = bound(creditAmount, proposal.minCreditAmount, 1e40);
        proposal.isOffer = isOffer;

        vm.prank(activeLoanContract);
        (bytes32 proposalHash, SimpleTerms memory terms) = proposalContract.acceptProposal({
            acceptor: acceptor,
            refinancingLoanId: 0,
            proposalData: abi.encode(proposal, proposalValues),
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, _proposalHash(proposal))
        });

        assertEq(proposalHash, _proposalHash(proposal));
        assertEq(terms.lender, isOffer ? proposal.proposer : acceptor);
        assertEq(terms.borrower, isOffer ? acceptor : proposal.proposer);
        assertEq(terms.duration, proposal.durationOrDate);
        assertEq(uint8(terms.collateral.category), uint8(proposal.collateralCategory));
        assertEq(terms.collateral.assetAddress, proposal.collateralAddress);
        assertEq(terms.collateral.id, proposal.collateralId);
        assertEq(terms.collateral.amount, proposalContract.getCollateralAmount(proposalValues.creditAmount, proposal.creditPerCollateralUnit));
        assertEq(uint8(terms.credit.category), uint8(MultiToken.Category.ERC20));
        assertEq(terms.credit.assetAddress, proposal.creditAddress);
        assertEq(terms.credit.id, 0);
        assertEq(terms.credit.amount, proposalValues.creditAmount);
        assertEq(terms.fixedInterestAmount, proposal.fixedInterestAmount);
        assertEq(terms.accruingInterestAPR, proposal.accruingInterestAPR);
        assertEq(terms.lenderSpecHash, isOffer ? proposal.proposerSpecHash : bytes32(0));
        assertEq(terms.borrowerSpecHash, isOffer ? bytes32(0) : proposal.proposerSpecHash);
    }

}
