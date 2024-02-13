// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "MultiToken/interfaces/ICryptoKitties.sol";

import "@pwn-test/helper/token/T20.sol";
import "@pwn-test/helper/DeploymentTest.t.sol";


abstract contract UseCasesTest is DeploymentTest {

    // Token mainnet addresses
    address ZRX = 0xE41d2489571d322189246DaFA5ebDe1F4699F498; // no revert on failed
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // no revert on fallback
    address CULT = 0xf0f9D895aCa5c8678f706FB8216fa22957685A13; // tax token
    address CK = 0x06012c8cf97BEaD5deAe237070F9587f8E7A266d; // CryptoKitties
    address USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // no bool return on transfer(From)
    address BNB = 0xB8c77482e45F1F44dE1745F52C74426C631bDD52; // bool return only on transfer
    address DOODLE = 0x8a90CAb2b38dba80c64b7734e58Ee1dB38B8992e;

    T20 loanAsset;
    address lender = makeAddr("lender");
    address borrower = makeAddr("borrower");

    PWNSimpleLoanSimpleOffer.Offer offer;


    function setUp() public override {
        vm.createSelectFork("mainnet");

        super.setUp();

        loanAsset = new T20();
        loanAsset.mint(lender, 100e18);
        loanAsset.mint(borrower, 100e18);

        vm.prank(lender);
        loanAsset.approve(address(simpleLoan), type(uint256).max);

        vm.prank(borrower);
        loanAsset.approve(address(simpleLoan), type(uint256).max);

        offer = PWNSimpleLoanSimpleOffer.Offer({
            collateralCategory: MultiToken.Category.ERC20,
            collateralAddress: address(loanAsset),
            collateralId: 0,
            collateralAmount: 10e18,
            loanAssetAddress: address(loanAsset),
            loanAmount: 1e18,
            loanYield: 0,
            duration: 3600,
            expiration: 0,
            allowedBorrower: address(0),
            lender: lender,
            isPersistent: false,
            nonce: 0
        });
    }


    function _createLoan() internal returns (uint256) {
        return _createLoanRevertWith("");
    }

    function _createLoanRevertWith(bytes memory revertData) internal returns (uint256) {
        // Make offer
        vm.prank(lender);
        simpleLoanSimpleOffer.makeOffer(offer);

        bytes memory factoryData = simpleLoanSimpleOffer.encodeLoanTermsFactoryData(offer);

        // Create a loan
        if (revertData.length > 0) {
            vm.expectRevert(revertData);
        }
        vm.prank(borrower);
        return simpleLoan.createLOAN({
            loanTermsFactoryContract: address(simpleLoanSimpleOffer),
            loanTermsFactoryData: factoryData,
            signature: "",
            loanAssetPermit: "",
            collateralPermit: ""
        });
    }

}


contract InvalidCollateralAssetCategoryTest is UseCasesTest {

    // “No Revert on Failure” tokens can be used to steal from lender
    function testUseCase_shouldFail_when20CollateralPassedWith721Category() external {
        // Borrower has not ZRX tokens

        // Define offer
        offer.collateralCategory = MultiToken.Category.ERC721;
        offer.collateralAddress = ZRX;
        offer.collateralId = 10e18;
        offer.collateralAmount = 0;

        // Create loan
        _createLoanRevertWith(abi.encodeWithSelector(InvalidCollateralAsset.selector));
    }

    // Borrower can steal lender’s assets by using WETH as collateral
    function testUseCase_shouldFail_when20CollateralPassedWith1155Category() external {
        // Borrower has not WETH tokens

        // Define offer
        offer.collateralCategory = MultiToken.Category.ERC1155;
        offer.collateralAddress = WETH;
        offer.collateralId = 0;
        offer.collateralAmount = 10e18;

        // Create loan
        _createLoanRevertWith(abi.encodeWithSelector(InvalidCollateralAsset.selector));
    }

    // CryptoKitties token is locked when using it as ERC721 type collateral
    function testUseCase_shouldFail_whenCryptoKittiesCollateralPassedWith721Category() external {
        uint256 ckId = 42;

        // Mock CK
        address originalCkOwner = ICryptoKitties(CK).ownerOf(ckId);
        vm.prank(originalCkOwner);
        ICryptoKitties(CK).transfer(borrower, ckId);

        vm.prank(borrower);
        ICryptoKitties(CK).approve(address(simpleLoan), ckId);

        // Define offer
        offer.collateralCategory = MultiToken.Category.ERC721;
        offer.collateralAddress = CK;
        offer.collateralId = ckId;
        offer.collateralAmount = 0;

        // Create loan
        _createLoanRevertWith(abi.encodeWithSelector(InvalidCollateralAsset.selector));
    }

}


contract InvalidLoanAssetTest is UseCasesTest {

    function testUseCase_shouldFail_whenUsingERC721AsLoanAsset() external {
        uint256 doodleId = 42;

        // Mock DOODLE
        address originalDoodleOwner = IERC721(DOODLE).ownerOf(doodleId);
        vm.prank(originalDoodleOwner);
        IERC721(DOODLE).transferFrom(originalDoodleOwner, lender, doodleId);

        vm.prank(lender);
        IERC721(DOODLE).approve(address(simpleLoan), doodleId);

        // Define offer
        offer.loanAssetAddress = DOODLE;
        offer.loanAmount = doodleId;

        // Create loan
        _createLoanRevertWith(abi.encodeWithSelector(InvalidLoanAsset.selector));
    }

    function testUseCase_shouldFail_whenUsingCryptoKittiesAsLoanAsset() external {
        uint256 ckId = 42;

        // Mock CK
        address originalCkOwner = ICryptoKitties(CK).ownerOf(ckId);
        vm.prank(originalCkOwner);
        ICryptoKitties(CK).transfer(lender, ckId);

        vm.prank(lender);
        ICryptoKitties(CK).approve(address(simpleLoan), ckId);

        // Define offer
        offer.loanAssetAddress = CK;
        offer.loanAmount = ckId;

        // Create loan
        _createLoanRevertWith(abi.encodeWithSelector(InvalidLoanAsset.selector));
    }

}


