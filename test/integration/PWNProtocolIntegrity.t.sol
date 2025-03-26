// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { PWNHubTags } from "pwn/hub/PWNHubTags.sol";
import { AddressMissingHubTag } from "pwn/PWNErrors.sol";

import {
    MultiToken,
    MultiTokenCategoryRegistry,
    BaseIntegrationTest,
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
    PWNRevokedNonce
} from "test/integration/BaseIntegrationTest.t.sol";


contract PWNProtocolIntegrityTest is BaseIntegrationTest {

    function test_shouldFailToCreateLOAN_whenLoanContractNotActive() external {
        // Remove ACTIVE_LOAN tag
        vm.prank(__e.protocolTimelock);
        __d.hub.setTag(address(__d.simpleLoan), PWNHubTags.ACTIVE_LOAN, false);

        // Try to create LOAN
        _createERC1155LoanFailing(
            abi.encodeWithSelector(AddressMissingHubTag.selector, address(__d.simpleLoan), PWNHubTags.ACTIVE_LOAN)
        );
    }

    function test_shouldRepayLOAN_whenLoanContractNotActive_whenOriginalLenderIsLOANOwner() external {
        // Create LOAN
        uint256 loanId = _createERC1155Loan();

        // Remove ACTIVE_LOAN tag
        vm.prank(__e.protocolTimelock);
        __d.hub.setTag(address(__d.simpleLoan), PWNHubTags.ACTIVE_LOAN, false);

        // Repay loan directly to original lender
        _repayLoan(loanId);

        // Assert final state
        vm.expectRevert("ERC721: invalid token ID");
        __d.loanToken.ownerOf(loanId);

        assertEq(credit.balanceOf(lender), 110e18);
        assertEq(credit.balanceOf(borrower), 0);
        assertEq(credit.balanceOf(address(__d.simpleLoan)), 0);

        assertEq(t1155.balanceOf(lender, 42), 0);
        assertEq(t1155.balanceOf(borrower, 42), 10e18);
        assertEq(t1155.balanceOf(address(__d.simpleLoan), 42), 0);
    }

    function test_shouldRepayLOAN_whenLoanContractNotActive_whenOriginalLenderIsNotLOANOwner() external {
        address lender2 = makeAddr("lender2");

        // Create LOAN
        uint256 loanId = _createERC1155Loan();

        // Transfer loan to another lender
        vm.prank(lender);
        __d.loanToken.transferFrom(lender, lender2, loanId);

        // Remove ACTIVE_LOAN tag
        vm.prank(__e.protocolTimelock);
        __d.hub.setTag(address(__d.simpleLoan), PWNHubTags.ACTIVE_LOAN, false);

        // Repay loan directly to original lender
        _repayLoan(loanId);

        // Assert final state
        assertEq(__d.loanToken.ownerOf(loanId), lender2);

        assertEq(credit.balanceOf(lender), 0);
        assertEq(credit.balanceOf(lender2), 0);
        assertEq(credit.balanceOf(borrower), 0);
        assertEq(credit.balanceOf(address(__d.simpleLoan)), 110e18);

        assertEq(t1155.balanceOf(lender, 42), 0);
        assertEq(t1155.balanceOf(lender2, 42), 0);
        assertEq(t1155.balanceOf(borrower, 42), 10e18);
        assertEq(t1155.balanceOf(address(__d.simpleLoan), 42), 0);
    }

    function test_shouldClaimRepaidLOAN_whenLoanContractNotActive() external {
        address lender2 = makeAddr("lender2");

        // Create LOAN
        uint256 loanId = _createERC1155Loan();

        // Transfer loan to another lender
        vm.prank(lender);
        __d.loanToken.transferFrom(lender, lender2, loanId);

        // Repay loan
        _repayLoan(loanId);

        // Remove ACTIVE_LOAN tag
        vm.prank(__e.protocolTimelock);
        __d.hub.setTag(address(__d.simpleLoan), PWNHubTags.ACTIVE_LOAN, false);

        // Claim loan
        vm.prank(lender2);
        __d.simpleLoan.claimLOAN(loanId);

        // Assert final state
        vm.expectRevert("ERC721: invalid token ID");
        __d.loanToken.ownerOf(loanId);

        assertEq(credit.balanceOf(lender), 0);
        assertEq(credit.balanceOf(lender2), 110e18);
        assertEq(credit.balanceOf(borrower), 0);
        assertEq(credit.balanceOf(address(__d.simpleLoan)), 0);

        assertEq(t1155.balanceOf(lender, 42), 0);
        assertEq(t1155.balanceOf(lender2, 42), 0);
        assertEq(t1155.balanceOf(borrower, 42), 10e18);
        assertEq(t1155.balanceOf(address(__d.simpleLoan), 42), 0);
    }

    function test_shouldFailToCreateLOANTerms_whenCallerIsNotActiveLoan() external {
        // Remove ACTIVE_LOAN tag
        vm.prank(__e.protocolTimelock);
        __d.hub.setTag(address(__d.simpleLoan), PWNHubTags.ACTIVE_LOAN, false);

        bytes memory proposalData = __d.simpleLoanSimpleProposal.encodeProposalData(simpleProposal);

        vm.expectRevert(
            abi.encodeWithSelector(
                AddressMissingHubTag.selector, address(__d.simpleLoan), PWNHubTags.ACTIVE_LOAN
            )
        );
        vm.prank(address(__d.simpleLoan));
        __d.simpleLoanSimpleProposal.acceptProposal({
            acceptor: borrower,
            refinancingLoanId: 0,
            proposalData: proposalData,
            proposalInclusionProof: new bytes32[](0),
            signature: ""
        });
    }

    function test_shouldFailToCreateLOAN_whenPassingInvalidTermsFactoryContract() external {
        // Remove LOAN_PROPOSAL tag
        vm.prank(__e.protocolTimelock);
        __d.hub.setTag(address(__d.simpleLoanSimpleProposal), PWNHubTags.LOAN_PROPOSAL, false);

        // Try to create LOAN
        _createERC1155LoanFailing(
            abi.encodeWithSelector(
                AddressMissingHubTag.selector, address(__d.simpleLoanSimpleProposal), PWNHubTags.LOAN_PROPOSAL
            )
        );
    }

}
