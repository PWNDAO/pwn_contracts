// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "@pwn/PWNError.sol";

import "@pwn-test/helper/BaseIntegrationTest.t.sol";


contract PWNSimpleLoanSimpleRequestIntegrationTest is BaseIntegrationTest {

    function _createLoan(PWNSimpleLoanSimpleRequest.Request memory _request, bytes memory revertData) private returns (uint256) {
        // Sign request
        bytes memory signature = _sign(borrowerPK, simpleRequest.getRequestHash(_request));

        // Mint initial state
        loanAsset.mint(lender, 100e18);

        // Approve loan asset
        vm.prank(lender);
        loanAsset.approve(address(simpleLoan), 100e18);

        // Create LOAN
        if (keccak256(revertData) != keccak256("")) {
            vm.expectRevert(revertData);
        }
        vm.prank(lender);
        return simpleLoan.createLOAN({
            loanFactoryContract: address(simpleRequest),
            loanFactoryData: abi.encode(_request),
            signature: signature,
            loanAssetPermit: "",
            collateralPermit: ""
        });
    }


    // Create LOAN

    function test_shouldCreateLOAN_withERC20Collateral() external {
        // Request
        request.collateralCategory = MultiToken.Category.ERC20;
        request.collateralAddress = address(t20);
        request.collateralId = 0;
        request.collateralAmount = 10e18;

        // Mint initial state
        t20.mint(borrower, 10e18);

        // Approve collateral
        vm.prank(borrower);
        t20.approve(address(simpleLoan), 10e18);

        // Create LOAN
        uint256 loanId = _createLoan(request, "");

        // Assert final state
        assertEq(loanToken.ownerOf(loanId), lender);

        assertEq(loanAsset.balanceOf(lender), 0);
        assertEq(loanAsset.balanceOf(borrower), 100e18);
        assertEq(loanAsset.balanceOf(address(simpleLoan)), 0);

        assertEq(t20.balanceOf(lender), 0);
        assertEq(t20.balanceOf(borrower), 0);
        assertEq(t20.balanceOf(address(simpleLoan)), 10e18);

        assertEq(revokedRequestNonce.isRequestNonceRevoked(borrower, request.nonce), true);
        assertEq(loanToken.loanContract(loanId), address(simpleLoan));
    }

    function test_shouldCreateLOAN_withERC721Collateral() external {
        // Request
        request.collateralCategory = MultiToken.Category.ERC721;
        request.collateralAddress = address(t721);
        request.collateralId = 42;
        request.collateralAmount = 1;

        // Mint initial state
        t721.mint(borrower, 42);

        // Approve collateral
        vm.prank(borrower);
        t721.approve(address(simpleLoan), 42);

        // Create LOAN
        uint256 loanId = _createLoan(request, "");

        // Assert final state
        assertEq(loanToken.ownerOf(loanId), lender);

        assertEq(loanAsset.balanceOf(lender), 0);
        assertEq(loanAsset.balanceOf(borrower), 100e18);
        assertEq(loanAsset.balanceOf(address(simpleLoan)), 0);

        assertEq(t721.ownerOf(42), address(simpleLoan));

        assertEq(revokedRequestNonce.isRequestNonceRevoked(borrower, request.nonce), true);
        assertEq(loanToken.loanContract(loanId), address(simpleLoan));
    }

    function test_shouldCreateLOAN_withERC1155Collateral() external {
        // Request
        request.collateralCategory = MultiToken.Category.ERC1155;
        request.collateralAddress = address(t1155);
        request.collateralId = 42;
        request.collateralAmount = 10e18;

        // Mint initial state
        t1155.mint(borrower, 42, 10e18);

        // Approve collateral
        vm.prank(borrower);
        t1155.setApprovalForAll(address(simpleLoan), true);

        // Create LOAN
        uint256 loanId = _createLoan(request, "");

        // Assert final state
        assertEq(loanToken.ownerOf(loanId), lender);

        assertEq(loanAsset.balanceOf(lender), 0);
        assertEq(loanAsset.balanceOf(borrower), 100e18);
        assertEq(loanAsset.balanceOf(address(simpleLoan)), 0);

        assertEq(t1155.balanceOf(lender, 42), 0);
        assertEq(t1155.balanceOf(borrower, 42), 0);
        assertEq(t1155.balanceOf(address(simpleLoan), 42), 10e18);

        assertEq(revokedRequestNonce.isRequestNonceRevoked(borrower, request.nonce), true);
        assertEq(loanToken.loanContract(loanId), address(simpleLoan));
    }

    function test_shouldCreateLOAN_withCryptoKittiesCollateral() external {
        // TODO:
    }


    // Group of requests

    function test_shouldRevokeRequestsInGroup_whenAcceptingOneFromGroup() external {
        // Mint initial state
        loanAsset.mint(lender, 100e18);
        t1155.mint(borrower, 42, 10e18);

        // Sign requests
        request = PWNSimpleLoanSimpleRequest.Request({
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
        bytes memory signature1 = _sign(borrowerPK, simpleRequest.getRequestHash(request));
        bytes memory requestData1 = abi.encode(request);

        request.loanYield = 20e18;
        bytes memory signature2 = _sign(borrowerPK, simpleRequest.getRequestHash(request));
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
            loanFactoryContract: address(simpleRequest),
            loanFactoryData: requestData2,
            signature: signature2,
            loanAssetPermit: "",
            collateralPermit: ""
        });

        // Fail to accept other requests with same nonce
        vm.expectRevert(abi.encodeWithSelector(PWNError.NonceRevoked.selector));
        vm.prank(lender);
        simpleLoan.createLOAN({
            loanFactoryContract: address(simpleRequest),
            loanFactoryData: requestData1,
            signature: signature1,
            loanAssetPermit: "",
            collateralPermit: ""
        });
    }

}