contract TaxTokensTest is UseCasesTest {

    // Fee-on-transfer tokens can be locked in the vault
    function testUseCase_shouldFail_whenUsingTaxTokenAsCollateral() external {
        // Transfer CULT to borrower
        vm.prank(CULT);
        T20(CULT).transfer(borrower, 20e18);

        vm.prank(borrower);
        T20(CULT).approve(address(simpleLoan), type(uint256).max);

        // Define offer
        offer.collateralCategory = MultiToken.Category.ERC20;
        offer.collateralAddress = CULT;
        offer.collateralId = 0;
        offer.collateralAmount = 10e18;

        // Create loan
        _createLoanRevertWith(abi.encodeWithSelector(IncompleteTransfer.selector));
    }

    // Fee-on-transfer tokens can be locked in the vault
    function testUseCase_shouldFail_whenUsingTaxTokenAsCredit() external {
        // Transfer CULT to lender
        vm.prank(CULT);
        T20(CULT).transfer(lender, 20e18);

        vm.prank(lender);
        T20(CULT).approve(address(simpleLoan), type(uint256).max);

        // Define offer
        offer.loanAssetAddress = CULT;
        offer.loanAmount = 10e18;

        // Create loan
        _createLoanRevertWith(abi.encodeWithSelector(IncompleteTransfer.selector));
    }

}


contract IncompleteERC20TokensTest is UseCasesTest {

    function testUseCase_shouldPass_when20TokenTransferNotReturnsBool_whenUsedAsCollateral() external {
        address TetherTreasury = 0x5754284f345afc66a98fbB0a0Afe71e0F007B949;

        // Transfer USDT to borrower
        bool success;
        vm.prank(TetherTreasury);
        (success, ) = USDT.call(abi.encodeWithSignature("transfer(address,uint256)", borrower, 10e6));
        require(success);

        vm.prank(borrower);
        (success, ) = USDT.call(abi.encodeWithSignature("approve(address,uint256)", address(simpleLoan), type(uint256).max));
        require(success);

        // Define offer
        offer.collateralCategory = MultiToken.Category.ERC20;
        offer.collateralAddress = USDT;
        offer.collateralId = 0;
        offer.collateralAmount = 10e6; // USDT has 6 decimals

        // Check balance
        assertEq(T20(USDT).balanceOf(borrower), 10e6);
        assertEq(T20(USDT).balanceOf(address(simpleLoan)), 0);

        // Create loan
        uint256 loanId = _createLoan();

        // Check balance
        assertEq(T20(USDT).balanceOf(borrower), 0);
        assertEq(T20(USDT).balanceOf(address(simpleLoan)), 10e6);

        // Repay loan
        vm.prank(borrower);
        simpleLoan.repayLOAN({
            loanId: loanId,
            loanAssetPermit: ""
        });

        // Check balance
        assertEq(T20(USDT).balanceOf(borrower), 10e6);
        assertEq(T20(USDT).balanceOf(address(simpleLoan)), 0);
    }

    function testUseCase_shouldPass_when20TokenTransferNotReturnsBool_whenUsedAsCredit() external {
        address TetherTreasury = 0x5754284f345afc66a98fbB0a0Afe71e0F007B949;

        // Transfer USDT to lender
        bool success;
        vm.prank(TetherTreasury);
        (success, ) = USDT.call(abi.encodeWithSignature("transfer(address,uint256)", lender, 10e6));
        require(success);

        vm.prank(lender);
        (success, ) = USDT.call(abi.encodeWithSignature("approve(address,uint256)", address(simpleLoan), type(uint256).max));
        require(success);

        vm.prank(borrower);
        (success, ) = USDT.call(abi.encodeWithSignature("approve(address,uint256)", address(simpleLoan), type(uint256).max));
        require(success);

        // Define offer
        offer.loanAssetAddress = USDT;
        offer.loanAmount = 10e6; // USDT has 6 decimals

        // Check balance
        assertEq(T20(USDT).balanceOf(lender), 10e6);
        assertEq(T20(USDT).balanceOf(borrower), 0);

        // Create loan
        uint256 loanId = _createLoan();

        // Check balance
        assertEq(T20(USDT).balanceOf(lender), 0);
        assertEq(T20(USDT).balanceOf(borrower), 10e6);

        // Repay loan
        vm.prank(borrower);
        simpleLoan.repayLOAN({
            loanId: loanId,
            loanAssetPermit: ""
        });

        // Check balance
        assertEq(T20(USDT).balanceOf(lender), 0);
        assertEq(T20(USDT).balanceOf(address(simpleLoan)), 10e6);

        // Claim repaid loan
        vm.prank(lender);
        simpleLoan.claimLOAN(loanId);

        // Check balance
        assertEq(T20(USDT).balanceOf(lender), 10e6);
        assertEq(T20(USDT).balanceOf(address(simpleLoan)), 0);
    }

}
