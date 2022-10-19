// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "@pwn/PWNError.sol";

import "@pwn-test/helper/BaseIntegrationTest.t.sol";


contract PWNSimpleLoanIntegrationTest is BaseIntegrationTest {

    // Create LOAN

    function test_shouldCreateLOAN_withERC20Collateral() external {
        // Create LOAN
        uint256 loanId = _createERC20Loan();

        // Assert final state
        assertEq(loanToken.ownerOf(loanId), lender);

        assertEq(loanAsset.balanceOf(lender), 0);
        assertEq(loanAsset.balanceOf(borrower), 100e18);
        assertEq(loanAsset.balanceOf(address(simpleLoan)), 0);

        assertEq(t20.balanceOf(lender), 0);
        assertEq(t20.balanceOf(borrower), 0);
        assertEq(t20.balanceOf(address(simpleLoan)), 10e18);

        assertEq(revokedOfferNonce.isOfferNonceRevoked(lender, offer.nonce), true);
        assertEq(loanToken.loanContract(loanId), address(simpleLoan));
    }

    function test_shouldCreateLOAN_withERC721Collateral() external {
        // Create LOAN
        uint256 loanId = _createERC721Loan();

        // Assert final state
        assertEq(loanToken.ownerOf(loanId), lender);

        assertEq(loanAsset.balanceOf(lender), 0);
        assertEq(loanAsset.balanceOf(borrower), 100e18);
        assertEq(loanAsset.balanceOf(address(simpleLoan)), 0);

        assertEq(t721.ownerOf(42), address(simpleLoan));

        assertEq(revokedOfferNonce.isOfferNonceRevoked(lender, offer.nonce), true);
        assertEq(loanToken.loanContract(loanId), address(simpleLoan));
    }

    function test_shouldCreateLOAN_withERC1155Collateral() external {
        // Create LOAN
        uint256 loanId = _createERC1155Loan();

        // Assert final state
        assertEq(loanToken.ownerOf(loanId), lender);

        assertEq(loanAsset.balanceOf(lender), 0);
        assertEq(loanAsset.balanceOf(borrower), 100e18);
        assertEq(loanAsset.balanceOf(address(simpleLoan)), 0);

        assertEq(t1155.balanceOf(lender, 42), 0);
        assertEq(t1155.balanceOf(borrower, 42), 0);
        assertEq(t1155.balanceOf(address(simpleLoan), 42), 10e18);

        assertEq(revokedOfferNonce.isOfferNonceRevoked(lender, nonce), true);
        assertEq(loanToken.loanContract(loanId), address(simpleLoan));
    }

    function test_shouldCreateLOAN_withCryptoKittiesCollateral() external {
        // TODO:
    }


    // Repay LOAN

    function test_shouldRepayLoan_whenNotExpired() external {
        // Create LOAN
        uint256 loanId = _createERC1155Loan();

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

    function test_shouldFailToRepayLoan_whenLOANExpired() external {
        // Create LOAN
        uint256 loanId = _createERC1155Loan();

        // Try to repay loan
        uint256 expiration = block.timestamp + uint256(offer.duration);
        vm.warp(expiration);
        _repayLoanFailing(
            loanId,
            abi.encodeWithSelector(PWNError.LoanDefaulted.selector, uint40(expiration))
        );
    }


    // Claim LOAN

    function test_shouldClaimRepaidLOAN() external {
        // Create LOAN
        uint256 loanId = _createERC1155Loan();

        // Repay loan
        _repayLoan(loanId);

        // Claim loan
        vm.prank(lender);
        simpleLoan.claimLoan(loanId);

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

    function test_shouldClaimDefaultedLOAN() external {
        // Create LOAN
        uint256 loanId = _createERC1155Loan();

        // Loan defaulted
        vm.warp(block.timestamp + uint256(offer.duration));

        // Claim defaulted loan
        vm.prank(lender);
        simpleLoan.claimLoan(loanId);

        // Assert final state
        vm.expectRevert("ERC721: invalid token ID");
        loanToken.ownerOf(loanId);

        assertEq(loanAsset.balanceOf(lender), 0);
        assertEq(loanAsset.balanceOf(borrower), 100e18);
        assertEq(loanAsset.balanceOf(address(simpleLoan)), 0);

        assertEq(t1155.balanceOf(lender, 42), 10e18);
        assertEq(t1155.balanceOf(borrower, 42), 0);
        assertEq(t1155.balanceOf(address(simpleLoan), 42), 0);
    }

}
