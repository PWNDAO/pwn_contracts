// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "@pwn/hub/PWNHubTags.sol";
import "@pwn/PWNErrors.sol";

import "@pwn-test/integration/BaseIntegrationTest.t.sol";


contract PWNProtocolIntegrityTest is BaseIntegrationTest {

    function test_shouldFailToCreateLOAN_whenLoanContractNotActive() external {
        // Remove ACTIVE_LOAN tag
        vm.prank(protocolSafe);
        hub.setTag(address(simpleLoan), PWNHubTags.ACTIVE_LOAN, false);

        // Try to create LOAN
        _createERC1155LoanFailing(
            abi.encodeWithSelector(CallerMissingHubTag.selector, PWNHubTags.ACTIVE_LOAN)
        );
    }

    function test_shouldRepayLOAN_whenLoanContractNotActive_whenOriginalLenderIsLOANOwner() external {
        // Create LOAN
        uint256 loanId = _createERC1155Loan();

        // Remove ACTIVE_LOAN tag
        vm.prank(protocolSafe);
        hub.setTag(address(simpleLoan), PWNHubTags.ACTIVE_LOAN, false);

        // Repay loan directly to original lender
        _repayLoan(loanId);

        // Assert final state
        vm.expectRevert("ERC721: invalid token ID");
        loanToken.ownerOf(loanId);

        assertEq(loanAsset.balanceOf(lender), 110e18);
        assertEq(loanAsset.balanceOf(borrower), 0);
        assertEq(loanAsset.balanceOf(address(simpleLoan)), 0);

        assertEq(t1155.balanceOf(lender, 42), 0);
        assertEq(t1155.balanceOf(borrower, 42), 10e18);
        assertEq(t1155.balanceOf(address(simpleLoan), 42), 0);
    }

    function test_shouldRepayLOAN_whenLoanContractNotActive_whenOriginalLenderIsNotLOANOwner() external {
        address lender2 = makeAddr("lender2");

        // Create LOAN
        uint256 loanId = _createERC1155Loan();

        // Transfer loan to another lender
        vm.prank(lender);
        loanToken.transferFrom(lender, lender2, loanId);

        // Remove ACTIVE_LOAN tag
        vm.prank(protocolSafe);
        hub.setTag(address(simpleLoan), PWNHubTags.ACTIVE_LOAN, false);

        // Repay loan directly to original lender
        _repayLoan(loanId);

        // Assert final state
        assertEq(loanToken.ownerOf(loanId), lender2);

        assertEq(loanAsset.balanceOf(lender), 0);
        assertEq(loanAsset.balanceOf(lender2), 0);
        assertEq(loanAsset.balanceOf(borrower), 0);
        assertEq(loanAsset.balanceOf(address(simpleLoan)), 110e18);

        assertEq(t1155.balanceOf(lender, 42), 0);
        assertEq(t1155.balanceOf(lender2, 42), 0);
        assertEq(t1155.balanceOf(borrower, 42), 10e18);
        assertEq(t1155.balanceOf(address(simpleLoan), 42), 0);
    }

    function test_shouldClaimRepaidLOAN_whenLoanContractNotActive() external {
        address lender2 = makeAddr("lender2");

        // Create LOAN
        uint256 loanId = _createERC1155Loan();

        // Transfer loan to another lender
        vm.prank(lender);
        loanToken.transferFrom(lender, lender2, loanId);

        // Repay loan
        _repayLoan(loanId);

        // Remove ACTIVE_LOAN tag
        vm.prank(protocolSafe);
        hub.setTag(address(simpleLoan), PWNHubTags.ACTIVE_LOAN, false);

        // Claim loan
        vm.prank(lender2);
        simpleLoan.claimLOAN(loanId);

        // Assert final state
        vm.expectRevert("ERC721: invalid token ID");
        loanToken.ownerOf(loanId);

        assertEq(loanAsset.balanceOf(lender), 0);
        assertEq(loanAsset.balanceOf(lender2), 110e18);
        assertEq(loanAsset.balanceOf(borrower), 0);
        assertEq(loanAsset.balanceOf(address(simpleLoan)), 0);

        assertEq(t1155.balanceOf(lender, 42), 0);
        assertEq(t1155.balanceOf(lender2, 42), 0);
        assertEq(t1155.balanceOf(borrower, 42), 10e18);
        assertEq(t1155.balanceOf(address(simpleLoan), 42), 0);
    }

    function test_shouldFailToCreateLOANTerms_whenCallerIsNotActiveLoan() external {
        // Remove ACTIVE_LOAN tag
        vm.prank(protocolSafe);
        hub.setTag(address(simpleLoan), PWNHubTags.ACTIVE_LOAN, false);

        vm.expectRevert(
            abi.encodeWithSelector(CallerMissingHubTag.selector, PWNHubTags.ACTIVE_LOAN)
        );
        vm.prank(address(simpleLoan));
        simpleLoanSimpleOffer.createLOANTerms(borrower, "", ""); // Offer data are not important in this test
    }

    function test_shouldFailToCreateLOAN_whenPassingInvalidTermsFactoryContract() external {
        // Remove SIMPLE_LOAN_TERMS_FACTORY tag
        vm.prank(protocolSafe);
        hub.setTag(address(simpleLoanSimpleOffer), PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY, false);

        // Try to create LOAN
        _createERC1155LoanFailing(
            abi.encodeWithSelector(CallerMissingHubTag.selector, PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY)
        );
    }

}
