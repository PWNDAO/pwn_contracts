// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "MultiToken/MultiToken.sol";

import "@pwn-test/helper/token/T20.sol";
import "@pwn-test/helper/token/T721.sol";
import "@pwn-test/helper/token/T1155.sol";
import "@pwn-test/helper/DeploymentTest.t.sol";


abstract contract BaseIntegrationTest is DeploymentTest {

    T20 t20;
    T721 t721;
    T1155 t1155;
    T20 loanAsset;

    uint256 lenderPK = uint256(777);
    address lender = vm.addr(lenderPK);
    uint256 borrowerPK = uint256(888);
    address borrower = vm.addr(borrowerPK);
    uint256 nonce = uint256(keccak256("nonce_1"));
    PWNSimpleLoanSimpleOffer.Offer defaultOffer;

    function setUp() public override {
        super.setUp();

        // Deploy tokens
        t20 = new T20();
        t721 = new T721();
        t1155 = new T1155();
        loanAsset = new T20();

        // Default offer
        defaultOffer = PWNSimpleLoanSimpleOffer.Offer({
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
            lateRepaymentEnabled: false,
            nonce: nonce
        });
    }


    function _sign(uint256 pk, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    // Create from offer

    function _createERC20Loan() internal returns (uint256) {
        // Offer
        defaultOffer.collateralCategory = MultiToken.Category.ERC20;
        defaultOffer.collateralAddress = address(t20);
        defaultOffer.collateralId = 0;
        defaultOffer.collateralAmount = 10e18;

        // Mint initial state
        t20.mint(borrower, 10e18);

        // Approve collateral
        vm.prank(borrower);
        t20.approve(address(simpleLoan), 10e18);

        // Create LOAN
        return _createLoan(defaultOffer, "");
    }

    function _createERC721Loan() internal returns (uint256) {
        // Offer
        defaultOffer.collateralCategory = MultiToken.Category.ERC721;
        defaultOffer.collateralAddress = address(t721);
        defaultOffer.collateralId = 42;
        defaultOffer.collateralAmount = 0;

        // Mint initial state
        t721.mint(borrower, 42);

        // Approve collateral
        vm.prank(borrower);
        t721.approve(address(simpleLoan), 42);

        // Create LOAN
        return _createLoan(defaultOffer, "");
    }

    function _createERC1155Loan() internal returns (uint256) {
        return _createERC1155LoanFailing("");
    }

    function _createERC1155LoanFailing(bytes memory revertData) internal returns (uint256) {
        // Offer
        defaultOffer.collateralCategory = MultiToken.Category.ERC1155;
        defaultOffer.collateralAddress = address(t1155);
        defaultOffer.collateralId = 42;
        defaultOffer.collateralAmount = 10e18;

        // Mint initial state
        t1155.mint(borrower, 42, 10e18);

        // Approve collateral
        vm.prank(borrower);
        t1155.setApprovalForAll(address(simpleLoan), true);

        // Create LOAN
        return _createLoan(defaultOffer, revertData);
    }

    function _createLoan(PWNSimpleLoanSimpleOffer.Offer memory _offer, bytes memory revertData) private returns (uint256) {
        // Sign offer
        bytes memory signature = _sign(lenderPK, simpleLoanSimpleOffer.getOfferHash(_offer));

        // Mint initial state
        loanAsset.mint(lender, 100e18);

        // Approve loan asset
        vm.prank(lender);
        loanAsset.approve(address(simpleLoan), 100e18);

        // Loan factory data (need for vm.prank to work properly when creating a loan)
        bytes memory loanTermsFactoryData = simpleLoanSimpleOffer.encodeLoanTermsFactoryData(_offer);

        // Create LOAN
        if (keccak256(revertData) != keccak256("")) {
            vm.expectRevert(revertData);
        }
        vm.prank(borrower);
        return simpleLoan.createLOAN({
            loanTermsFactoryContract: address(simpleLoanSimpleOffer),
            loanTermsFactoryData: loanTermsFactoryData,
            signature: signature,
            loanAssetPermit: "",
            collateralPermit: ""
        });
    }

    // Repay

    function _repayLoan(uint256 loanId) internal {
        _repayLoanFailing(loanId, "");
    }

    function _repayLoanFailing(uint256 loanId, bytes memory revertData) internal {
        // Get the yield by farming 100000% APR food tokens
        loanAsset.mint(borrower, 10e18);

        // Approve loan asset
        vm.prank(borrower);
        loanAsset.approve(address(simpleLoan), 110e18);

        // Repay loan
        if (keccak256(revertData) != keccak256("")) {
            vm.expectRevert(revertData);
        }
        vm.prank(borrower);
        simpleLoan.repayLOAN(loanId, "");
    }

}