// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { Permit } from "pwn/loan/vault/Permit.sol";

import { T20 } from "test/helper/T20.sol";
import { T721 } from "test/helper/T721.sol";
import { T1155 } from "test/helper/T1155.sol";
import {
    DeploymentTest,
    PWNConfig,
    IPWNDeployer,
    PWNHub,
    PWNHubTags,
    PWNSimpleLoan,
    PWNSimpleLoanDutchAuctionProposal,
    PWNSimpleLoanFungibleProposal,
    PWNSimpleLoanListProposal,
    PWNSimpleLoanSimpleProposal,
    PWNLOAN,
    PWNRevokedNonce,
    MultiTokenCategoryRegistry
} from "test/DeploymentTest.t.sol";


abstract contract BaseIntegrationTest is DeploymentTest {

    T20 t20;
    T721 t721;
    T1155 t1155;
    T20 credit;

    uint256 lenderPK = uint256(777);
    address lender = vm.addr(lenderPK);
    uint256 borrowerPK = uint256(888);
    address borrower = vm.addr(borrowerPK);
    PWNSimpleLoanSimpleProposal.Proposal simpleProposal;

    function setUp() public override {
        super.setUp();

        // Deploy tokens
        t20 = new T20();
        t721 = new T721();
        t1155 = new T1155();
        credit = new T20();

        // Default offer
        simpleProposal = PWNSimpleLoanSimpleProposal.Proposal({
            collateralCategory: MultiToken.Category.ERC1155,
            collateralAddress: address(t1155),
            collateralId: 42,
            collateralAmount: 10e18,
            checkCollateralStateFingerprint: false,
            collateralStateFingerprint: bytes32(0),
            creditAddress: address(credit),
            creditAmount: 100e18,
            availableCreditLimit: 0,
            fixedInterestAmount: 10e18,
            accruingInterestAPR: 0,
            duration: 3600,
            expiration: uint40(block.timestamp + 7 days),
            allowedAcceptor: borrower,
            proposer: lender,
            proposerSpecHash: deployment.simpleLoan.getLenderSpecHash(PWNSimpleLoan.LenderSpec(lender)),
            isOffer: true,
            refinancingLoanId: 0,
            nonceSpace: 0,
            nonce: 0,
            loanContract: address(deployment.simpleLoan)
        });
    }


    function _sign(uint256 pk, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    // Create from proposal

    function _createERC20Loan() internal returns (uint256) {
        // Proposal
        simpleProposal.collateralCategory = MultiToken.Category.ERC20;
        simpleProposal.collateralAddress = address(t20);
        simpleProposal.collateralId = 0;
        simpleProposal.collateralAmount = 10e18;

        // Mint initial state
        t20.mint(borrower, 10e18);

        // Approve collateral
        vm.prank(borrower);
        t20.approve(address(deployment.simpleLoan), 10e18);

        // Create LOAN
        return _createLoan(simpleProposal, "");
    }

    function _createERC721Loan() internal returns (uint256) {
        // Proposal
        simpleProposal.collateralCategory = MultiToken.Category.ERC721;
        simpleProposal.collateralAddress = address(t721);
        simpleProposal.collateralId = 42;
        simpleProposal.collateralAmount = 0;

        // Mint initial state
        t721.mint(borrower, 42);

        // Approve collateral
        vm.prank(borrower);
        t721.approve(address(deployment.simpleLoan), 42);

        // Create LOAN
        return _createLoan(simpleProposal, "");
    }

    function _createERC1155Loan() internal returns (uint256) {
        return _createERC1155LoanFailing("");
    }

    function _createERC1155LoanFailing(bytes memory revertData) internal returns (uint256) {
        // Offer
        simpleProposal.collateralCategory = MultiToken.Category.ERC1155;
        simpleProposal.collateralAddress = address(t1155);
        simpleProposal.collateralId = 42;
        simpleProposal.collateralAmount = 10e18;

        // Mint initial state
        t1155.mint(borrower, 42, 10e18);

        // Approve collateral
        vm.prank(borrower);
        t1155.setApprovalForAll(address(deployment.simpleLoan), true);

        // Create LOAN
        return _createLoan(simpleProposal, revertData);
    }

    function _createLoan(PWNSimpleLoanSimpleProposal.Proposal memory _proposal, bytes memory revertData) private returns (uint256) {
        // Sign proposal
        bytes memory signature = _sign(lenderPK, deployment.simpleLoanSimpleProposal.getProposalHash(_proposal));

        // Mint initial state
        credit.mint(lender, 100e18);

        // Approve loan asset
        vm.prank(lender);
        credit.approve(address(deployment.simpleLoan), 100e18);

        // Proposal data (need for vm.prank to work properly when creating a loan)
        bytes memory proposalData = deployment.simpleLoanSimpleProposal.encodeProposalData(_proposal);

        // Create LOAN
        if (keccak256(revertData) != keccak256("")) {
            vm.expectRevert(revertData);
        }
        vm.prank(borrower);
        return deployment.simpleLoan.createLOAN({
            proposalSpec: PWNSimpleLoan.ProposalSpec({
                proposalContract: address(deployment.simpleLoanSimpleProposal),
                proposalData: proposalData,
                proposalInclusionProof: new bytes32[](0),
                signature: signature
            }),
            lenderSpec: PWNSimpleLoan.LenderSpec({
                sourceOfFunds: lender
            }),
            callerSpec: PWNSimpleLoan.CallerSpec({
                refinancingLoanId: 0,
                revokeNonce: false,
                nonce: 0,
                permitData: ""
            }),
            extra: ""
        });
    }

    // Repay

    function _repayLoan(uint256 loanId) internal {
        _repayLoanFailing(loanId, "");
    }

    function _repayLoanFailing(uint256 loanId, bytes memory revertData) internal {
        // Get the yield by farming 100000% APR food tokens
        credit.mint(borrower, 10e18);

        // Approve loan asset
        vm.prank(borrower);
        credit.approve(address(deployment.simpleLoan), 110e18);

        // Repay loan
        if (keccak256(revertData) != keccak256("")) {
            vm.expectRevert(revertData);
        }
        vm.prank(borrower);
        deployment.simpleLoan.repayLOAN({
            loanId: loanId,
            permitData: ""
        });
    }

}