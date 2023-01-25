// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "@pwn/PWNErrors.sol";

import "@pwn-test/helper/BaseIntegrationTest.t.sol";


contract PWNSimpleLoanSimpleOfferIntegrationTest is BaseIntegrationTest {

    // Group of offers

    function test_shouldRevokeOffersInGroup_whenAcceptingOneFromGroup() external {
        // Mint initial state
        loanAsset.mint(lender, 100e18);
        t1155.mint(borrower, 42, 10e18);

        // Sign offers
        PWNSimpleLoanSimpleOffer.Offer memory offer = PWNSimpleLoanSimpleOffer.Offer({
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
            lateRepaymentEnabled: false,
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
            loanTermsFactoryContract: address(simpleOffer),
            loanTermsFactoryData: offerData2,
            signature: signature2,
            loanAssetPermit: "",
            collateralPermit: ""
        });

        // Fail to accept other offers with same nonce
        vm.expectRevert(abi.encodeWithSelector(NonceAlreadyRevoked.selector));
        vm.prank(borrower);
        simpleLoan.createLOAN({
            loanTermsFactoryContract: address(simpleOffer),
            loanTermsFactoryData: offerData1,
            signature: signature1,
            loanAssetPermit: "",
            collateralPermit: ""
        });
    }

}
