// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "@pwn/PWNErrors.sol";

import "@pwn-test/integration/contracts/BaseIntegrationTest.t.sol";


contract PWNSimpleLoanSimpleRequestIntegrationTest is BaseIntegrationTest {

    // Group of requests

    function test_shouldRevokeRequestsInGroup_whenAcceptingOneFromGroup() external {
        // Mint initial state
        loanAsset.mint(lender, 100e18);
        t1155.mint(borrower, 42, 10e18);

        // Sign requests
        PWNSimpleLoanSimpleRequest.Request memory request = PWNSimpleLoanSimpleRequest.Request({
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
            nonce: nonce
        });
        bytes memory signature1 = _sign(borrowerPK, simpleLoanSimpleRequest.getRequestHash(request));
        bytes memory requestData1 = abi.encode(request);

        request.loanYield = 20e18;
        bytes memory signature2 = _sign(borrowerPK, simpleLoanSimpleRequest.getRequestHash(request));
        bytes memory requestData2 = abi.encode(request);

        // Approve loan asset
        vm.prank(lender);
        loanAsset.approve(address(simpleLoan), 100e18);

        // Approve collateral
        vm.prank(borrower);
        t1155.setApprovalForAll(address(simpleLoan), true);

        // Create LOAN with request 2
        vm.prank(lender);
        simpleLoan.createLOAN({
            loanTermsFactoryContract: address(simpleLoanSimpleRequest),
            loanTermsFactoryData: requestData2,
            signature: signature2,
            loanAssetPermit: "",
            collateralPermit: ""
        });

        // Fail to accept other requests with same nonce
        vm.expectRevert(abi.encodeWithSelector(NonceAlreadyRevoked.selector));
        vm.prank(lender);
        simpleLoan.createLOAN({
            loanTermsFactoryContract: address(simpleLoanSimpleRequest),
            loanTermsFactoryData: requestData1,
            signature: signature1,
            loanAssetPermit: "",
            collateralPermit: ""
        });
    }

}
