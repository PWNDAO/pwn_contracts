// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "MultiToken/MultiToken.sol";

import "@pwn/hub/PWNHubTags.sol";
import "@pwn/loan/terms/simple/loan/PWNSimpleLoan.sol";
import "@pwn/loan/terms/PWNLOANTerms.sol";
import "@pwn/PWNErrors.sol";

import "@pwn-test/helper/token/T20.sol";
import "@pwn-test/helper/token/T721.sol";


abstract contract PWNSimpleLoanTest is Test {

    bytes32 internal constant LOANS_SLOT = bytes32(uint256(0)); // `LOANs` mapping position

    uint256 public constant MAX_EXPIRATION_EXTENSION = 2_592_000; // 30 days

    PWNSimpleLoan loan;
    address hub = makeAddr("hub");
    address loanToken = makeAddr("loanToken");
    address config = makeAddr("config");
    address categoryRegistry = makeAddr("categoryRegistry");
    address feeCollector = makeAddr("feeCollector");
    address alice = makeAddr("alice");
    address loanFactory = makeAddr("loanFactory");
    uint256 loanId = 42;
    address lender = makeAddr("lender");
    address borrower = makeAddr("borrower");
    PWNSimpleLoan.LOAN simpleLoan;
    PWNSimpleLoan.LOAN nonExistingLoan;
    PWNLOANTerms.Simple simpleLoanTerms;
    T20 fungibleAsset;
    T721 nonFungibleAsset;

    bytes loanFactoryData;
    bytes signature;
    bytes loanAssetPermit;
    bytes collateralPermit;
    bytes32 loanFactoryDataHash;

    event LOANCreated(uint256 indexed loanId, PWNLOANTerms.Simple terms, bytes32 indexed factoryDataHash, address indexed factoryAddress);
    event LOANPaidBack(uint256 indexed loanId);
    event LOANClaimed(uint256 indexed loanId, bool indexed defaulted);
    event LOANExpirationDateExtended(uint256 indexed loanId, uint40 extendedExpirationDate);

    constructor() {
        vm.etch(hub, bytes("data"));
        vm.etch(loanToken, bytes("data"));
        vm.etch(loanFactory, bytes("data"));
        vm.etch(config, bytes("data"));
    }

    function setUp() virtual public {
        loan = new PWNSimpleLoan(hub, loanToken, config, categoryRegistry);
        fungibleAsset = new T20();
        nonFungibleAsset = new T721();

        fungibleAsset.mint(lender, 6831);
        fungibleAsset.mint(borrower, 6831);
        fungibleAsset.mint(address(this), 6831);
        fungibleAsset.mint(address(loan), 6831);
        nonFungibleAsset.mint(borrower, 2);

        vm.prank(lender);
        fungibleAsset.approve(address(loan), type(uint256).max);

        vm.prank(borrower);
        fungibleAsset.approve(address(loan), type(uint256).max);

        vm.prank(address(this));
        fungibleAsset.approve(address(loan), type(uint256).max);

        vm.prank(borrower);
        nonFungibleAsset.approve(address(loan), 2);

        loanFactoryData = "";
        signature = "";
        loanAssetPermit = "";
        collateralPermit = "";

        simpleLoan = PWNSimpleLoan.LOAN({
            status: 2,
            borrower: borrower,
            expiration: uint40(block.timestamp + 40039),
            loanAssetAddress: address(fungibleAsset),
            loanRepayAmount: 6731,
            collateral: MultiToken.ERC721(address(nonFungibleAsset), 2),
            originalLender: lender
        });

        simpleLoanTerms = PWNLOANTerms.Simple({
            lender: lender,
            borrower: borrower,
            expiration: uint40(block.timestamp + 40039),
            collateral: MultiToken.ERC721(address(nonFungibleAsset), 2),
            asset: MultiToken.ERC20(address(fungibleAsset), 100),
            loanRepayAmount: 6731
        });

        nonExistingLoan = PWNSimpleLoan.LOAN({
            status: 0,
            borrower: address(0),
            expiration: 0,
            loanAssetAddress: address(0),
            loanRepayAmount: 0,
            collateral: MultiToken.Asset(MultiToken.Category(0), address(0), 0, 0),
            originalLender: address(0)
        });

        loanFactoryDataHash = keccak256("factoryData");

        vm.mockCall(
            address(fungibleAsset),
            abi.encodeWithSignature("permit(address,address,uint256,uint256,uint8,bytes32,bytes32)"),
            abi.encode()
        );
        vm.mockCall(
            categoryRegistry,
            abi.encodeWithSignature("registeredCategoryValue(address)"),
            abi.encode(type(uint8).max)
        );
    }


    function _assertLOANEq(PWNSimpleLoan.LOAN memory _simpleLoan1, PWNSimpleLoan.LOAN memory _simpleLoan2) internal {
        assertEq(_simpleLoan1.status, _simpleLoan2.status);
        assertEq(_simpleLoan1.borrower, _simpleLoan2.borrower);
        assertEq(_simpleLoan1.expiration, _simpleLoan2.expiration);
        assertEq(_simpleLoan1.loanAssetAddress, _simpleLoan2.loanAssetAddress);
        assertEq(_simpleLoan1.loanRepayAmount, _simpleLoan2.loanRepayAmount);
        assertEq(uint8(_simpleLoan1.collateral.category), uint8(_simpleLoan2.collateral.category));
        assertEq(_simpleLoan1.collateral.assetAddress, _simpleLoan2.collateral.assetAddress);
        assertEq(_simpleLoan1.collateral.id, _simpleLoan2.collateral.id);
        assertEq(_simpleLoan1.collateral.amount, _simpleLoan2.collateral.amount);
        assertEq(_simpleLoan1.originalLender, _simpleLoan2.originalLender);
    }

    function _assertLOANEq(uint256 _loanId, PWNSimpleLoan.LOAN memory _simpleLoan) internal {
        uint256 loanSlot = uint256(keccak256(abi.encode(
            _loanId,
            LOANS_SLOT
        )));
        // Status, borrower address & expiration in one storage slot
        _assertLOANWord(loanSlot + 0, abi.encodePacked(uint48(0), _simpleLoan.expiration, _simpleLoan.borrower, _simpleLoan.status));
        // Loan asset address
        _assertLOANWord(loanSlot + 1, abi.encodePacked(uint96(0), _simpleLoan.loanAssetAddress));
        // Loan repay amount
        _assertLOANWord(loanSlot + 2, abi.encodePacked(_simpleLoan.loanRepayAmount));
        // Collateral category & collateral asset address in one storage slot
        _assertLOANWord(loanSlot + 3, abi.encodePacked(uint88(0), _simpleLoan.collateral.assetAddress, _simpleLoan.collateral.category));
        // Collateral id
        _assertLOANWord(loanSlot + 4, abi.encodePacked(_simpleLoan.collateral.id));
        // Collateral amount
        _assertLOANWord(loanSlot + 5, abi.encodePacked(_simpleLoan.collateral.amount));
        // Original lender
        _assertLOANWord(loanSlot + 6, abi.encodePacked(uint96(0), _simpleLoan.originalLender));
    }

    function _mockLOAN(uint256 _loanId, PWNSimpleLoan.LOAN memory _simpleLoan) internal {
        uint256 loanSlot = uint256(keccak256(abi.encode(
            _loanId,
            LOANS_SLOT
        )));
        // Status, borrower address & expiration in one storage slot
        _storeLOANWord(loanSlot + 0, abi.encodePacked(uint48(0), _simpleLoan.expiration, _simpleLoan.borrower, _simpleLoan.status));
        // Loan asset address
        _storeLOANWord(loanSlot + 1, abi.encodePacked(uint96(0), _simpleLoan.loanAssetAddress));
        // Loan repay amount
        _storeLOANWord(loanSlot + 2, abi.encodePacked(_simpleLoan.loanRepayAmount));
        // Collateral category & collateral asset address in one storage slot
        _storeLOANWord(loanSlot + 3, abi.encodePacked(uint88(0), _simpleLoan.collateral.assetAddress, _simpleLoan.collateral.category));
        // Collateral id
        _storeLOANWord(loanSlot + 4, abi.encodePacked(_simpleLoan.collateral.id));
        // Collateral amount
        _storeLOANWord(loanSlot + 5, abi.encodePacked(_simpleLoan.collateral.amount));
        // Original lender
        _storeLOANWord(loanSlot + 6, abi.encodePacked(uint96(0), _simpleLoan.originalLender));
    }


    function _assertLOANWord(uint256 wordSlot, bytes memory word) private {
        assertEq(
            abi.encodePacked(vm.load(address(loan), bytes32(wordSlot))),
            word
        );
    }

    function _storeLOANWord(uint256 wordSlot, bytes memory word) private {
        vm.store(address(loan), bytes32(wordSlot), _bytesToBytes32(word));
    }

    function _bytesToBytes32(bytes memory _bytes) private pure returns (bytes32 _bytes32) {
        assembly {
            _bytes32 := mload(add(_bytes, 32))
        }
    }

}


