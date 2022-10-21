// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "@pwn/PWNErrors.sol";

import "@pwn-test/helper/BaseIntegrationTest.t.sol";


contract PWNSimpleLoanSimpleOfferIntegrationTest is BaseIntegrationTest {

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


    // Group of offers

    function test_shouldRevokeOffersInGroup_whenAcceptingOneFromGroup() external {
        // Mint initial state
        loanAsset.mint(lender, 100e18);
        t1155.mint(borrower, 42, 10e18);

        // Sign offers
        offer = PWNSimpleLoanSimpleOffer.Offer({
            collateralCategory: MultiToken.Category.ERC1155,
            collateralAddress: address(t1155),
            collateralId: 42,
            collateralAmount: 5e18, // 1/2 of borrower balance
            loanAssetAddress: address(loanAsset),
            loanAmount: 50e18, // 1/2 of lender balance
            loanYield: 10e18,
            duration: 3600,
            expiration: 0,
            borrower: borrower,
            lender: lender,
            isPersistent: false,
            nonce: nonce
        });
        bytes memory signature1 = _sign(lenderPK, simpleOffer.getOfferHash(offer));
        bytes memory offerData1 = abi.encode(offer);

        offer.loanYield = 20e18;
        bytes memory signature2 = _sign(lenderPK, simpleOffer.getOfferHash(offer));
        bytes memory offerData2 = abi.encode(offer);

        // Approve loan asset
        vm.prank(lender);
        loanAsset.approve(address(simpleLoan), 100e18);

        // Approve collateral
        vm.prank(borrower);
        t1155.setApprovalForAll(address(simpleLoan), true);

        // Create LOAN with offer 2
        vm.prank(borrower);
        simpleLoan.createLOAN({
            loanFactoryContract: address(simpleOffer),
            loanFactoryData: offerData2,
            signature: signature2,
            loanAssetPermit: "",
            collateralPermit: ""
        });

        // Fail to accept other offers with same nonce
        vm.expectRevert(abi.encodeWithSelector(NonceRevoked.selector));
        vm.prank(borrower);
        simpleLoan.createLOAN({
            loanFactoryContract: address(simpleOffer),
            loanFactoryData: offerData1,
            signature: signature1,
            loanAssetPermit: "",
            collateralPermit: ""
        });
    }

}
