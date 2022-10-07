// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

import "forge-std/Test.sol";

import "MultiToken/MultiToken.sol";

import "../../src/hub/PWNHub.sol";
import "../../src/hub/PWNHubTags.sol";
import "../../src/loan/type/PWNSimpleLoan.sol";
import "../../src/loan/PWNLOAN.sol";
import "../../src/loan-factory/simple-loan/offer/PWNSimpleLoanSimpleOffer.sol";
import "../../src/loan-factory/PWNRevokedOfferNonce.sol";
import "../../src/PWNConfig.sol";
import "../helpers/token/T20.sol";
import "../helpers/token/T721.sol";
import "../helpers/token/T1155.sol";


contract PWNSimpleLoanSimpleOfferIntegrationTest is Test {

    T20 t20;
    T721 t721;
    T1155 t1155;
    T20 loanAsset;

    PWNHub hub;
    PWNConfig config;
    PWNLOAN loanToken;
    PWNSimpleLoan simpleLoan;
    PWNRevokedOfferNonce revokedOfferNonce;
    PWNSimpleLoanSimpleOffer simpleOffer;

    uint256 lenderPK = uint256(777);
    address lender = vm.addr(lenderPK);
    address borrower = address(0x1001);
    bytes32 nonce = keccak256("nonce_1");
    PWNSimpleLoanSimpleOffer.Offer offer;

    function setUp() external {
        // Deploy realm
        hub = new PWNHub();
        config = new PWNConfig(0);

        loanToken = new PWNLOAN(address(hub));
        simpleLoan = new PWNSimpleLoan(address(hub), address(loanToken), address(config));

        revokedOfferNonce = new PWNRevokedOfferNonce(address(hub));
        simpleOffer = new PWNSimpleLoanSimpleOffer(address(hub), address(revokedOfferNonce));

        // Set hub tags
        hub.setTag(address(simpleLoan), PWNHubTags.LOAN, true);
        hub.setTag(address(simpleLoan), PWNHubTags.ACTIVE_LOAN, true);
        hub.setTag(address(simpleOffer), PWNHubTags.LOAN_FACTORY, true);
        hub.setTag(address(simpleOffer), PWNHubTags.LOAN_OFFER, true);

        // Deploy tokens
        t20 = new T20();
        t721 = new T721();
        t1155 = new T1155();
        loanAsset = new T20();

        // Default offer
        offer = PWNSimpleLoanSimpleOffer.Offer({
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
            isPersistent: false,
            nonce: nonce
        });
    }

    function _sign(uint256 pk, bytes32 digest) private returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _createLoan(PWNSimpleLoanSimpleOffer.Offer memory _offer, bytes memory revertMessage) private returns (uint256) {
        // Sign offer
        bytes memory signature = _sign(lenderPK, simpleOffer.getOfferHash(_offer));

        // Mint initial state
        loanAsset.mint(lender, 100e18);

        // Approve loan asset
        vm.prank(lender);
        loanAsset.approve(address(simpleLoan), 100e18);

        // Create LOAN
        if (keccak256(revertMessage) != keccak256("")) {
            vm.expectRevert(revertMessage);
        }
        vm.prank(borrower);
        return simpleLoan.createLOAN({
            loanFactoryContract: address(simpleOffer),
            loanFactoryData: abi.encode(_offer),
            signature: signature,
            loanAssetPermit: "",
            collateralPermit: ""
        });
    }

    function _createERC20Loan() private returns (uint256) {
        // Offer
        offer.collateralCategory = MultiToken.Category.ERC20;
        offer.collateralAddress = address(t20);
        offer.collateralId = 0;
        offer.collateralAmount = 10e18;

        // Mint initial state
        t20.mint(borrower, 10e18);

        // Approve collateral
        vm.prank(borrower);
        t20.approve(address(simpleLoan), 10e18);

        // Create LOAN
        return _createLoan(offer, "");
    }

    function _createERC721Loan() private returns (uint256) {
        // Offer
        offer.collateralCategory = MultiToken.Category.ERC721;
        offer.collateralAddress = address(t721);
        offer.collateralId = 42;
        offer.collateralAmount = 1;

        // Mint initial state
        t721.mint(borrower, 42);

        // Approve collateral
        vm.prank(borrower);
        t721.approve(address(simpleLoan), 42);

        // Create LOAN
        return _createLoan(offer, "");
    }

    function _createERC1155Loan() private returns (uint256) {
        return _createERC1155LoanFailing("");
    }

    function _createERC1155LoanFailing(bytes memory revertMessage) private returns (uint256) {
        // Offer
        offer.collateralCategory = MultiToken.Category.ERC1155;
        offer.collateralAddress = address(t1155);
        offer.collateralId = 42;
        offer.collateralAmount = 10e18;

        // Mint initial state
        t1155.mint(borrower, 42, 10e18);

        // Approve collateral
        vm.prank(borrower);
        t1155.setApprovalForAll(address(simpleLoan), true);

        // Create LOAN
        return _createLoan(offer, revertMessage);
    }

    function _repayLoan(uint256 loanId) private {
        _repayLoanFailing(loanId, "");
    }

    function _repayLoanFailing(uint256 loanId, bytes memory revertMessage) private {
        // Get the yield by farming 100000% APR food tokens
        loanAsset.mint(borrower, 10e18);

        // Approve loan asset
        vm.prank(borrower);
        loanAsset.approve(address(simpleLoan), 110e18);

        // Repay loan
        if (keccak256(revertMessage) != keccak256("")) {
            vm.expectRevert(revertMessage);
        }
        vm.prank(borrower);
        simpleLoan.repayLoan(loanId, "");
    }


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

        assertEq(revokedOfferNonce.revokedOfferNonces(lender, offer.nonce), true);
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

        assertEq(revokedOfferNonce.revokedOfferNonces(lender, offer.nonce), true);
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

        assertEq(revokedOfferNonce.revokedOfferNonces(lender, nonce), true);
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
        vm.warp(block.timestamp + uint256(offer.duration));
        _repayLoanFailing(loanId, "Loan is expired");
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


    // Protocol integrity

    function test_shouldFailCreatingLOANOnNotActiveLoanContract() external {
        // Remove ACTIVE_LOAN tag
        hub.setTag(address(simpleLoan), PWNHubTags.ACTIVE_LOAN, false);

        // Try to create LOAN
        _createERC1155LoanFailing("Caller is not active loan");
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

    function test_shouldFail_whenCallerIsNotActiveLoan() external {
        // Remove ACTIVE_LOAN tag
        hub.setTag(address(simpleLoan), PWNHubTags.ACTIVE_LOAN, false);

        vm.expectRevert("Caller is not active loan");
        vm.prank(address(simpleLoan));
        simpleOffer.createLOAN(borrower, "", ""); // Offer data are not important in this test
    }

    function test_shouldFail_whenPassingInvalidOfferContract() external {
        // Remove LOAN_FACTORY tag
        hub.setTag(address(simpleOffer), PWNHubTags.LOAN_FACTORY, false);

        // Try to create LOAN
        _createERC1155LoanFailing("Given contract is not loan factory");
    }


    // Group of offers

    function test_shouldRevokeOffesInGroup_whenAcceptingOneFromGroup() external {
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
        vm.expectRevert("Offer is revoked or has been accepted");
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