/*----------------------------------------------------------*|
|*  # CREATE LOAN                                           *|
|*----------------------------------------------------------*/

contract PWNSimpleLoan_CreateLoan_Test is PWNSimpleLoanTest {

    function setUp() override public {
        super.setUp();

        vm.mockCall(
            config,
            abi.encodeWithSignature("fee()"),
            abi.encode(0)
        );
        vm.mockCall(
            config,
            abi.encodeWithSignature("feeCollector()"),
            abi.encode(feeCollector)
        );

        vm.mockCall(
            hub,
            abi.encodeWithSignature("hasTag(address,bytes32)"),
            abi.encode(false)
        );
        vm.mockCall(
            hub,
            abi.encodeWithSignature("hasTag(address,bytes32)", loanFactory, PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY),
            abi.encode(true)
        );

        vm.mockCall(
            loanFactory,
            abi.encodeWithSignature("createLOANTerms(address,bytes,bytes)"),
            abi.encode(simpleLoanTerms, loanFactoryDataHash)
        );

        vm.mockCall(
            loanToken,
            abi.encodeWithSignature("mint(address)"),
            abi.encode(loanId)
        );
    }


    function test_shouldFail_whenLoanFactoryContractIsNotTaggerInPWNHub() external {
        address notLoanFactory = address(0);

        vm.expectRevert(abi.encodeWithSelector(CallerMissingHubTag.selector, PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY));
        loan.createLOAN(notLoanFactory, loanFactoryData, signature, loanAssetPermit, collateralPermit);
    }

    function test_shouldGetLOANTermsStructFromGivenFactoryContract() external {
        loanFactoryData = abi.encode(1, 2, "data");
        signature = abi.encode("other data", "whaat?", uint256(312312));

        vm.expectCall(
            address(loanFactory),
            abi.encodeWithSignature("createLOANTerms(address,bytes,bytes)", address(this), loanFactoryData, signature)
        );

        loan.createLOAN(loanFactory, loanFactoryData, signature, loanAssetPermit, collateralPermit);
    }

    function test_shouldFailWhenLoanAssetIsInvalid() external {
        vm.mockCall(
            categoryRegistry,
            abi.encodeWithSignature("registeredCategoryValue(address)", simpleLoanTerms.asset.assetAddress),
            abi.encode(1)
        );

        vm.mockCall(
            loanFactory,
            abi.encodeWithSignature("createLOANTerms(address,bytes,bytes)"),
            abi.encode(simpleLoanTerms, loanFactoryDataHash)
        );

        vm.expectRevert(InvalidLoanAsset.selector);
        loan.createLOAN(loanFactory, loanFactoryData, signature, loanAssetPermit, collateralPermit);
    }

    function test_shouldFailWhenCollateralAssetIsInvalid() external {
        vm.mockCall(
            categoryRegistry,
            abi.encodeWithSignature("registeredCategoryValue(address)", simpleLoanTerms.collateral.assetAddress),
            abi.encode(0)
        );

        vm.mockCall(
            loanFactory,
            abi.encodeWithSignature("createLOANTerms(address,bytes,bytes)"),
            abi.encode(simpleLoanTerms, loanFactoryDataHash)
        );

        vm.expectRevert(InvalidCollateralAsset.selector);
        loan.createLOAN(loanFactory, loanFactoryData, signature, loanAssetPermit, collateralPermit);
    }

    function test_shouldMintLOANToken() external {
        vm.expectCall(
            address(loanToken),
            abi.encodeWithSignature("mint(address)", lender)
        );

        loan.createLOAN(loanFactory, loanFactoryData, signature, loanAssetPermit, collateralPermit);
    }

    function test_shouldStoreLoanData() external {
        loan.createLOAN(loanFactory, loanFactoryData, signature, loanAssetPermit, collateralPermit);

        _assertLOANEq(loanId, simpleLoan);
    }

    function test_shouldTransferCollateral_fromBorrower_toVault() external {
        simpleLoanTerms.collateral.category = MultiToken.Category.ERC20;
        simpleLoanTerms.collateral.assetAddress = address(fungibleAsset);
        simpleLoanTerms.collateral.id = 0;
        simpleLoanTerms.collateral.amount = 100;

        vm.mockCall(
            loanFactory,
            abi.encodeWithSignature("createLOANTerms(address,bytes,bytes)"),
            abi.encode(simpleLoanTerms, loanFactoryDataHash)
        );

        collateralPermit = abi.encodePacked(uint256(1), uint256(2), uint256(3), uint8(4));

        vm.expectCall(
            simpleLoanTerms.collateral.assetAddress,
            abi.encodeWithSignature(
                "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
                borrower, address(loan), simpleLoanTerms.collateral.amount, 1, uint8(4), uint256(2), uint256(3)
            )
        );
        vm.expectCall(
            simpleLoanTerms.collateral.assetAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", borrower, address(loan), simpleLoanTerms.collateral.amount)
        );

        loan.createLOAN(loanFactory, loanFactoryData, signature, loanAssetPermit, collateralPermit);
    }

    function test_shouldTransferLoanAsset_fromLender_toBorrower_whenZeroFees() external {
        loanAssetPermit = abi.encodePacked(uint256(1), uint256(2), uint256(3), uint8(4));

        vm.expectCall(
            simpleLoanTerms.asset.assetAddress,
            abi.encodeWithSignature(
                "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
                lender, address(loan), simpleLoanTerms.asset.amount, 1, uint8(4), uint256(2), uint256(3)
            )
        );
        vm.expectCall(
            simpleLoanTerms.asset.assetAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", lender, borrower, simpleLoanTerms.asset.amount)
        );

        loan.createLOAN(loanFactory, loanFactoryData, signature, loanAssetPermit, collateralPermit);
    }

    function test_shouldTransferLoanAsset_fromLender_toBorrowerAndFeeCollector_whenNonZeroFee() external {
        vm.mockCall(
            config,
            abi.encodeWithSignature("fee()"),
            abi.encode(1000)
        );

        loanAssetPermit = abi.encodePacked(uint256(1), uint256(2), uint256(3), uint8(4));

        vm.expectCall(
            simpleLoanTerms.asset.assetAddress,
            abi.encodeWithSignature(
                "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
                lender, address(loan), simpleLoanTerms.asset.amount, 1, uint8(4), uint256(2), uint256(3)
            )
        );
        // Fee transfer
        vm.expectCall(
            simpleLoanTerms.asset.assetAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", lender, feeCollector, 10)
        );
        // Updated amount transfer
        vm.expectCall(
            simpleLoanTerms.asset.assetAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", lender, borrower, 90)
        );

        loan.createLOAN(loanFactory, loanFactoryData, signature, loanAssetPermit, collateralPermit);
    }

    function test_shouldEmitEvent_LOANCreated() external {
        vm.expectEmit(true, true, true, true);
        emit LOANCreated(loanId, simpleLoanTerms, loanFactoryDataHash, loanFactory);

        loan.createLOAN(loanFactory, loanFactoryData, signature, loanAssetPermit, collateralPermit);
    }

    function test_shouldReturnCreatedLoanId() external {
        uint256 createdLoanId = loan.createLOAN(loanFactory, loanFactoryData, signature, loanAssetPermit, collateralPermit);

        assertEq(createdLoanId, loanId);
    }

}


