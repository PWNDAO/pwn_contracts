// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

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
    PWNSimpleLoanElasticProposal,
    PWNSimpleLoanListProposal,
    PWNSimpleLoanSimpleProposal,
    PWNLOAN,
    PWNRevokedNonce,
    PWNUtilizedCredit,
    MultiTokenCategoryRegistry
} from "test/DeploymentTest.t.sol";


abstract contract BaseIntegrationTest is DeploymentTest {

    T20 t20;
    T721 t721;
    T1155 t1155;
    T20 credit;

    PWNSimpleLoanSimpleProposal.Proposal simpleProposal;
    PWNSimpleLoanSimpleProposal.ProposalValues simpleProposalValues;

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
            utilizedCreditId: 0,
            fixedInterestAmount: 10e18,
            accruingInterestAPR: 0,
            durationOrDate: 1 days,
            expiration: uint40(block.timestamp + 7 days),
            acceptorController: address(0),
            acceptorControllerData: "",
            proposer: lender,
            proposerSpecHash: __d.simpleLoan.getLenderSpecHash(PWNSimpleLoan.LenderSpec(lender)),
            isOffer: true,
            refinancingLoanId: 0,
            nonceSpace: 0,
            nonce: 0,
            loanContract: address(__d.simpleLoan)
        });

        simpleProposalValues = PWNSimpleLoanSimpleProposal.ProposalValues({
            acceptorControllerData: ""
        });
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
        t20.approve(address(__d.simpleLoan), 10e18);

        // Create LOAN
        return _createLoan(simpleProposal, simpleProposalValues, "");
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
        t721.approve(address(__d.simpleLoan), 42);

        // Create LOAN
        return _createLoan(simpleProposal, simpleProposalValues, "");
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
        t1155.setApprovalForAll(address(__d.simpleLoan), true);

        // Create LOAN
        return _createLoan(simpleProposal, simpleProposalValues, revertData);
    }

    function _createLoan(
        PWNSimpleLoanSimpleProposal.Proposal memory _proposal,
        PWNSimpleLoanSimpleProposal.ProposalValues memory _proposalValues,
        bytes memory revertData
    ) private returns (uint256) {
        // Sign proposal
        bytes memory signature = _sign(lenderPK, __d.simpleLoanSimpleProposal.getProposalHash(_proposal));

        // Mint initial state
        credit.mint(lender, 100e18);

        // Approve loan asset
        vm.prank(lender);
        credit.approve(address(__d.simpleLoan), 100e18);

        // Proposal data (need for vm.prank to work properly when creating a loan)
        bytes memory proposalData = __d.simpleLoanSimpleProposal.encodeProposalData(_proposal, _proposalValues);

        // Create LOAN
        if (keccak256(revertData) != keccak256("")) {
            vm.expectRevert(revertData);
        }
        vm.prank(borrower);
        return __d.simpleLoan.createLOAN({
            proposalSpec: PWNSimpleLoan.ProposalSpec({
                proposalContract: address(__d.simpleLoanSimpleProposal),
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
                nonce: 0
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
        credit.approve(address(__d.simpleLoan), 110e18);

        // Repay loan
        if (keccak256(revertData) != keccak256("")) {
            vm.expectRevert(revertData);
        }
        vm.prank(borrower);
        __d.simpleLoan.repayLOAN(loanId);
    }

}