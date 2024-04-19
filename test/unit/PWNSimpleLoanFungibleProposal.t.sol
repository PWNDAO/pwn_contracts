// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { PWNHubTags } from "pwn/hub/PWNHubTags.sol";
import {
    PWNSimpleLoanFungibleProposal,
    PWNSimpleLoanProposal,
    PWNSimpleLoan
} from "pwn/loan/terms/simple/proposal/PWNSimpleLoanFungibleProposal.sol";

import {
    MultiToken,
    Math,
    PWNSimpleLoanProposalTest,
    PWNSimpleLoanProposal_AcceptProposal_Test
} from "test/unit/PWNSimpleLoanProposal.t.sol";


abstract contract PWNSimpleLoanFungibleProposalTest is PWNSimpleLoanProposalTest {

    PWNSimpleLoanFungibleProposal proposalContract;
    PWNSimpleLoanFungibleProposal.Proposal proposal;
    PWNSimpleLoanFungibleProposal.ProposalValues proposalValues;

    event ProposalMade(bytes32 indexed proposalHash, address indexed proposer, PWNSimpleLoanFungibleProposal.Proposal proposal);

    function setUp() virtual public override {
        super.setUp();

        proposalContract = new PWNSimpleLoanFungibleProposal(hub, revokedNonce, config);
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
            proposerSpecHash: keccak256("proposer spec"),
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
                keccak256("Proposal(uint8 collateralCategory,address collateralAddress,uint256 collateralId,uint256 minCollateralAmount,bool checkCollateralStateFingerprint,bytes32 collateralStateFingerprint,address creditAddress,uint256 creditPerCollateralUnit,uint256 availableCreditLimit,uint256 fixedInterestAmount,uint40 accruingInterestAPR,uint32 duration,uint40 expiration,address allowedAcceptor,address proposer,bytes32 proposerSpecHash,bool isOffer,uint256 refinancingLoanId,uint256 nonceSpace,uint256 nonce,address loanContract)"),
                abi.encode(_proposal)
            ))
        ));
    }

    function _updateProposal(PWNSimpleLoanProposal.ProposalBase memory _proposal) internal {
        proposal.collateralAddress = _proposal.collateralAddress;
        proposal.collateralId = _proposal.collateralId;
        proposal.checkCollateralStateFingerprint = _proposal.checkCollateralStateFingerprint;
        proposal.collateralStateFingerprint = _proposal.collateralStateFingerprint;
        proposal.availableCreditLimit = _proposal.availableCreditLimit;
        proposal.expiration = _proposal.expiration;
        proposal.allowedAcceptor = _proposal.allowedAcceptor;
        proposal.proposer = _proposal.proposer;
        proposal.isOffer = _proposal.isOffer;
        proposal.refinancingLoanId = _proposal.refinancingLoanId;
        proposal.nonceSpace = _proposal.nonceSpace;
        proposal.nonce = _proposal.nonce;
        proposal.loanContract = _proposal.loanContract;

        proposalValues.collateralAmount = _proposal.creditAmount;
    }


    function _callAcceptProposalWith(Params memory _params) internal override returns (bytes32, PWNSimpleLoan.Terms memory) {
        _updateProposal(_params.base);
        return proposalContract.acceptProposal({
            acceptor: _params.acceptor,
            refinancingLoanId: _params.refinancingLoanId,
            proposalData: abi.encode(proposal, proposalValues),
            proposalInclusionProof: _params.proposalInclusionProof,
            signature: _params.signature
        });
    }

    function _getProposalHashWith(Params memory _params) internal override returns (bytes32) {
        _updateProposal(_params.base);
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

contract PWNSimpleLoanFungibleProposal_EncodeProposalData_Test is PWNSimpleLoanFungibleProposalTest {

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

contract PWNSimpleLoanFungibleProposal_DecodeProposalData_Test is PWNSimpleLoanFungibleProposalTest {

    function test_shouldReturnDecodedProposalData() external {
        (
            PWNSimpleLoanFungibleProposal.Proposal memory _proposal,
            PWNSimpleLoanFungibleProposal.ProposalValues memory _proposalValues
        ) = proposalContract.decodeProposalData(abi.encode(proposal, proposalValues));

        assertEq(uint8(_proposal.collateralCategory), uint8(proposal.collateralCategory));
        assertEq(_proposal.collateralAddress, proposal.collateralAddress);
        assertEq(_proposal.collateralId, proposal.collateralId);
        assertEq(_proposal.minCollateralAmount, proposal.minCollateralAmount);
        assertEq(_proposal.checkCollateralStateFingerprint, proposal.checkCollateralStateFingerprint);
        assertEq(_proposal.collateralStateFingerprint, proposal.collateralStateFingerprint);
        assertEq(_proposal.creditAddress, proposal.creditAddress);
        assertEq(_proposal.creditPerCollateralUnit, proposal.creditPerCollateralUnit);
        assertEq(_proposal.availableCreditLimit, proposal.availableCreditLimit);
        assertEq(_proposal.fixedInterestAmount, proposal.fixedInterestAmount);
        assertEq(_proposal.accruingInterestAPR, proposal.accruingInterestAPR);
        assertEq(_proposal.duration, proposal.duration);
        assertEq(_proposal.expiration, proposal.expiration);
        assertEq(_proposal.allowedAcceptor, proposal.allowedAcceptor);
        assertEq(_proposal.proposer, proposal.proposer);
        assertEq(_proposal.isOffer, proposal.isOffer);
        assertEq(_proposal.refinancingLoanId, proposal.refinancingLoanId);
        assertEq(_proposal.nonceSpace, proposal.nonceSpace);
        assertEq(_proposal.nonce, proposal.nonce);
        assertEq(_proposal.loanContract, proposal.loanContract);

        assertEq(_proposalValues.collateralAmount, proposalValues.collateralAmount);
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


    function test_shouldFail_whenZeroMinCollateralAmount() external {
        proposal.minCollateralAmount = 0;

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoanFungibleProposal.MinCollateralAmountNotSet.selector));
        vm.prank(activeLoanContract);
        proposalContract.acceptProposal({
            acceptor: acceptor,
            refinancingLoanId: 0,
            proposalData: abi.encode(proposal, proposalValues),
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, _proposalHash(proposal))
        });
    }

    function testFuzz_shouldFail_whenCollateralAmountLessThanMinCollateralAmount(
        uint256 minCollateralAmount, uint256 collateralAmount
    ) external {
        proposal.minCollateralAmount = bound(minCollateralAmount, 1, type(uint256).max);
        proposalValues.collateralAmount = bound(collateralAmount, 0, proposal.minCollateralAmount - 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNSimpleLoanFungibleProposal.InsufficientCollateralAmount.selector,
                proposalValues.collateralAmount,
                proposal.minCollateralAmount
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

    function testFuzz_shouldCallLoanContractWithLoanTerms(
        uint256 collateralAmount, uint256 creditPerCollateralUnit, bool isOffer
    ) external {
        proposalValues.collateralAmount = bound(collateralAmount, proposal.minCollateralAmount, 1e40);
        proposal.creditPerCollateralUnit = bound(creditPerCollateralUnit, 1, type(uint256).max / proposalValues.collateralAmount);
        proposal.isOffer = isOffer;

        vm.prank(activeLoanContract);
        (bytes32 proposalHash, PWNSimpleLoan.Terms memory terms) = proposalContract.acceptProposal({
            acceptor: acceptor,
            refinancingLoanId: 0,
            proposalData: abi.encode(proposal, proposalValues),
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, _proposalHash(proposal))
        });

        assertEq(proposalHash, _proposalHash(proposal));
        assertEq(terms.lender, isOffer ? proposal.proposer : acceptor);
        assertEq(terms.borrower, isOffer ? acceptor : proposal.proposer);
        assertEq(terms.duration, proposal.duration);
        assertEq(uint8(terms.collateral.category), uint8(proposal.collateralCategory));
        assertEq(terms.collateral.assetAddress, proposal.collateralAddress);
        assertEq(terms.collateral.id, proposal.collateralId);
        assertEq(terms.collateral.amount, proposalValues.collateralAmount);
        assertEq(uint8(terms.credit.category), uint8(MultiToken.Category.ERC20));
        assertEq(terms.credit.assetAddress, proposal.creditAddress);
        assertEq(terms.credit.id, 0);
        assertEq(terms.credit.amount, proposalContract.getCreditAmount(proposalValues.collateralAmount, proposal.creditPerCollateralUnit));
        assertEq(terms.fixedInterestAmount, proposal.fixedInterestAmount);
        assertEq(terms.accruingInterestAPR, proposal.accruingInterestAPR);
        assertEq(terms.lenderSpecHash, isOffer ? proposal.proposerSpecHash : bytes32(0));
        assertEq(terms.borrowerSpecHash, isOffer ? bytes32(0) : proposal.proposerSpecHash);
    }

}
