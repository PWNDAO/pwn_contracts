// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "MultiToken/MultiToken.sol";

import "@pwn/hub/PWNHubTags.sol";
import "@pwn/loan/type/PWNSimpleLoan.sol";
import "@pwn/PWNError.sol";


abstract contract PWNSimpleLoanTest is Test {

    bytes32 internal constant LOANS_SLOT = bytes32(uint256(0)); // `LOANs` mapping position

    PWNSimpleLoan loan;
    address hub = address(0x80b);
    address loanToken = address(0x111111);
    address config = address(0xc0f1c);
    address feeCollector = address(0xfee);
    address token = address(0x070ce2);
    address alice = address(0xa11ce);
    address loanFactory = address(0x1001);
    uint256 loanId = 42;
    address lender = address(0x1001);
    address borrower = address(0x1002);
    PWNSimpleLoan.LOAN simpleLoan;
    PWNSimpleLoan.LOANTerms simpleLoanTerms;

    bytes loanFactoryData;
    bytes signature;
    bytes loanAssetPermit;
    bytes collateralPermit;

    event LOANCreated(uint256 indexed loanId, address indexed lender);
    event LOANPaidBack(uint256 loanId);
    event LOANClaimed(uint256 loanId);

    constructor() {
        vm.etch(hub, bytes("data"));
        vm.etch(loanToken, bytes("data"));
        vm.etch(loanFactory, bytes("data"));
        vm.etch(token, bytes("data"));
        vm.etch(config, bytes("data"));
    }

    function setUp() virtual public {
        loan = new PWNSimpleLoan(hub, loanToken, config);

        loanFactoryData = "";
        signature = "";
        loanAssetPermit = "";
        collateralPermit = "";

        simpleLoan = PWNSimpleLoan.LOAN({
            status: 2,
            borrower: borrower,
            expiration: 40039,
            loanAssetAddress: token,
            loanRepayAmount: 6731,
            collateral: MultiToken.Asset(MultiToken.Category.ERC721, token, 2, 0)
        });

        simpleLoanTerms = PWNSimpleLoan.LOANTerms({
            lender: lender,
            borrower: borrower,
            expiration: 40039,
            collateral: MultiToken.Asset(MultiToken.Category.ERC721, token, 2, 0),
            asset: MultiToken.Asset(MultiToken.Category.ERC721, token, 0, 5),
            loanRepayAmount: 6731
        });
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
            abi.encodeWithSignature("hasTag(address,bytes32)", loanFactory, PWNHubTags.SIMPLE_LOAN_FACTORY),
            abi.encode(true)
        );

        vm.mockCall(
            loanFactory,
            abi.encodeWithSignature("createLOAN(address,bytes,bytes)"),
            abi.encode(simpleLoanTerms)
        );

        vm.mockCall(
            loanToken,
            abi.encodeWithSignature("mint(address)"),
            abi.encode(loanId)
        );
    }


    function test_shouldFail_whenLoanFactoryContractIsNotTaggerInPWNHub() external {
        address notLoanFactory = address(0);

        vm.expectRevert(abi.encodeWithSelector(PWNError.CallerMissingHubTag.selector, PWNHubTags.SIMPLE_LOAN_FACTORY));
        loan.createLOAN(notLoanFactory, loanFactoryData, signature, loanAssetPermit, collateralPermit);
    }

    function test_shouldGetLOANStructFromGivenFactoryContract() external {
        loanFactoryData = abi.encode(1, 2, "data");
        signature = abi.encode("other data", "whaat?", uint256(312312));

        vm.expectCall(
            address(loanFactory),
            abi.encodeWithSignature("createLOAN(address,bytes,bytes)", address(this), loanFactoryData, signature)
        );

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
        simpleLoanTerms.collateral.assetAddress = token;
        simpleLoanTerms.collateral.id = 0;
        simpleLoanTerms.collateral.amount = 100;

        vm.mockCall(
            loanFactory,
            abi.encodeWithSignature("createLOAN(address,bytes,bytes)"),
            abi.encode(simpleLoanTerms)
        );

        collateralPermit = abi.encodePacked(uint256(1), uint256(2), uint256(3), uint8(4));

        vm.mockCall(
            simpleLoanTerms.collateral.assetAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)"),
            abi.encode(true)
        );
        vm.expectCall(
            token,
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
        simpleLoanTerms.asset.category = MultiToken.Category.ERC20;
        simpleLoanTerms.asset.assetAddress = token;
        simpleLoanTerms.asset.id = 0;
        simpleLoanTerms.asset.amount = 100;

        vm.mockCall(
            loanFactory,
            abi.encodeWithSignature("createLOAN(address,bytes,bytes)"),
            abi.encode(simpleLoanTerms, lender, borrower)
        );

        loanAssetPermit = abi.encodePacked(uint256(1), uint256(2), uint256(3), uint8(4));

        vm.mockCall(
            simpleLoanTerms.asset.assetAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)"),
            abi.encode(true)
        );
        vm.expectCall(
            token,
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
        simpleLoanTerms.asset.category = MultiToken.Category.ERC20;
        simpleLoanTerms.asset.assetAddress = token;
        simpleLoanTerms.asset.id = 0;
        simpleLoanTerms.asset.amount = 100;

        vm.mockCall(
            config,
            abi.encodeWithSignature("fee()"),
            abi.encode(1000)
        );

        vm.mockCall(
            loanFactory,
            abi.encodeWithSignature("createLOAN(address,bytes,bytes)"),
            abi.encode(simpleLoanTerms, lender, borrower)
        );

        loanAssetPermit = abi.encodePacked(uint256(1), uint256(2), uint256(3), uint8(4));

        vm.mockCall(
            simpleLoanTerms.asset.assetAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)"),
            abi.encode(true)
        );
        vm.expectCall(
            token,
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
        vm.expectEmit(true, true, false, false);
        emit LOANCreated(loanId, lender);

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

contract PWNSimpleLoan_RepayLoan_Test is PWNSimpleLoanTest {

    function setUp() override public {
        super.setUp();

        vm.warp(30039);

        vm.mockCall(
            simpleLoan.loanAssetAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)"),
            abi.encode(true)
        );
        vm.mockCall(
            simpleLoan.collateral.assetAddress,
            abi.encodeWithSignature("safeTransferFrom(address,address,uint256,bytes)"),
            abi.encode(true)
        );
    }

    function test_shouldFail_whenLoanDoesNotExist() external {
        simpleLoan.status = 0;
        _mockLOAN(loanId, simpleLoan);

        vm.expectRevert(abi.encodeWithSelector(PWNError.NonExistingLoan.selector));
        loan.repayLoan(loanId, loanAssetPermit);
    }

    function test_shouldFail_whenLoanIsNotRunning() external {
        simpleLoan.status = 3;
        _mockLOAN(loanId, simpleLoan);

        vm.expectRevert(abi.encodeWithSelector(PWNError.InvalidLoanStatus.selector, 3));
        loan.repayLoan(loanId, loanAssetPermit);
    }

    function test_shouldFail_whenLoanIsExpired() external {
        vm.warp(50039);
        _mockLOAN(loanId, simpleLoan);

        vm.expectRevert(abi.encodeWithSelector(PWNError.LoanDefaulted.selector, simpleLoan.expiration));
        loan.repayLoan(loanId, loanAssetPermit);
    }

    function test_shouldMoveLoanToRepaidState() external {
        _mockLOAN(loanId, simpleLoan);

        loan.repayLoan(loanId, loanAssetPermit);

        bytes32 loanSlot = keccak256(abi.encode(
            loanId,
            LOANS_SLOT
        ));
        // Parse status value from first storage slot
        bytes32 statusValue = vm.load(address(loan), loanSlot) & bytes32(uint256(0xff));
        assertTrue(statusValue == bytes32(uint256(3)));
    }

    function test_shouldTransferRepaidAmountToVault() external {
        _mockLOAN(loanId, simpleLoan);
        loanAssetPermit = abi.encodePacked(uint256(1), uint256(2), uint256(3), uint8(4));

        vm.expectCall(
            token,
            abi.encodeWithSignature(
                "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
                borrower, address(loan), simpleLoan.loanRepayAmount, 1, uint8(4), uint256(2), uint256(3)
            )
        );
        vm.expectCall(
            simpleLoan.loanAssetAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", borrower, address(loan), simpleLoan.loanRepayAmount)
        );

        vm.prank(borrower);
        loan.repayLoan(loanId, loanAssetPermit);
    }

    function test_shouldTransferCollateralToBorrower() external {
        _mockLOAN(loanId, simpleLoan);

        vm.expectCall(
            simpleLoan.collateral.assetAddress,
            abi.encodeWithSignature("safeTransferFrom(address,address,uint256,bytes)", address(loan), simpleLoan.borrower, simpleLoan.collateral.id)
        );

        loan.repayLoan(loanId, loanAssetPermit);
    }

    function test_shouldEmitEvent_LOANPaidBack() external {
        _mockLOAN(loanId, simpleLoan);

        vm.expectEmit(true, false, false, false);
        emit LOANPaidBack(loanId);

        loan.repayLoan(loanId, loanAssetPermit);
    }

}


