// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { PWNHubTags } from "pwn/hub/PWNHubTags.sol";
import {
    PWNSimpleLoanListProposal,
    PWNSimpleLoanProposal,
    PWNSimpleLoan
} from "pwn/loan/terms/simple/proposal/PWNSimpleLoanListProposal.sol";

import {
    MultiToken,
    Math,
    PWNSimpleLoanProposalTest,
    PWNSimpleLoanProposal_AcceptProposal_Test
} from "test/unit/PWNSimpleLoanProposal.t.sol";


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
            proposerSpecHash: keccak256("proposer spec"),
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
                keccak256("Proposal(uint8 collateralCategory,address collateralAddress,bytes32 collateralIdsWhitelistMerkleRoot,uint256 collateralAmount,bool checkCollateralStateFingerprint,bytes32 collateralStateFingerprint,address creditAddress,uint256 creditAmount,uint256 availableCreditLimit,uint256 fixedInterestAmount,uint40 accruingInterestAPR,uint32 duration,uint40 expiration,address allowedAcceptor,address proposer,bytes32 proposerSpecHash,bool isOffer,uint256 refinancingLoanId,uint256 nonceSpace,uint256 nonce,address loanContract)"),
                abi.encode(_proposal)
            ))
        ));
    }

    function _updateProposal(PWNSimpleLoanProposal.ProposalBase memory _proposal) internal {
        proposal.collateralAddress = _proposal.collateralAddress;
        proposal.checkCollateralStateFingerprint = _proposal.checkCollateralStateFingerprint;
        proposal.collateralStateFingerprint = _proposal.collateralStateFingerprint;
        proposal.creditAmount = _proposal.creditAmount;
        proposal.availableCreditLimit = _proposal.availableCreditLimit;
        proposal.expiration = _proposal.expiration;
        proposal.allowedAcceptor = _proposal.allowedAcceptor;
        proposal.proposer = _proposal.proposer;
        proposal.isOffer = _proposal.isOffer;
        proposal.refinancingLoanId = _proposal.refinancingLoanId;
        proposal.nonceSpace = _proposal.nonceSpace;
        proposal.nonce = _proposal.nonce;
        proposal.loanContract = _proposal.loanContract;

        proposalValues.collateralId = _proposal.collateralId;
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

contract PWNSimpleLoanListProposal_EncodeProposalData_Test is PWNSimpleLoanListProposalTest {

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

contract PWNSimpleLoanListProposal_DecodeProposalData_Test is PWNSimpleLoanListProposalTest {

    function test_shouldReturnDecodedProposalData() external {
        (
            PWNSimpleLoanListProposal.Proposal memory _proposal,
            PWNSimpleLoanListProposal.ProposalValues memory _proposalValues
        ) = proposalContract.decodeProposalData(abi.encode(proposal, proposalValues));

        assertEq(uint8(_proposal.collateralCategory), uint8(proposal.collateralCategory));
        assertEq(_proposal.collateralAddress, proposal.collateralAddress);
        assertEq(_proposal.collateralIdsWhitelistMerkleRoot, proposal.collateralIdsWhitelistMerkleRoot);
        assertEq(_proposal.collateralAmount, proposal.collateralAmount);
        assertEq(_proposal.checkCollateralStateFingerprint, proposal.checkCollateralStateFingerprint);
        assertEq(_proposal.collateralStateFingerprint, proposal.collateralStateFingerprint);
        assertEq(_proposal.creditAddress, proposal.creditAddress);
        assertEq(_proposal.creditAmount, proposal.creditAmount);
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

        assertEq(_proposalValues.collateralId, proposalValues.collateralId);
        assertEq(_proposalValues.merkleInclusionProof.length, proposalValues.merkleInclusionProof.length);
        for (uint256 i; i < _proposalValues.merkleInclusionProof.length; ++i) {
            assertEq(_proposalValues.merkleInclusionProof[i], proposalValues.merkleInclusionProof[i]);
        }
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT PROPOSAL                                       *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanListProposal_AcceptProposal_Test is PWNSimpleLoanListProposalTest, PWNSimpleLoanProposal_AcceptProposal_Test {

    function setUp() virtual public override(PWNSimpleLoanListProposalTest, PWNSimpleLoanProposalTest) {
        super.setUp();
    }


    function testFuzz_shouldAcceptAnyCollateralId_whenMerkleRootIsZero(uint256 collId) external {
        proposalValues.collateralId = collId;
        proposal.collateralIdsWhitelistMerkleRoot = bytes32(0);

        vm.prank(activeLoanContract);
        proposalContract.acceptProposal({
            acceptor: acceptor,
            refinancingLoanId: 0,
            proposalData: abi.encode(proposal, proposalValues),
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, _proposalHash(proposal))
        });
    }

    function testFuzz_shouldPass_whenGivenCollateralIdIsWhitelisted(uint256 collId1, uint256 collId2) external {
        bytes32 id1Hash = keccak256(abi.encodePacked(collId1));
        bytes32 id2Hash = keccak256(abi.encodePacked(collId2));
        proposal.collateralIdsWhitelistMerkleRoot = keccak256(
            uint256(id1Hash) < uint256(id2Hash)
                ? abi.encodePacked(id1Hash, id2Hash)
                : abi.encodePacked(id2Hash, id1Hash)
        );

        proposalValues.collateralId = collId1;
        proposalValues.merkleInclusionProof = new bytes32[](1);
        proposalValues.merkleInclusionProof[0] = id2Hash;

        vm.prank(activeLoanContract);
        proposalContract.acceptProposal({
            acceptor: acceptor,
            refinancingLoanId: 0,
            proposalData: abi.encode(proposal, proposalValues),
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, _proposalHash(proposal))
        });
    }

    function testFuzz_shouldFail_whenGivenCollateralIdIsNotWhitelisted(
        uint256 collId1, uint256 collId2, uint256 collId3
    ) external {
        vm.assume(collId1 < collId2);
        vm.assume(collId3 != collId1 && collId3 != collId2);
        bytes32 id1Hash = keccak256(abi.encodePacked(collId1));
        bytes32 id2Hash = keccak256(abi.encodePacked(collId2));
        proposal.collateralIdsWhitelistMerkleRoot = keccak256(
            uint256(id1Hash) < uint256(id2Hash)
                ? abi.encodePacked(id1Hash, id2Hash)
                : abi.encodePacked(id2Hash, id1Hash)
        );

        proposalValues.collateralId = collId3;
        proposalValues.merkleInclusionProof = new bytes32[](1);
        proposalValues.merkleInclusionProof[0] = id2Hash;

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNSimpleLoanListProposal.CollateralIdNotWhitelisted.selector, proposalValues.collateralId
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

    function testFuzz_shouldCallLoanContractWithLoanTerms(bool isOffer) external {
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
        assertEq(terms.collateral.id, proposalValues.collateralId);
        assertEq(terms.collateral.amount, proposal.collateralAmount);
        assertEq(uint8(terms.credit.category), uint8(MultiToken.Category.ERC20));
        assertEq(terms.credit.assetAddress, proposal.creditAddress);
        assertEq(terms.credit.id, 0);
        assertEq(terms.credit.amount, proposal.creditAmount);
        assertEq(terms.fixedInterestAmount, proposal.fixedInterestAmount);
        assertEq(terms.accruingInterestAPR, proposal.accruingInterestAPR);
        assertEq(terms.lenderSpecHash, isOffer ? proposal.proposerSpecHash : bytes32(0));
        assertEq(terms.borrowerSpecHash, isOffer ? bytes32(0) : proposal.proposerSpecHash);
    }

}
