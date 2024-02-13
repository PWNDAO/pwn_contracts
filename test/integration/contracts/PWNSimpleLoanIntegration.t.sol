// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "@pwn/PWNErrors.sol";

import "@pwn-test/integration/BaseIntegrationTest.t.sol";


contract PWNSimpleLoanIntegrationTest is BaseIntegrationTest {

    // Create LOAN

    function test_shouldCreateLOAN_fromSimpleOffer() external {
        PWNSimpleLoanSimpleOffer.Offer memory offer = PWNSimpleLoanSimpleOffer.Offer({
            collateralCategory: MultiToken.Category.ERC1155,
            collateralAddress: address(t1155),
            collateralId: 42,
            collateralAmount: 10e18,
            loanAssetAddress: address(loanAsset),
            loanAmount: 100e18,
            loanYield: 10e18,
            duration: 3600,
            expiration: 0,
            allowedBorrower: borrower,
            lender: lender,
            isPersistent: false,
            nonce: nonce
        });

        // Mint initial state
        t1155.mint(borrower, 42, 10e18);

        // Approve collateral
        vm.prank(borrower);
        t1155.setApprovalForAll(address(simpleLoan), true);

        // Sign offer
        bytes memory signature = _sign(lenderPK, simpleLoanSimpleOffer.getOfferHash(offer));

        // Mint initial state
        loanAsset.mint(lender, 100e18);

        // Approve loan asset
        vm.prank(lender);
        loanAsset.approve(address(simpleLoan), 100e18);

        // Loan factory data (need for vm.prank to work properly when creating a loan)
        bytes memory loanTermsFactoryData = simpleLoanSimpleOffer.encodeLoanTermsFactoryData(offer);

        // Create LOAN
        vm.prank(borrower);
        uint256 loanId = simpleLoan.createLOAN({
            loanTermsFactoryContract: address(simpleLoanSimpleOffer),
            loanTermsFactoryData: loanTermsFactoryData,
            signature: signature,
            loanAssetPermit: "",
            collateralPermit: ""
        });

        // Assert final state
        assertEq(loanToken.ownerOf(loanId), lender);

        assertEq(loanAsset.balanceOf(lender), 0);
        assertEq(loanAsset.balanceOf(borrower), 100e18);
        assertEq(loanAsset.balanceOf(address(simpleLoan)), 0);

        assertEq(t1155.balanceOf(lender, 42), 0);
        assertEq(t1155.balanceOf(borrower, 42), 0);
        assertEq(t1155.balanceOf(address(simpleLoan), 42), 10e18);

        assertEq(revokedOfferNonce.isNonceRevoked(lender, nonce), true);
        assertEq(loanToken.loanContract(loanId), address(simpleLoan));
    }

    function test_shouldCreateLOAN_fromListOffer() external {
        bytes32 id1Hash = keccak256(abi.encodePacked(uint256(52)));
        bytes32 id2Hash = keccak256(abi.encodePacked(uint256(42)));
        bytes32 collateralIdsWhitelistMerkleRoot = keccak256(abi.encodePacked(id1Hash, id2Hash));

        PWNSimpleLoanListOffer.Offer memory offer = PWNSimpleLoanListOffer.Offer({
            collateralCategory: MultiToken.Category.ERC1155,
            collateralAddress: address(t1155),
            collateralIdsWhitelistMerkleRoot: collateralIdsWhitelistMerkleRoot,
            collateralAmount: 10e18,
            loanAssetAddress: address(loanAsset),
            loanAmount: 100e18,
            loanYield: 10e18,
            duration: 3600,
            expiration: 0,
            allowedBorrower: borrower,
            lender: lender,
            isPersistent: false,
            nonce: nonce
        });

        PWNSimpleLoanListOffer.OfferValues memory offerValues = PWNSimpleLoanListOffer.OfferValues({
            collateralId: 42,
            merkleInclusionProof: new bytes32[](1)
        });
        offerValues.merkleInclusionProof[0] = id1Hash;

        // Mint initial state
        t1155.mint(borrower, 42, 10e18);

        // Approve collateral
        vm.prank(borrower);
        t1155.setApprovalForAll(address(simpleLoan), true);

        // Sign offer
        bytes memory signature = _sign(lenderPK, simpleLoanListOffer.getOfferHash(offer));

        // Mint initial state
        loanAsset.mint(lender, 100e18);

        // Approve loan asset
        vm.prank(lender);
        loanAsset.approve(address(simpleLoan), 100e18);

        // Loan factory data (need for vm.prank to work properly when creating a loan)
        bytes memory loanTermsFactoryData = simpleLoanListOffer.encodeLoanTermsFactoryData(offer, offerValues);

        // Create LOAN
        vm.prank(borrower);
        uint256 loanId = simpleLoan.createLOAN({
            loanTermsFactoryContract: address(simpleLoanListOffer),
            loanTermsFactoryData: loanTermsFactoryData,
            signature: signature,
            loanAssetPermit: "",
            collateralPermit: ""
        });

        // Assert final state
        assertEq(loanToken.ownerOf(loanId), lender);

        assertEq(loanAsset.balanceOf(lender), 0);
        assertEq(loanAsset.balanceOf(borrower), 100e18);
        assertEq(loanAsset.balanceOf(address(simpleLoan)), 0);

        assertEq(t1155.balanceOf(lender, 42), 0);
        assertEq(t1155.balanceOf(borrower, 42), 0);
        assertEq(t1155.balanceOf(address(simpleLoan), 42), 10e18);

        assertEq(revokedOfferNonce.isNonceRevoked(lender, nonce), true);
        assertEq(loanToken.loanContract(loanId), address(simpleLoan));
    }

    function test_shouldCreateLOAN_fromSimpleRequest() external {
        PWNSimpleLoanSimpleRequest.Request memory request = PWNSimpleLoanSimpleRequest.Request({
            collateralCategory: MultiToken.Category.ERC1155,
            collateralAddress: address(t1155),
            collateralId: 42,
            collateralAmount: 10e18,
            loanAssetAddress: address(loanAsset),
            loanAmount: 100e18,
            loanYield: 10e18,
            duration: 3600,
            expiration: 0,
            borrower: borrower,
            lender: lender,
            nonce: nonce
        });

        // Mint initial state
        t1155.mint(borrower, 42, 10e18);

        // Approve collateral
        vm.prank(borrower);
        t1155.setApprovalForAll(address(simpleLoan), true);

        // Sign request
        bytes memory signature = _sign(borrowerPK, simpleLoanSimpleRequest.getRequestHash(request));

        // Mint initial state
        loanAsset.mint(lender, 100e18);

        // Approve loan asset
        vm.prank(lender);
        loanAsset.approve(address(simpleLoan), 100e18);

        // Loan factory data (need for vm.prank to work properly when creating a loan)
        bytes memory loanTermsFactoryData = simpleLoanSimpleRequest.encodeLoanTermsFactoryData(request);

        // Create LOAN
        vm.prank(lender);
        uint256 loanId = simpleLoan.createLOAN({
            loanTermsFactoryContract: address(simpleLoanSimpleRequest),
            loanTermsFactoryData: loanTermsFactoryData,
            signature: signature,
            loanAssetPermit: "",
            collateralPermit: ""
        });

        // Assert final state
        assertEq(loanToken.ownerOf(loanId), lender);

        assertEq(loanAsset.balanceOf(lender), 0);
        assertEq(loanAsset.balanceOf(borrower), 100e18);
        assertEq(loanAsset.balanceOf(address(simpleLoan)), 0);

        assertEq(t1155.balanceOf(lender, 42), 0);
        assertEq(t1155.balanceOf(borrower, 42), 0);
        assertEq(t1155.balanceOf(address(simpleLoan), 42), 10e18);

        assertEq(revokedRequestNonce.isNonceRevoked(borrower, request.nonce), true);
        assertEq(loanToken.loanContract(loanId), address(simpleLoan));
    }


    // Different collateral types

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

        assertEq(revokedOfferNonce.isNonceRevoked(lender, defaultOffer.nonce), true);
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

        assertEq(revokedOfferNonce.isNonceRevoked(lender, defaultOffer.nonce), true);
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

        assertEq(revokedOfferNonce.isNonceRevoked(lender, defaultOffer.nonce), true);
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

        // Default on a loan
        uint256 expiration = block.timestamp + uint256(defaultOffer.duration);
        vm.warp(expiration);

        // Try to repay loan
        _repayLoanFailing(
            loanId,
            abi.encodeWithSelector(LoanDefaulted.selector, uint40(expiration))
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

    function test_shouldClaimDefaultedLOAN() external {
        // Create LOAN
        uint256 loanId = _createERC1155Loan();

        // Loan defaulted
        vm.warp(block.timestamp + uint256(defaultOffer.duration));

        // Claim defaulted loan
        vm.prank(lender);
        simpleLoan.claimLOAN(loanId);

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