/*----------------------------------------------------------*|
|*  # REPAY LOAN                                            *|
|*----------------------------------------------------------*/

contract PWNSimpleLoan_RepayLOAN_Test is PWNSimpleLoanTest {

    address notOriginalLender = makeAddr("notOriginalLender");

    function setUp() override public {
        super.setUp();

        vm.mockCall(
            loanToken, abi.encodeWithSignature("ownerOf(uint256)", loanId), abi.encode(lender)
        );

        // Move collateral to vault
        vm.prank(borrower);
        nonFungibleAsset.transferFrom(borrower, address(loan), 2);
    }

    function _LOANTokenNotOwnedByOriginalLender() internal {
        vm.mockCall(
            loanToken, abi.encodeWithSignature("ownerOf(uint256)", loanId), abi.encode(notOriginalLender)
        );
    }


    function test_shouldFail_whenLoanDoesNotExist() external {
        simpleLoan.status = 0;
        _mockLOAN(loanId, simpleLoan);

        vm.expectRevert(abi.encodeWithSelector(NonExistingLoan.selector));
        loan.repayLOAN(loanId, loanAssetPermit);
    }

    function test_shouldFail_whenLoanIsNotRunning() external {
        simpleLoan.status = 3;
        _mockLOAN(loanId, simpleLoan);

        vm.expectRevert(abi.encodeWithSelector(InvalidLoanStatus.selector, 3));
        loan.repayLOAN(loanId, loanAssetPermit);
    }

    function test_shouldFail_whenLoanIsExpired() external {
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.expiration + 10000);

        vm.expectRevert(abi.encodeWithSelector(LoanDefaulted.selector, simpleLoan.expiration));
        loan.repayLOAN(loanId, loanAssetPermit);
    }

    function test_shouldCallPermit_whenProvided() external {
        _mockLOAN(loanId, simpleLoan);
        loanAssetPermit = abi.encodePacked(uint256(1), uint256(2), uint256(3), uint8(4));

        vm.expectCall(
            simpleLoan.loanAssetAddress,
            abi.encodeWithSignature(
                "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
                borrower, address(loan), simpleLoan.loanRepayAmount, 1, uint8(4), uint256(2), uint256(3)
            )
        );

        vm.prank(borrower);
        loan.repayLOAN(loanId, loanAssetPermit);
    }

    function test_shouldDeleteLoanData_whenLOANOwnerIsOriginalLender() external {
        _mockLOAN(loanId, simpleLoan);

        loan.repayLOAN(loanId, loanAssetPermit);

        _assertLOANEq(loanId, nonExistingLoan);
    }

    function test_shouldBurnLOANToken_whenLOANOwnerIsOriginalLender() external {
        _mockLOAN(loanId, simpleLoan);

        vm.expectCall(loanToken, abi.encodeWithSignature("burn(uint256)", loanId));

        loan.repayLOAN(loanId, loanAssetPermit);
    }

    function test_shouldTransferRepaidAmountToLender_whenLOANOwnerIsOriginalLender() external {
        _mockLOAN(loanId, simpleLoan);

        vm.expectCall(
            simpleLoan.loanAssetAddress,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)", borrower, lender, simpleLoan.loanRepayAmount
            )
        );

        vm.prank(borrower);
        loan.repayLOAN(loanId, loanAssetPermit);
    }

    function test_shouldMoveLoanToRepaidState_whenLOANOwnerIsNotOriginalLender() external {
        _mockLOAN(loanId, simpleLoan);
        _LOANTokenNotOwnedByOriginalLender();

        loan.repayLOAN(loanId, loanAssetPermit);

        bytes32 loanSlot = keccak256(abi.encode(loanId, LOANS_SLOT));
        // Parse status value from first storage slot
        bytes32 statusValue = vm.load(address(loan), loanSlot) & bytes32(uint256(0xff));
        assertTrue(statusValue == bytes32(uint256(3)));
    }

    function test_shouldTransferRepaidAmountToVault_whenLOANOwnerIsNotOriginalLender() external {
        _mockLOAN(loanId, simpleLoan);
        _LOANTokenNotOwnedByOriginalLender();

        vm.expectCall(
            simpleLoan.loanAssetAddress,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)", borrower, address(loan), simpleLoan.loanRepayAmount
            )
        );

        vm.prank(borrower);
        loan.repayLOAN(loanId, loanAssetPermit);
    }

    function test_shouldTransferCollateralToBorrower() external {
        _mockLOAN(loanId, simpleLoan);

        vm.expectCall(
            simpleLoan.collateral.assetAddress,
            abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256,bytes)",
                address(loan), simpleLoan.borrower, simpleLoan.collateral.id
            )
        );

        loan.repayLOAN(loanId, loanAssetPermit);
    }

    function test_shouldEmitEvent_LOANPaidBack() external {
        _mockLOAN(loanId, simpleLoan);

        vm.expectEmit(true, false, false, false);
        emit LOANPaidBack(loanId);

        loan.repayLOAN(loanId, loanAssetPermit);
    }

    function test_shouldEmitEvent_LOANClaimed_whenLOANOwnerIsOriginalLender() external {
        _mockLOAN(loanId, simpleLoan);

        vm.expectEmit(true, true, true, true);
        emit LOANClaimed(loanId, false);

        loan.repayLOAN(loanId, loanAssetPermit);
    }

}


