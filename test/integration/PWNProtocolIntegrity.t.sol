// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "@pwn/hub/PWNHubTags.sol";
import "@pwn/PWNErrors.sol";

import "@pwn-test/helper/BaseIntegrationTest.t.sol";


contract PWNProtocolIntegrityTest is BaseIntegrationTest {

    function test_shouldFailCreatingLOANOnNotActiveLoanContract() external {
        // Remove ACTIVE_LOAN tag
        hub.setTag(address(simpleLoan), PWNHubTags.ACTIVE_LOAN, false);

        // Try to create LOAN
        _createERC1155LoanFailing(
            abi.encodeWithSelector(CallerMissingHubTag.selector, PWNHubTags.ACTIVE_LOAN)
        );
    }

    function test_shouldRepayLOANWithNotActiveLoanContract() external {
        // Create LOAN
        uint256 loanId = _createERC1155Loan();

        // Remove ACTIVE_LOAN tag
        hub.setTag(address(simpleLoan), PWNHubTags.ACTIVE_LOAN, false);

        // Repay loan
        _repayLoan(loanId);

        // Assert final state
        assertEq(loanToken.ownerOf(loanId), lender);

        assertEq(loanAsset.balanceOf(lender), 0);
        assertEq(loanAsset.balanceOf(borrower), 0);
        assertEq(loanAsset.balanceOf(address(simpleLoan)), 110e18);

        assertEq(t1155.balanceOf(lender, 42), 0);
        assertEq(t1155.balanceOf(borrower, 42), 10e18);
        assertEq(t1155.balanceOf(address(simpleLoan), 42), 0);
    }

    function test_shouldClaimRepaidLOANWithNotActiveLoanContract() external {
        // Create LOAN
        uint256 loanId = _createERC1155Loan();

        // Repay loan
        _repayLoan(loanId);

        // Remove ACTIVE_LOAN tag
        hub.setTag(address(simpleLoan), PWNHubTags.ACTIVE_LOAN, false);

        // Claim loan
        vm.prank(lender);
        simpleLoan.claimLOAN(loanId);

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

    function test_shouldFail_whenCallerIsNotActiveLoan() external {
        // Remove ACTIVE_LOAN tag
        hub.setTag(address(simpleLoan), PWNHubTags.ACTIVE_LOAN, false);

        vm.expectRevert(
            abi.encodeWithSelector(CallerMissingHubTag.selector, PWNHubTags.ACTIVE_LOAN)
        );
        vm.prank(address(simpleLoan));
        simpleOffer.getLOANTerms(borrower, "", ""); // Offer data are not important in this test
    }

    function test_shouldFail_whenPassingInvalidOfferContract() external {
        // Remove SIMPLE_LOAN_TERMS_FACTORY tag
        hub.setTag(address(simpleOffer), PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY, false);

        // Try to create LOAN
        _createERC1155LoanFailing(
            abi.encodeWithSelector(CallerMissingHubTag.selector, PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY)
        );
    }

}