/*----------------------------------------------------------*|
|*  # CLAIM LOAN                                            *|
|*----------------------------------------------------------*/

contract PWNSimpleLoan_ClaimLoan_Test is PWNSimpleLoanTest {

    function setUp() override public {
        super.setUp();

        vm.warp(30039);
        vm.mockCall(
            loanToken,
            abi.encodeWithSignature("ownerOf(uint256)", loanId),
            abi.encode(lender)
        );
        vm.mockCall(
            token,
            abi.encodeWithSignature("transfer(address,uint256)"),
            abi.encode(true)
        );
        vm.mockCall(
            token,
            abi.encodeWithSignature("safeTransferFrom(address,address,uint256,bytes)"),
            abi.encode(true)
        );

        simpleLoan.status = 3;
    }


    function test_shouldFail_whenCallerIsNotLOANTokenHolder() external {
        _mockLOAN(loanId, simpleLoan);

        vm.expectRevert(abi.encodeWithSelector(PWNError.CallerNotLOANTokenHolder.selector));
        vm.prank(borrower);
        loan.claimLoan(loanId);
    }

    function test_shouldFail_whenLoanDoesNotExist() external {
        vm.expectRevert(abi.encodeWithSelector(PWNError.NonExistingLoan.selector));
        vm.prank(lender);
        loan.claimLoan(loanId);
    }

    function test_shouldFail_whenLoanIsNotRepaidNorExpired() external {
        simpleLoan.status = 2;
        _mockLOAN(loanId, simpleLoan);

        vm.expectRevert(abi.encodeWithSelector(PWNError.InvalidLoanStatus.selector, 2));
        vm.prank(lender);
        loan.claimLoan(loanId);
    }

    function test_shouldPass_whenLoanIsRepaid() external {
        _mockLOAN(loanId, simpleLoan);

        vm.prank(lender);
        loan.claimLoan(loanId);
    }

    function test_shouldPass_whenLoanIsExpired() external {
        vm.warp(50039);
        simpleLoan.status = 2;
        _mockLOAN(loanId, simpleLoan);

        vm.prank(lender);
        loan.claimLoan(loanId);
    }

    function test_shouldDeleteLoanData() external {
        _mockLOAN(loanId, simpleLoan);

        vm.prank(lender);
        loan.claimLoan(loanId);

        PWNSimpleLoan.LOAN memory nonExistingLoan = PWNSimpleLoan.LOAN({
            status: 0,
            borrower: address(0),
            expiration: 0,
            loanAssetAddress: address(0),
            loanRepayAmount: 0,
            collateral: MultiToken.Asset(MultiToken.Category.ERC20, address(0), 0, 0)
        });
        _assertLOANEq(loanId, nonExistingLoan);
    }

    function test_shouldBurnLOANToken() external {
        _mockLOAN(loanId, simpleLoan);

        vm.expectCall(
            loanToken,
            abi.encodeWithSignature("burn(uint256)", loanId)
        );

        vm.prank(lender);
        loan.claimLoan(loanId);
    }

    function test_shouldTransferRepaidAmountToLender_whenLoanIsRepaid() external {
        simpleLoan.loanRepayAmount = 110;

        _mockLOAN(loanId, simpleLoan);

        vm.expectCall(
            simpleLoan.loanAssetAddress,
            abi.encodeWithSignature("transfer(address,uint256)", lender, simpleLoan.loanRepayAmount)
        );

        vm.prank(lender);
        loan.claimLoan(loanId);
    }

    function test_shouldTransferCollateralToLender_whenLoanIsExpired() external {
        simpleLoan.collateral.category = MultiToken.Category.ERC721;
        simpleLoan.collateral.assetAddress = token;
        simpleLoan.collateral.id = 8383;
        simpleLoan.collateral.amount = 100;

        vm.warp(50039);
        simpleLoan.status = 2;
        _mockLOAN(loanId, simpleLoan);

        vm.expectCall(
            simpleLoan.collateral.assetAddress,
            abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256,bytes)",
                address(loan), lender, simpleLoan.collateral.id, ""
            )
        );

        vm.prank(lender);
        loan.claimLoan(loanId);
    }

    function test_shouldEmitEvent_LOANClaimed() external {
        _mockLOAN(loanId, simpleLoan);

        vm.expectEmit(true, false, false, false);
        emit LOANClaimed(loanId);

        vm.prank(lender);
        loan.claimLoan(loanId);
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