/*----------------------------------------------------------*|
|*  # CLAIM LOAN                                            *|
|*----------------------------------------------------------*/

contract PWNSimpleLoan_ClaimLOAN_Test is PWNSimpleLoanTest {

    function setUp() override public {
        super.setUp();

        vm.mockCall(
            loanToken,
            abi.encodeWithSignature("ownerOf(uint256)", loanId),
            abi.encode(lender)
        );

        simpleLoan.status = 3;

        // Move collateral to vault
        vm.prank(borrower);
        nonFungibleAsset.transferFrom(borrower, address(loan), 2);
    }


    function test_shouldFail_whenCallerIsNotLOANTokenHolder() external {
        _mockLOAN(loanId, simpleLoan);

        vm.expectRevert(abi.encodeWithSelector(CallerNotLOANTokenHolder.selector));
        vm.prank(borrower);
        loan.claimLOAN(loanId);
    }

    function test_shouldFail_whenLoanDoesNotExist() external {
        vm.expectRevert(abi.encodeWithSelector(NonExistingLoan.selector));
        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

    function test_shouldFail_whenLoanIsNotRepaidNorExpired() external {
        simpleLoan.status = 2;
        _mockLOAN(loanId, simpleLoan);

        vm.expectRevert(abi.encodeWithSelector(InvalidLoanStatus.selector, 2));
        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

    function test_shouldPass_whenLoanIsRepaid() external {
        _mockLOAN(loanId, simpleLoan);

        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

    function test_shouldPass_whenLoanIsExpired() external {
        simpleLoan.status = 2;
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.expiration + 10000);

        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

    function test_shouldDeleteLoanData() external {
        _mockLOAN(loanId, simpleLoan);

        vm.prank(lender);
        loan.claimLOAN(loanId);

        _assertLOANEq(loanId, nonExistingLoan);
    }

    function test_shouldBurnLOANToken() external {
        _mockLOAN(loanId, simpleLoan);

        vm.expectCall(
            loanToken,
            abi.encodeWithSignature("burn(uint256)", loanId)
        );

        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

    function test_shouldTransferRepaidAmountToLender_whenLoanIsRepaid() external {
        simpleLoan.loanRepayAmount = 110;

        _mockLOAN(loanId, simpleLoan);

        vm.expectCall(
            simpleLoan.loanAssetAddress,
            abi.encodeWithSignature("transfer(address,uint256)", lender, simpleLoan.loanRepayAmount)
        );

        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

    function test_shouldTransferCollateralToLender_whenLoanIsExpired() external {
        simpleLoan.status = 2;
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.expiration + 10000);

        vm.expectCall(
            simpleLoan.collateral.assetAddress,
            abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256,bytes)",
                address(loan), lender, simpleLoan.collateral.id, ""
            )
        );

        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

    function test_shouldEmitEvent_LOANClaimed_whenRepaid() external {
        _mockLOAN(loanId, simpleLoan);

        vm.expectEmit(true, true, false, false);
        emit LOANClaimed(loanId, false);

        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

    function test_shouldEmitEvent_LOANClaimed_whenDefaulted() external {
        simpleLoan.status = 2;
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.expiration + 10000);

        vm.expectEmit(true, true, false, false);
        emit LOANClaimed(loanId, true);

        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

}


/*----------------------------------------------------------*|
|*  # EXTEND LOAN EXPIRATION DATE                           *|
|*----------------------------------------------------------*/

contract PWNSimpleLoan_ExtendExpirationDate_Test is PWNSimpleLoanTest {

    function setUp() override public {
        super.setUp();

        // vm.warp(block.timestamp - 30039); // orig: block.timestamp + 40039
        vm.mockCall(
            loanToken,
            abi.encodeWithSignature("ownerOf(uint256)", loanId),
            abi.encode(lender)
        );
    }


    function test_shouldFail_whenCallerIsNotLOANTokenHolder() external {
        _mockLOAN(loanId, simpleLoan);

        vm.expectRevert(abi.encodeWithSelector(CallerNotLOANTokenHolder.selector));
        vm.prank(borrower);
        loan.extendLOANExpirationDate(loanId, simpleLoan.expiration + 1);
    }

    function test_shouldFail_whenExtendedExpirationDateIsSmallerThanCurrentExpirationDate() external {
        _mockLOAN(loanId, simpleLoan);

        vm.expectRevert(abi.encodeWithSelector(InvalidExtendedExpirationDate.selector));
        vm.prank(lender);
        loan.extendLOANExpirationDate(loanId, simpleLoan.expiration - 1);
    }

    function test_shouldFail_whenExtendedExpirationDateIsSmallerThanCurrentDate() external {
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.expiration + 1000);

        vm.expectRevert(abi.encodeWithSelector(InvalidExtendedExpirationDate.selector));
        vm.prank(lender);
        loan.extendLOANExpirationDate(loanId, simpleLoan.expiration + 500);
    }

    function test_shouldFail_whenExtendedExpirationDateIsBiggerThanMaxExpirationExtension() external {
        _mockLOAN(loanId, simpleLoan);

        vm.expectRevert(abi.encodeWithSelector(InvalidExtendedExpirationDate.selector));
        vm.prank(lender);
        loan.extendLOANExpirationDate(loanId, uint40(block.timestamp + MAX_EXPIRATION_EXTENSION + 1));
    }

    function test_shouldStoreExtendedExpirationDate() external {
        _mockLOAN(loanId, simpleLoan);

        uint40 newExpiration = uint40(simpleLoan.expiration + 10000);

        vm.prank(lender);
        loan.extendLOANExpirationDate(loanId, newExpiration);

        bytes32 loanFirstSlot = keccak256(abi.encode(loanId, LOANS_SLOT));
        bytes32 firstSlotValue = vm.load(address(loan), loanFirstSlot);
        bytes32 expirationDateValue = firstSlotValue >> 168;
        assertEq(uint256(expirationDateValue), newExpiration);
    }

    function test_shouldEmitEvent_LOANExpirationDateExtended() external {
        _mockLOAN(loanId, simpleLoan);

        uint40 newExpiration = uint40(simpleLoan.expiration + 10000);

        vm.expectEmit(true, true, true, true);
        emit LOANExpirationDateExtended(loanId, newExpiration);

        vm.prank(lender);
        loan.extendLOANExpirationDate(loanId, newExpiration);
    }

}


/*----------------------------------------------------------*|
|*  # GET LOAN                                              *|
|*----------------------------------------------------------*/

contract PWNSimpleLoan_GetLOAN_Test is PWNSimpleLoanTest {

    function test_shouldReturnLOANData() external {
        _mockLOAN(loanId, simpleLoan);

        _assertLOANEq(loan.getLOAN(loanId), simpleLoan);
    }

    function test_shouldReturnExpiredStatus_whenLOANExpired() external {
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.expiration + 10000);

        simpleLoan.status = 4;
        _assertLOANEq(loan.getLOAN(loanId), simpleLoan);
    }

    function test_shouldReturnEmptyLOANDataForNonExistingLoan() external {
        _assertLOANEq(loan.getLOAN(loanId), nonExistingLoan);
    }

}


/*----------------------------------------------------------*|
|*  # LOAN METADATA URI                                     *|
|*----------------------------------------------------------*/

contract PWNSimpleLoan_LoanMetadataUri_Test is PWNSimpleLoanTest {

    string tokenUri;

    function setUp() override public {
        super.setUp();

        tokenUri = "test.uri.xyz";

        vm.mockCall(
            config,
            abi.encodeWithSignature("loanMetadataUri(address)"),
            abi.encode(tokenUri)
        );
    }


    function test_shouldCallConfig() external {
        vm.expectCall(
            config,
            abi.encodeWithSignature("loanMetadataUri(address)", loan)
        );

        loan.loanMetadataUri();
    }

    function test_shouldReturnCorrectValue() external {
        string memory _tokenUri = loan.loanMetadataUri();

        assertEq(tokenUri, _tokenUri);
    }

}


/*----------------------------------------------------------*|
|*  # ERC5646                                               *|
|*----------------------------------------------------------*/

contract PWNSimpleLoan_GetStateFingerprint_Test is PWNSimpleLoanTest {

    function test_shouldReturnZeroIfLoanDoesNotExist() external {
        bytes32 fingerprint = loan.getStateFingerprint(loanId);

        assertEq(fingerprint, bytes32(0));
    }

    function test_shouldReturnCorrectStateFingerprint() external {
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.expiration - 10000);
        assertEq(loan.getStateFingerprint(loanId), keccak256(abi.encode(2, simpleLoan.expiration)));

        vm.warp(simpleLoan.expiration + 10000);
        assertEq(loan.getStateFingerprint(loanId), keccak256(abi.encode(4, simpleLoan.expiration)));

        simpleLoan.status = 3;
        simpleLoan.expiration = 60039;
        _mockLOAN(loanId, simpleLoan);
        assertEq(loan.getStateFingerprint(loanId), keccak256(abi.encode(3, 60039)));
    }

}
