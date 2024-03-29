// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import { PWNSimpleLoan, PWNHubTags, Math, MultiToken, Permit } from "@pwn/loan/terms/simple/loan/PWNSimpleLoan.sol";
import "@pwn/PWNErrors.sol";

import { T20 } from "@pwn-test/helper/token/T20.sol";
import { T721 } from "@pwn-test/helper/token/T721.sol";


abstract contract PWNSimpleLoanTest is Test {

    bytes32 internal constant LOANS_SLOT = bytes32(uint256(0)); // `LOANs` mapping position
    bytes32 internal constant EXTENSION_PROPOSALS_MADE_SLOT = bytes32(uint256(1)); // `extensionProposalsMade` mapping position

    PWNSimpleLoan loan;
    address hub = makeAddr("hub");
    address loanToken = makeAddr("loanToken");
    address config = makeAddr("config");
    address revokedNonce = makeAddr("revokedNonce");
    address categoryRegistry = makeAddr("categoryRegistry");
    address feeCollector = makeAddr("feeCollector");
    address alice = makeAddr("alice");
    address proposalContract = makeAddr("proposalContract");
    bytes proposalData = bytes("proposalData");
    bytes signature = bytes("signature");
    uint256 loanId = 42;
    address lender = makeAddr("lender");
    address borrower = makeAddr("borrower");
    uint256 loanDurationInDays = 101;
    PWNSimpleLoan.LOAN simpleLoan;
    PWNSimpleLoan.LOAN nonExistingLoan;
    PWNSimpleLoan.Terms simpleLoanTerms;
    PWNSimpleLoan.ProposalSpec proposalSpec;
    PWNSimpleLoan.CallerSpec callerSpec;
    PWNSimpleLoan.ExtensionProposal extension;
    T20 fungibleAsset;
    T721 nonFungibleAsset;
    Permit permit;

    bytes32 proposalHash = keccak256("proposalHash");

    event LOANCreated(uint256 indexed loanId, PWNSimpleLoan.Terms terms, bytes32 indexed proposalHash, address indexed proposalContract, bytes extra);
    event LOANPaidBack(uint256 indexed loanId);
    event LOANClaimed(uint256 indexed loanId, bool indexed defaulted);
    event LOANRefinanced(uint256 indexed loanId, uint256 indexed refinancedLoanId);
    event LOANExtended(uint256 indexed loanId, uint40 originalDefaultTimestamp, uint40 extendedDefaultTimestamp);
    event ExtensionProposalMade(bytes32 indexed extensionHash, address indexed proposer,  PWNSimpleLoan.ExtensionProposal proposal);

    function setUp() virtual public {
        vm.etch(hub, bytes("data"));
        vm.etch(loanToken, bytes("data"));
        vm.etch(proposalContract, bytes("data"));
        vm.etch(config, bytes("data"));

        loan = new PWNSimpleLoan(hub, loanToken, config, revokedNonce, categoryRegistry);
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

        simpleLoan = PWNSimpleLoan.LOAN({
            status: 2,
            creditAddress: address(fungibleAsset),
            startTimestamp: uint40(block.timestamp),
            defaultTimestamp: uint40(block.timestamp + loanDurationInDays * 1 days),
            borrower: borrower,
            originalLender: lender,
            accruingInterestDailyRate: 0,
            fixedInterestAmount: 6631,
            principalAmount: 100,
            collateral: MultiToken.ERC721(address(nonFungibleAsset), 2)
        });

        simpleLoanTerms = PWNSimpleLoan.Terms({
            lender: lender,
            borrower: borrower,
            duration: uint32(loanDurationInDays * 1 days),
            collateral: MultiToken.ERC721(address(nonFungibleAsset), 2),
            credit: MultiToken.ERC20(address(fungibleAsset), 100),
            fixedInterestAmount: 6631,
            accruingInterestAPR: 0
        });

        proposalSpec = PWNSimpleLoan.ProposalSpec({
            proposalContract: proposalContract,
            proposalData: proposalData,
            signature: signature
        });

        nonExistingLoan = PWNSimpleLoan.LOAN({
            status: 0,
            creditAddress: address(0),
            startTimestamp: 0,
            defaultTimestamp: 0,
            borrower: address(0),
            originalLender: address(0),
            accruingInterestDailyRate: 0,
            fixedInterestAmount: 0,
            principalAmount: 0,
            collateral: MultiToken.Asset(MultiToken.Category(0), address(0), 0, 0)
        });

        extension = PWNSimpleLoan.ExtensionProposal({
            loanId: loanId,
            compensationAddress: address(fungibleAsset),
            compensationAmount: 100,
            duration: 2 days,
            expiration: simpleLoan.defaultTimestamp,
            proposer: borrower,
            nonceSpace: 1,
            nonce: 1
        });

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

        vm.mockCall(config, abi.encodeWithSignature("fee()"), abi.encode(0));
        vm.mockCall(config, abi.encodeWithSignature("feeCollector()"), abi.encode(feeCollector));

        vm.mockCall(hub, abi.encodeWithSignature("hasTag(address,bytes32)"), abi.encode(false));
        vm.mockCall(
            hub,
            abi.encodeWithSignature("hasTag(address,bytes32)", proposalContract, PWNHubTags.LOAN_PROPOSAL),
            abi.encode(true)
        );

        _mockLoanTerms(simpleLoanTerms);
        _mockLOANMint(loanId);
        _mockLOANTokenOwner(loanId, lender);

        vm.mockCall(
            revokedNonce, abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)"), abi.encode(true)
        );
    }


    function _assertLOANEq(PWNSimpleLoan.LOAN memory _simpleLoan1, PWNSimpleLoan.LOAN memory _simpleLoan2) internal {
        assertEq(_simpleLoan1.status, _simpleLoan2.status);
        assertEq(_simpleLoan1.creditAddress, _simpleLoan2.creditAddress);
        assertEq(_simpleLoan1.startTimestamp, _simpleLoan2.startTimestamp);
        assertEq(_simpleLoan1.defaultTimestamp, _simpleLoan2.defaultTimestamp);
        assertEq(_simpleLoan1.borrower, _simpleLoan2.borrower);
        assertEq(_simpleLoan1.originalLender, _simpleLoan2.originalLender);
        assertEq(_simpleLoan1.accruingInterestDailyRate, _simpleLoan2.accruingInterestDailyRate);
        assertEq(_simpleLoan1.fixedInterestAmount, _simpleLoan2.fixedInterestAmount);
        assertEq(_simpleLoan1.principalAmount, _simpleLoan2.principalAmount);
        assertEq(uint8(_simpleLoan1.collateral.category), uint8(_simpleLoan2.collateral.category));
        assertEq(_simpleLoan1.collateral.assetAddress, _simpleLoan2.collateral.assetAddress);
        assertEq(_simpleLoan1.collateral.id, _simpleLoan2.collateral.id);
        assertEq(_simpleLoan1.collateral.amount, _simpleLoan2.collateral.amount);
    }

    function _assertLOANEq(uint256 _loanId, PWNSimpleLoan.LOAN memory _simpleLoan) internal {
        uint256 loanSlot = uint256(keccak256(abi.encode(_loanId, LOANS_SLOT)));

        // Status, credit address, start timestamp, default timestamp
        _assertLOANWord(loanSlot + 0, abi.encodePacked(uint8(0), _simpleLoan.defaultTimestamp, _simpleLoan.startTimestamp, _simpleLoan.creditAddress, _simpleLoan.status));
        // Borrower address
        _assertLOANWord(loanSlot + 1, abi.encodePacked(uint96(0), _simpleLoan.borrower));
        // Original lender, accruing interest daily rate
        _assertLOANWord(loanSlot + 2, abi.encodePacked(uint56(0), _simpleLoan.accruingInterestDailyRate, _simpleLoan.originalLender));
        // Fixed interest amount
        _assertLOANWord(loanSlot + 3, abi.encodePacked(_simpleLoan.fixedInterestAmount));
        // Principal amount
        _assertLOANWord(loanSlot + 4, abi.encodePacked(_simpleLoan.principalAmount));
        // Collateral category, collateral asset address
        _assertLOANWord(loanSlot + 5, abi.encodePacked(uint88(0), _simpleLoan.collateral.assetAddress, _simpleLoan.collateral.category));
        // Collateral id
        _assertLOANWord(loanSlot + 6, abi.encodePacked(_simpleLoan.collateral.id));
        // Collateral amount
        _assertLOANWord(loanSlot + 7, abi.encodePacked(_simpleLoan.collateral.amount));
    }


    function _mockLOAN(uint256 _loanId, PWNSimpleLoan.LOAN memory _simpleLoan) internal {
        uint256 loanSlot = uint256(keccak256(abi.encode(_loanId, LOANS_SLOT)));

        // Status, credit address, start timestamp, default timestamp
        _storeLOANWord(loanSlot + 0, abi.encodePacked(uint8(0), _simpleLoan.defaultTimestamp, _simpleLoan.startTimestamp, _simpleLoan.creditAddress, _simpleLoan.status));
        // Borrower address
        _storeLOANWord(loanSlot + 1, abi.encodePacked(uint96(0), _simpleLoan.borrower));
        // Original lender, accruing interest daily rate
        _storeLOANWord(loanSlot + 2, abi.encodePacked(uint56(0), _simpleLoan.accruingInterestDailyRate, _simpleLoan.originalLender));
        // Fixed interest amount
        _storeLOANWord(loanSlot + 3, abi.encodePacked(_simpleLoan.fixedInterestAmount));
        // Principal amount
        _storeLOANWord(loanSlot + 4, abi.encodePacked(_simpleLoan.principalAmount));
        // Collateral category, collateral asset address
        _storeLOANWord(loanSlot + 5, abi.encodePacked(uint88(0), _simpleLoan.collateral.assetAddress, _simpleLoan.collateral.category));
        // Collateral id
        _storeLOANWord(loanSlot + 6, abi.encodePacked(_simpleLoan.collateral.id));
        // Collateral amount
        _storeLOANWord(loanSlot + 7, abi.encodePacked(_simpleLoan.collateral.amount));
    }

    function _mockLoanTerms(PWNSimpleLoan.Terms memory _terms) internal {
        vm.mockCall(
            proposalContract,
            abi.encodeWithSignature("acceptProposal(address,uint256,bytes,bytes)"),
            abi.encode(proposalHash, _terms)
        );
    }

    function _mockLOANMint(uint256 _loanId) internal {
        vm.mockCall(loanToken, abi.encodeWithSignature("mint(address)"), abi.encode(_loanId));
    }

    function _mockLOANTokenOwner(uint256 _loanId, address _owner) internal {
        vm.mockCall(loanToken, abi.encodeWithSignature("ownerOf(uint256)", _loanId), abi.encode(_owner));
    }

    function _mockExtensionProposalMade(PWNSimpleLoan.ExtensionProposal memory _extension) internal {
        bytes32 extensionProposalSlot = keccak256(abi.encode(_extensionHash(_extension), EXTENSION_PROPOSALS_MADE_SLOT));
        vm.store(address(loan), extensionProposalSlot, bytes32(uint256(1)));
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

    function _extensionHash(PWNSimpleLoan.ExtensionProposal memory _extension) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            "\x19\x01",
            keccak256(abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("PWNSimpleLoan"),
                keccak256("1.2"),
                block.chainid,
                address(loan)
            )),
            keccak256(abi.encodePacked(
                keccak256("ExtensionProposal(uint256 loanId,address compensationAddress,uint256 compensationAmount,uint40 duration,uint40 expiration,address proposer,uint256 nonceSpace,uint256 nonce)"),
                abi.encode(_extension)
            ))
        ));
    }

}


/*----------------------------------------------------------*|
|*  # CREATE LOAN                                           *|
|*----------------------------------------------------------*/

contract PWNSimpleLoan_CreateLOAN_Test is PWNSimpleLoanTest {

    function testFuzz_shouldFail_whenProposalContractNotTagged_LOAN_PROPOSAL(address _proposalContract) external {
        vm.assume(_proposalContract != proposalContract);

        proposalSpec.proposalContract = _proposalContract;

        vm.expectRevert(abi.encodeWithSelector(AddressMissingHubTag.selector, _proposalContract, PWNHubTags.LOAN_PROPOSAL));
        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldRevokeCallersNonce_whenFlagIsTrue(address caller, uint256 nonce) external {
        callerSpec.revokeNonce = true;
        callerSpec.nonce = nonce;

        vm.expectCall(
            revokedNonce,
            abi.encodeWithSignature("revokeNonce(address,uint256)", caller, nonce)
        );

        vm.prank(caller);
        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldNotRevokeCallersNonce_whenFlagIsTrue(address caller, uint256 nonce) external {
        callerSpec.revokeNonce = false;
        callerSpec.nonce = nonce;

        vm.expectCall({
            callee: revokedNonce,
            data: abi.encodeWithSignature("revokeNonce(address,uint256)", caller, nonce),
            count: 0
        });

        vm.prank(caller);
        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldCallProposalContract(address caller) external {
        vm.expectCall(
            proposalContract,
            abi.encodeWithSignature("acceptProposal(address,uint256,bytes,bytes)", caller, 0, proposalData, signature)
        );

        vm.prank(caller);
        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldFail_whenLoanTermsDurationLessThanMin(uint256 duration) external {
        uint256 minDuration = loan.MIN_LOAN_DURATION();
        vm.assume(duration < minDuration);
        duration = bound(duration, 0, minDuration - 1);
        simpleLoanTerms.duration = uint32(duration);
        _mockLoanTerms(simpleLoanTerms);

        vm.expectRevert(abi.encodeWithSelector(InvalidDuration.selector, duration, minDuration));
        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldFail_whenLoanTermsAccruingInterestAPROutOfBounds(uint256 interestAPR) external {
        uint256 maxInterest = loan.MAX_ACCRUING_INTEREST_APR();
        interestAPR = bound(interestAPR, maxInterest + 1, type(uint40).max);
        simpleLoanTerms.accruingInterestAPR = uint40(interestAPR);
        _mockLoanTerms(simpleLoanTerms);

        vm.expectRevert(abi.encodeWithSelector(AccruingInterestAPROutOfBounds.selector, interestAPR, maxInterest));
        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function test_shouldFail_whenInvalidCreditAsset() external {
        vm.mockCall(
            categoryRegistry,
            abi.encodeWithSignature("registeredCategoryValue(address)", simpleLoanTerms.credit.assetAddress),
            abi.encode(1)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidMultiTokenAsset.selector,
                uint8(simpleLoanTerms.credit.category),
                simpleLoanTerms.credit.assetAddress,
                simpleLoanTerms.credit.id,
                simpleLoanTerms.credit.amount
            )
        );
        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function test_shouldFail_whenInvalidCollateralAsset() external {
        vm.mockCall(
            categoryRegistry,
            abi.encodeWithSignature("registeredCategoryValue(address)", simpleLoanTerms.collateral.assetAddress),
            abi.encode(0)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidMultiTokenAsset.selector,
                uint8(simpleLoanTerms.collateral.category),
                simpleLoanTerms.collateral.assetAddress,
                simpleLoanTerms.collateral.id,
                simpleLoanTerms.collateral.amount
            )
        );
        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function test_shouldMintLOANToken() external {
        vm.expectCall(address(loanToken), abi.encodeWithSignature("mint(address)", lender));

        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldStoreLoanData(uint40 accruingInterestAPR) external {
        accruingInterestAPR = uint40(bound(accruingInterestAPR, 0, 1e11));
        simpleLoanTerms.accruingInterestAPR = accruingInterestAPR;
        _mockLoanTerms(simpleLoanTerms);

        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });

        simpleLoan.accruingInterestDailyRate = uint40(uint256(accruingInterestAPR) * 274 / 1e5);
        _assertLOANEq(loanId, simpleLoan);
    }

    function testFuzz_shouldFail_whenInvalidPermitData_permitOwner(address permitOwner) external {
        vm.assume(permitOwner != borrower && permitOwner != address(0));
        permit.asset = simpleLoan.creditAddress;
        permit.owner = permitOwner;

        callerSpec.permit = permit;

        vm.expectRevert(abi.encodeWithSelector(InvalidPermitOwner.selector, permitOwner, borrower));
        vm.prank(borrower);
        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldFail_whenInvalidPermitData_permitAsset(address permitAsset) external {
        vm.assume(permitAsset != simpleLoan.creditAddress && permitAsset != address(0));
        permit.asset = permitAsset;
        permit.owner = borrower;

        callerSpec.permit = permit;

        vm.expectRevert(abi.encodeWithSelector(InvalidPermitAsset.selector, permitAsset, simpleLoan.creditAddress));
        vm.prank(borrower);
        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function test_shouldCallPermit_whenProvided() external {
        permit.asset = simpleLoan.creditAddress;
        permit.owner = borrower;
        permit.amount = 101;
        permit.deadline = 1;
        permit.v = 4;
        permit.r = bytes32(uint256(2));
        permit.s = bytes32(uint256(3));

        callerSpec.permit = permit;

        vm.expectCall(
            permit.asset,
            abi.encodeWithSignature(
                "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
                permit.owner, address(loan), permit.amount, permit.deadline, permit.v, permit.r, permit.s
            )
        );

        vm.prank(borrower);
        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function test_shouldTransferCollateral_fromBorrower_toVault() external {
        simpleLoanTerms.collateral.category = MultiToken.Category.ERC20;
        simpleLoanTerms.collateral.assetAddress = address(fungibleAsset);
        simpleLoanTerms.collateral.id = 0;
        simpleLoanTerms.collateral.amount = 100;
        _mockLoanTerms(simpleLoanTerms);

        vm.expectCall(
            simpleLoanTerms.collateral.assetAddress,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)", borrower, address(loan), simpleLoanTerms.collateral.amount
            )
        );

        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldTransferCredit_fromLender_toBorrowerAndFeeCollector(
        uint256 fee, uint256 loanAmount
    ) external {
        fee = bound(fee, 0, 9999);
        loanAmount = bound(loanAmount, 1, 1e40);

        simpleLoanTerms.credit.amount = loanAmount;
        fungibleAsset.mint(lender, loanAmount);

        _mockLoanTerms(simpleLoanTerms);
        vm.mockCall(config, abi.encodeWithSignature("fee()"), abi.encode(fee));

        uint256 feeAmount = Math.mulDiv(loanAmount, fee, 1e4);
        uint256 newAmount = loanAmount - feeAmount;

        // Fee transfer
        vm.expectCall({
            callee: simpleLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature("transferFrom(address,address,uint256)", lender, feeCollector, feeAmount),
            count: feeAmount > 0 ? 1 : 0
        });
        // Updated amount transfer
        vm.expectCall(
            simpleLoanTerms.credit.assetAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", lender, borrower, newAmount)
        );

        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function test_shouldEmitEvent_LOANCreated() external {
        vm.expectEmit();
        emit LOANCreated(loanId, simpleLoanTerms, proposalHash, proposalContract, "lil extra");

        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: "lil extra"
        });
    }

    function testFuzz_shouldReturnNewLoanId(uint256 _loanId) external {
        _mockLOANMint(_loanId);

        uint256 createdLoanId = loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });

        assertEq(createdLoanId, _loanId);
    }

}


/*----------------------------------------------------------*|
|*  # REFINANCE LOAN                                        *|
|*----------------------------------------------------------*/

/// @dev This contract tests only different behaviour of `createLOAN` with refinancingLoanId >0.
contract PWNSimpleLoan_RefinanceLOAN_Test is PWNSimpleLoanTest {

    PWNSimpleLoan.LOAN refinancedLoan;
    PWNSimpleLoan.Terms refinancedLoanTerms;
    uint256 refinancingLoanId = 44;
    address newLender = makeAddr("newLender");

    function setUp() override public {
        super.setUp();

        // Move collateral to vault
        vm.prank(borrower);
        nonFungibleAsset.transferFrom(borrower, address(loan), 2);

        refinancedLoan = PWNSimpleLoan.LOAN({
            status: 2,
            creditAddress: address(fungibleAsset),
            startTimestamp: uint40(block.timestamp),
            defaultTimestamp: uint40(block.timestamp + 40039),
            borrower: borrower,
            originalLender: lender,
            accruingInterestDailyRate: 0,
            fixedInterestAmount: 6631,
            principalAmount: 100,
            collateral: MultiToken.ERC721(address(nonFungibleAsset), 2)
        });

        refinancedLoanTerms = PWNSimpleLoan.Terms({
            lender: lender,
            borrower: borrower,
            duration: 40039,
            collateral: MultiToken.ERC721(address(nonFungibleAsset), 2),
            credit: MultiToken.ERC20(address(fungibleAsset), 100),
            fixedInterestAmount: 6631,
            accruingInterestAPR: 0
        });

        _mockLoanTerms(refinancedLoanTerms);
        _mockLOAN(refinancingLoanId, simpleLoan);
        _mockLOANTokenOwner(refinancingLoanId, lender);
        callerSpec.refinancingLoanId = refinancingLoanId;

        vm.prank(newLender);
        fungibleAsset.approve(address(loan), type(uint256).max);
    }


    function test_shouldFail_whenLoanDoesNotExist() external {
        simpleLoan.status = 0;
        _mockLOAN(refinancingLoanId, simpleLoan);

        vm.expectRevert(abi.encodeWithSelector(NonExistingLoan.selector));
        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function test_shouldFail_whenLoanIsNotRunning() external {
        simpleLoan.status = 3;
        _mockLOAN(refinancingLoanId, simpleLoan);

        vm.expectRevert(abi.encodeWithSelector(InvalidLoanStatus.selector, 3));
        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function test_shouldFail_whenLoanIsDefaulted() external {
        vm.warp(simpleLoan.defaultTimestamp);

        vm.expectRevert(abi.encodeWithSelector(LoanDefaulted.selector, simpleLoan.defaultTimestamp));
        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldFail_whenCreditAssetMismatch(address _assetAddress) external {
        vm.assume(_assetAddress != simpleLoan.creditAddress);
        refinancedLoanTerms.credit.assetAddress = _assetAddress;
        _mockLoanTerms(refinancedLoanTerms);

        vm.expectRevert(abi.encodeWithSelector(RefinanceCreditMismatch.selector));
        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function test_shouldFail_whenCreditAssetAmountZero() external {
        refinancedLoanTerms.credit.amount = 0;
        _mockLoanTerms(refinancedLoanTerms);

        vm.expectRevert(abi.encodeWithSelector(RefinanceCreditMismatch.selector));
        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldFail_whenCollateralCategoryMismatch(uint8 _category) external {
        _category = _category % 4;
        vm.assume(_category != uint8(simpleLoan.collateral.category));
        refinancedLoanTerms.collateral.category = MultiToken.Category(_category);
        _mockLoanTerms(refinancedLoanTerms);

        vm.expectRevert(abi.encodeWithSelector(RefinanceCollateralMismatch.selector));
        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldFail_whenCollateralAddressMismatch(address _assetAddress) external {
        vm.assume(_assetAddress != simpleLoan.collateral.assetAddress);
        refinancedLoanTerms.collateral.assetAddress = _assetAddress;
        _mockLoanTerms(refinancedLoanTerms);

        vm.expectRevert(abi.encodeWithSelector(RefinanceCollateralMismatch.selector));
        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldFail_whenCollateralIdMismatch(uint256 _id) external {
        vm.assume(_id != simpleLoan.collateral.id);
        refinancedLoanTerms.collateral.id = _id;
        _mockLoanTerms(refinancedLoanTerms);

        vm.expectRevert(abi.encodeWithSelector(RefinanceCollateralMismatch.selector));
        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldFail_whenCollateralAmountMismatch(uint256 _amount) external {
        vm.assume(_amount != simpleLoan.collateral.amount);
        refinancedLoanTerms.collateral.amount = _amount;
        _mockLoanTerms(refinancedLoanTerms);

        vm.expectRevert(abi.encodeWithSelector(RefinanceCollateralMismatch.selector));
        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldFail_whenBorrowerMismatch(address _borrower) external {
        vm.assume(_borrower != simpleLoan.borrower);
        refinancedLoanTerms.borrower = _borrower;
        _mockLoanTerms(refinancedLoanTerms);

        vm.expectRevert(abi.encodeWithSelector(RefinanceBorrowerMismatch.selector, simpleLoan.borrower, _borrower));
        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function test_shouldEmit_LOANPaidBack() external {
        vm.expectEmit();
        emit LOANPaidBack(refinancingLoanId);

        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function test_shouldEmit_LOANRefinanced() external {
        vm.expectEmit();
        emit LOANRefinanced(refinancingLoanId, loanId);

        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function test_shouldDeleteOldLoanData_whenLOANOwnerIsOriginalLender() external {
        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });

        _assertLOANEq(refinancingLoanId, nonExistingLoan);
    }

    function test_shouldEmit_LOANClaimed_whenLOANOwnerIsOriginalLender() external {
        vm.expectEmit();
        emit LOANClaimed(refinancingLoanId, false);

        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldUpdateLoanData_whenLOANOwnerIsNotOriginalLender(
        uint256 _days, uint256 principal, uint256 fixedInterest, uint256 dailyInterest
    ) external {
        _mockLOANTokenOwner(refinancingLoanId, makeAddr("notOriginalLender"));

        _days = bound(_days, 0, loanDurationInDays - 1);
        principal = bound(principal, 1, 1e40);
        fixedInterest = bound(fixedInterest, 0, 1e40);
        dailyInterest = bound(dailyInterest, 1, 274e8);

        simpleLoan.principalAmount = principal;
        simpleLoan.fixedInterestAmount = fixedInterest;
        simpleLoan.accruingInterestDailyRate = uint40(dailyInterest);
        _mockLOAN(refinancingLoanId, simpleLoan);

        vm.warp(simpleLoan.startTimestamp + _days * 1 days);

        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(refinancingLoanId);
        fungibleAsset.mint(borrower, loanRepaymentAmount);

        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });

        // Update loan and compare
        simpleLoan.status = 3; // move loan to repaid state
        simpleLoan.fixedInterestAmount = loanRepaymentAmount - principal; // stored accrued interest at the time of repayment
        simpleLoan.accruingInterestDailyRate = 0; // stop accruing interest
        _assertLOANEq(refinancingLoanId, simpleLoan);
    }

    function testFuzz_shouldTransferOriginalLoanRepaymentDirectly_andTransferSurplusToBorrower_whenLOANOwnerIsOriginalLender_whenRefinanceLoanMoreThanOrEqualToOriginalLoan(
        uint256 refinanceAmount, uint256 fee
    ) external {
        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(refinancingLoanId);
        fee = bound(fee, 0, 9999); // 0 - 99.99%
        uint256 minRefinanceAmount = Math.mulDiv(loanRepaymentAmount, 1e4, 1e4 - fee);
        refinanceAmount = bound(
            refinanceAmount,
            minRefinanceAmount,
            type(uint256).max - minRefinanceAmount - fungibleAsset.totalSupply()
        );
        uint256 feeAmount = Math.mulDiv(refinanceAmount, fee, 1e4);
        uint256 borrowerSurplus = refinanceAmount - feeAmount - loanRepaymentAmount;

        refinancedLoanTerms.credit.amount = refinanceAmount;
        refinancedLoanTerms.lender = newLender;
        _mockLoanTerms(refinancedLoanTerms);
        _mockLOANTokenOwner(refinancingLoanId, simpleLoan.originalLender);
        vm.mockCall(config, abi.encodeWithSignature("fee()"), abi.encode(fee));

        fungibleAsset.mint(newLender, refinanceAmount);

        vm.expectCall({ // fee transfer
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                newLender, feeCollector, feeAmount
            ),
            count: feeAmount > 0 ? 1 : 0
        });
        vm.expectCall( // lender repayment
            refinancedLoanTerms.credit.assetAddress,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                newLender, simpleLoan.originalLender, loanRepaymentAmount
            )
        );
        vm.expectCall({ // borrower surplus
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                newLender, borrower, borrowerSurplus
            ),
            count: borrowerSurplus > 0 ? 1 : 0
        });

        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldTransferOriginalLoanRepaymentToVault_andTransferSurplusToBorrower_whenLOANOwnerIsNotOriginalLender_whenRefinanceLoanMoreThanOrEqualToOriginalLoan(
        uint256 refinanceAmount, uint256 fee
    ) external {
        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(refinancingLoanId);
        fee = bound(fee, 0, 9999); // 0 - 99.99%
        uint256 minRefinanceAmount = Math.mulDiv(loanRepaymentAmount, 1e4, 1e4 - fee);
        refinanceAmount = bound(
            refinanceAmount,
            minRefinanceAmount,
            type(uint256).max - minRefinanceAmount - fungibleAsset.totalSupply()
        );
        uint256 feeAmount = Math.mulDiv(refinanceAmount, fee, 1e4);
        uint256 borrowerSurplus = refinanceAmount - feeAmount - loanRepaymentAmount;

        refinancedLoanTerms.credit.amount = refinanceAmount;
        refinancedLoanTerms.lender = newLender;
        _mockLoanTerms(refinancedLoanTerms);
        _mockLOANTokenOwner(refinancingLoanId, makeAddr("notOriginalLender"));
        vm.mockCall(config, abi.encodeWithSignature("fee()"), abi.encode(fee));

        fungibleAsset.mint(newLender, refinanceAmount);

        vm.expectCall({ // fee transfer
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                newLender, feeCollector, feeAmount
            ),
            count: feeAmount > 0 ? 1 : 0
        });
        vm.expectCall( // lender repayment
            refinancedLoanTerms.credit.assetAddress,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                newLender, address(loan), loanRepaymentAmount
            )
        );
        vm.expectCall({ // borrower surplus
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                newLender, borrower, borrowerSurplus
            ),
            count: borrowerSurplus > 0 ? 1 : 0
        });

        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldNotTransferOriginalLoanRepayment_andTransferSurplusToBorrower_whenLOANOwnerIsNewLender_whenRefinanceLoanMoreThanOrEqualOriginalLoan(
        uint256 refinanceAmount, uint256 fee
    ) external {
        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(refinancingLoanId);
        fee = bound(fee, 0, 9999); // 0 - 99.99%
        uint256 minRefinanceAmount = Math.mulDiv(loanRepaymentAmount, 1e4, 1e4 - fee);
        refinanceAmount = bound(
            refinanceAmount,
            minRefinanceAmount,
            type(uint256).max - minRefinanceAmount - fungibleAsset.totalSupply()
        );
        uint256 feeAmount = Math.mulDiv(refinanceAmount, fee, 1e4);
        uint256 borrowerSurplus = refinanceAmount - feeAmount - loanRepaymentAmount;

        refinancedLoanTerms.credit.amount = refinanceAmount;
        refinancedLoanTerms.lender = newLender;
        _mockLoanTerms(refinancedLoanTerms);
        _mockLOANTokenOwner(refinancingLoanId, newLender);
        vm.mockCall(config, abi.encodeWithSignature("fee()"), abi.encode(fee));

        fungibleAsset.mint(newLender, refinanceAmount);

        vm.expectCall({ // fee transfer
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                newLender, feeCollector, feeAmount
            ),
            count: feeAmount > 0 ? 1 : 0
        });
        vm.expectCall({ // lender repayment
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                newLender, newLender, loanRepaymentAmount
            ),
            count: 0
        });
        vm.expectCall({ // borrower surplus
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                newLender, borrower, borrowerSurplus
            ),
            count: borrowerSurplus > 0 ? 1 : 0
        });

        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldTransferOriginalLoanRepaymentDirectly_andContributeFromBorrower_whenLOANOwnerIsOriginalLender_whenRefinanceLoanLessThanOriginalLoan(
        uint256 refinanceAmount, uint256 fee
    ) external {
        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(refinancingLoanId);
        fee = bound(fee, 0, 9999); // 0 - 99.99%
        uint256 minRefinanceAmount = Math.mulDiv(loanRepaymentAmount, 1e4, 1e4 - fee);
        refinanceAmount = bound(refinanceAmount, 1, minRefinanceAmount - 1);
        uint256 feeAmount = Math.mulDiv(refinanceAmount, fee, 1e4);
        uint256 borrowerContribution = loanRepaymentAmount - (refinanceAmount - feeAmount);

        refinancedLoanTerms.credit.amount = refinanceAmount;
        refinancedLoanTerms.lender = newLender;
        _mockLoanTerms(refinancedLoanTerms);
        _mockLOANTokenOwner(refinancingLoanId, simpleLoan.originalLender);
        vm.mockCall(config, abi.encodeWithSignature("fee()"), abi.encode(fee));

        fungibleAsset.mint(newLender, refinanceAmount);

        vm.expectCall({ // fee transfer
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                newLender, feeCollector, feeAmount
            ),
            count: feeAmount > 0 ? 1 : 0
        });
        vm.expectCall( // lender repayment
            refinancedLoanTerms.credit.assetAddress,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                newLender, simpleLoan.originalLender, refinanceAmount - feeAmount
            )
        );
        vm.expectCall({ // borrower contribution
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                borrower, simpleLoan.originalLender, borrowerContribution
            ),
            count: borrowerContribution > 0 ? 1 : 0
        });

        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldTransferOriginalLoanRepaymentToVault_andContributeFromBorrower_whenLOANOwnerIsNotOriginalLender_whenRefinanceLoanLessThanOriginalLoan(
        uint256 refinanceAmount, uint256 fee
    ) external {
        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(refinancingLoanId);
        fee = bound(fee, 0, 9999); // 0 - 99.99%
        uint256 minRefinanceAmount = Math.mulDiv(loanRepaymentAmount, 1e4, 1e4 - fee);
        refinanceAmount = bound(refinanceAmount, 1, minRefinanceAmount - 1);
        uint256 feeAmount = Math.mulDiv(refinanceAmount, fee, 1e4);
        uint256 borrowerContribution = loanRepaymentAmount - (refinanceAmount - feeAmount);

        refinancedLoanTerms.credit.amount = refinanceAmount;
        refinancedLoanTerms.lender = newLender;
        _mockLoanTerms(refinancedLoanTerms);
        _mockLOANTokenOwner(refinancingLoanId, makeAddr("notOriginalLender"));
        vm.mockCall(config, abi.encodeWithSignature("fee()"), abi.encode(fee));

        fungibleAsset.mint(newLender, refinanceAmount);

        vm.expectCall({ // fee transfer
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                newLender, feeCollector, feeAmount
            ),
            count: feeAmount > 0 ? 1 : 0
        });
        vm.expectCall( // lender repayment
            refinancedLoanTerms.credit.assetAddress,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                newLender, address(loan), refinanceAmount - feeAmount
            )
        );
        vm.expectCall({ // borrower contribution
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                borrower, address(loan), borrowerContribution
            ),
            count: borrowerContribution > 0 ? 1 : 0
        });

        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldNotTransferOriginalLoanRepayment_andContributeFromBorrower_whenLOANOwnerIsNewLender_whenRefinanceLoanLessThanOriginalLoan(
        uint256 refinanceAmount, uint256 fee
    ) external {
        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(refinancingLoanId);
        fee = bound(fee, 0, 9999); // 0 - 99.99%
        uint256 minRefinanceAmount = Math.mulDiv(loanRepaymentAmount, 1e4, 1e4 - fee);
        refinanceAmount = bound(refinanceAmount, 1, minRefinanceAmount - 1);
        uint256 feeAmount = Math.mulDiv(refinanceAmount, fee, 1e4);
        uint256 borrowerContribution = loanRepaymentAmount - (refinanceAmount - feeAmount);

        refinancedLoanTerms.credit.amount = refinanceAmount;
        refinancedLoanTerms.lender = newLender;
        _mockLoanTerms(refinancedLoanTerms);
        _mockLOANTokenOwner(refinancingLoanId, newLender);
        vm.mockCall(config, abi.encodeWithSignature("fee()"), abi.encode(fee));

        fungibleAsset.mint(newLender, refinanceAmount);

        vm.expectCall({ // fee transfer
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                newLender, feeCollector, feeAmount
            ),
            count: feeAmount > 0 ? 1 : 0
        });
        vm.expectCall({ // lender repayment
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                newLender, newLender, refinanceAmount - feeAmount
            ),
            count: 0
        });
        vm.expectCall({ // borrower contribution
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                borrower, newLender, borrowerContribution
            ),
            count: borrowerContribution > 0 ? 1 : 0
        });

        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldRepayOriginalLoan(
        uint256 _days, uint256 principal, uint256 fixedInterest, uint256 dailyInterest, uint256 refinanceAmount
    ) external {
        _days = bound(_days, 0, loanDurationInDays - 1);
        principal = bound(principal, 1, 1e40);
        fixedInterest = bound(fixedInterest, 0, 1e40);
        dailyInterest = bound(dailyInterest, 1, 274e8);

        simpleLoan.principalAmount = principal;
        simpleLoan.fixedInterestAmount = fixedInterest;
        simpleLoan.accruingInterestDailyRate = uint40(dailyInterest);
        _mockLOAN(refinancingLoanId, simpleLoan);

        vm.warp(simpleLoan.startTimestamp + _days * 1 days);

        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(refinancingLoanId);
        refinanceAmount = bound(
            refinanceAmount, 1, type(uint256).max - loanRepaymentAmount - fungibleAsset.totalSupply()
        );

        refinancedLoanTerms.credit.amount = refinanceAmount;
        refinancedLoanTerms.lender = newLender;
        _mockLoanTerms(refinancedLoanTerms);
        _mockLOANTokenOwner(refinancingLoanId, lender);

        fungibleAsset.mint(newLender, refinanceAmount);
        if (loanRepaymentAmount > refinanceAmount) {
            fungibleAsset.mint(borrower, loanRepaymentAmount - refinanceAmount);
        }

        uint256 originalBalance = fungibleAsset.balanceOf(lender);

        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });

        assertEq(fungibleAsset.balanceOf(lender), originalBalance + loanRepaymentAmount);
    }

    function testFuzz_shouldCollectProtocolFee(
        uint256 _days, uint256 principal, uint256 fixedInterest, uint256 dailyInterest, uint256 refinanceAmount, uint256 fee
    ) external {
        _days = bound(_days, 0, loanDurationInDays - 1);
        principal = bound(principal, 1, 1e40);
        fixedInterest = bound(fixedInterest, 0, 1e40);
        dailyInterest = bound(dailyInterest, 1, 274e8);

        simpleLoan.principalAmount = principal;
        simpleLoan.fixedInterestAmount = fixedInterest;
        simpleLoan.accruingInterestDailyRate = uint40(dailyInterest);
        _mockLOAN(refinancingLoanId, simpleLoan);

        vm.warp(simpleLoan.startTimestamp + _days * 1 days);

        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(refinancingLoanId);
        fee = bound(fee, 1, 9999); // 0 - 99.99%
        refinanceAmount = bound(
            refinanceAmount, 1, type(uint256).max - loanRepaymentAmount - fungibleAsset.totalSupply()
        );
        uint256 feeAmount = Math.mulDiv(refinanceAmount, fee, 1e4);

        refinancedLoanTerms.credit.amount = refinanceAmount;
        refinancedLoanTerms.lender = newLender;
        _mockLoanTerms(refinancedLoanTerms);
        _mockLOANTokenOwner(refinancingLoanId, lender);
        vm.mockCall(config, abi.encodeWithSignature("fee()"), abi.encode(fee));

        fungibleAsset.mint(newLender, refinanceAmount);
        if (loanRepaymentAmount > refinanceAmount - feeAmount) {
            fungibleAsset.mint(borrower, loanRepaymentAmount - (refinanceAmount - feeAmount));
        }

        uint256 originalBalance = fungibleAsset.balanceOf(feeCollector);

        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });

        assertEq(fungibleAsset.balanceOf(feeCollector), originalBalance + feeAmount);
    }

    function testFuzz_shouldTransferSurplusToBorrower(uint256 refinanceAmount) external {
        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(refinancingLoanId);
        refinanceAmount = bound(
            refinanceAmount, loanRepaymentAmount + 1, type(uint256).max - loanRepaymentAmount - fungibleAsset.totalSupply()
        );
        uint256 surplus = refinanceAmount - loanRepaymentAmount;

        refinancedLoanTerms.credit.amount = refinanceAmount;
        refinancedLoanTerms.lender = newLender;
        _mockLoanTerms(refinancedLoanTerms);
        _mockLOANTokenOwner(refinancingLoanId, lender);

        fungibleAsset.mint(newLender, refinanceAmount);
        uint256 originalBalance = fungibleAsset.balanceOf(borrower);

        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });

        assertEq(fungibleAsset.balanceOf(borrower), originalBalance + surplus);
    }

    function testFuzz_shouldContributeFromBorrower(uint256 refinanceAmount) external {
        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(refinancingLoanId);
        refinanceAmount = bound(refinanceAmount, 1, loanRepaymentAmount - 1);
        uint256 contribution = loanRepaymentAmount - refinanceAmount;

        refinancedLoanTerms.credit.amount = refinanceAmount;
        refinancedLoanTerms.lender = newLender;
        _mockLoanTerms(refinancedLoanTerms);
        _mockLOANTokenOwner(refinancingLoanId, lender);

        fungibleAsset.mint(newLender, refinanceAmount);
        uint256 originalBalance = fungibleAsset.balanceOf(borrower);

        loan.createLOAN({
            proposalSpec: proposalSpec,
            callerSpec: callerSpec,
            extra: ""
        });

        assertEq(fungibleAsset.balanceOf(borrower), originalBalance - contribution);
    }

}


/*----------------------------------------------------------*|
|*  # REPAY LOAN                                            *|
|*----------------------------------------------------------*/

contract PWNSimpleLoan_RepayLOAN_Test is PWNSimpleLoanTest {

    address notOriginalLender = makeAddr("notOriginalLender");

    function setUp() override public {
        super.setUp();

        _mockLOAN(loanId, simpleLoan);

        // Move collateral to vault
        vm.prank(borrower);
        nonFungibleAsset.transferFrom(borrower, address(loan), 2);
    }


    function test_shouldFail_whenLoanDoesNotExist() external {
        simpleLoan.status = 0;
        _mockLOAN(loanId, simpleLoan);

        vm.expectRevert(abi.encodeWithSelector(NonExistingLoan.selector));
        loan.repayLOAN(loanId, permit);
    }

    function test_shouldFail_whenLoanIsNotRunning() external {
        simpleLoan.status = 3;
        _mockLOAN(loanId, simpleLoan);

        vm.expectRevert(abi.encodeWithSelector(InvalidLoanStatus.selector, 3));
        loan.repayLOAN(loanId, permit);
    }

    function test_shouldFail_whenLoanIsDefaulted() external {
        vm.warp(simpleLoan.defaultTimestamp);

        vm.expectRevert(abi.encodeWithSelector(LoanDefaulted.selector, simpleLoan.defaultTimestamp));
        loan.repayLOAN(loanId, permit);
    }

    function testFuzz_shouldFail_whenInvalidPermitData_permitOwner(address permitOwner) external {
        vm.assume(permitOwner != borrower && permitOwner != address(0));
        permit.asset = simpleLoan.creditAddress;
        permit.owner = permitOwner;

        callerSpec.permit = permit;

        vm.expectRevert(abi.encodeWithSelector(InvalidPermitOwner.selector, permitOwner, borrower));
        vm.prank(borrower);
        loan.repayLOAN(loanId, permit);
    }

    function testFuzz_shouldFail_whenInvalidPermitData_permitAsset(address permitAsset) external {
        vm.assume(permitAsset != simpleLoan.creditAddress && permitAsset != address(0));
        permit.asset = permitAsset;
        permit.owner = borrower;

        callerSpec.permit = permit;

        vm.expectRevert(abi.encodeWithSelector(InvalidPermitAsset.selector, permitAsset, simpleLoan.creditAddress));
        vm.prank(borrower);
        loan.repayLOAN(loanId, permit);
    }

    function test_shouldCallPermit_whenProvided() external {
        permit.asset = simpleLoan.creditAddress;
        permit.owner = borrower;
        permit.amount = 321;
        permit.deadline = 2;
        permit.v = 3;
        permit.r = bytes32(uint256(4));
        permit.s = bytes32(uint256(5));

        vm.expectCall(
            simpleLoan.creditAddress,
            abi.encodeWithSignature(
                "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
                permit.owner, address(loan), permit.amount, permit.deadline, permit.v, permit.r, permit.s
            )
        );

        vm.prank(borrower);
        loan.repayLOAN(loanId, permit);
    }

    function test_shouldDeleteLoanData_whenLOANOwnerIsOriginalLender() external {
        loan.repayLOAN(loanId, permit);

        _assertLOANEq(loanId, nonExistingLoan);
    }

    function test_shouldBurnLOANToken_whenLOANOwnerIsOriginalLender() external {
        vm.expectCall(loanToken, abi.encodeWithSignature("burn(uint256)", loanId));

        loan.repayLOAN(loanId, permit);
    }

    function testFuzz_shouldTransferRepaidAmountToLender_whenLOANOwnerIsOriginalLender(
        uint256 _days, uint256 _principal, uint256 _fixedInterest, uint256 _dailyInterest
    ) external {
        _days = bound(_days, 0, loanDurationInDays - 1);
        _principal = bound(_principal, 1, 1e40);
        _fixedInterest = bound(_fixedInterest, 0, 1e40);
        _dailyInterest = bound(_dailyInterest, 1, 274e8);

        simpleLoan.principalAmount = _principal;
        simpleLoan.fixedInterestAmount = _fixedInterest;
        simpleLoan.accruingInterestDailyRate = uint40(_dailyInterest);
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.startTimestamp + _days * 1 days);

        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(loanId);
        fungibleAsset.mint(borrower, loanRepaymentAmount);

        vm.expectCall(
            simpleLoan.creditAddress,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)", borrower, lender, loanRepaymentAmount
            )
        );

        vm.prank(borrower);
        loan.repayLOAN(loanId, permit);
    }

    function testFuzz_shouldUpdateLoanData_whenLOANOwnerIsNotOriginalLender(
        uint256 _days, uint256 _principal, uint256 _fixedInterest, uint256 _dailyInterest
    ) external {
        _mockLOANTokenOwner(loanId, notOriginalLender);

        _days = bound(_days, 0, loanDurationInDays - 1);
        _principal = bound(_principal, 1, 1e40);
        _fixedInterest = bound(_fixedInterest, 0, 1e40);
        _dailyInterest = bound(_dailyInterest, 1, 274e8);

        simpleLoan.principalAmount = _principal;
        simpleLoan.fixedInterestAmount = _fixedInterest;
        simpleLoan.accruingInterestDailyRate = uint40(_dailyInterest);
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.startTimestamp + _days * 1 days);

        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(loanId);
        fungibleAsset.mint(borrower, loanRepaymentAmount);

        vm.prank(borrower);
        loan.repayLOAN(loanId, permit);

        // Update loan and compare
        simpleLoan.status = 3; // move loan to repaid state
        simpleLoan.fixedInterestAmount = loanRepaymentAmount - _principal; // stored accrued interest at the time of repayment
        simpleLoan.accruingInterestDailyRate = 0; // stop accruing interest
        _assertLOANEq(loanId, simpleLoan);
    }

    function testFuzz_shouldTransferRepaidAmountToVault_whenLOANOwnerIsNotOriginalLender(
        uint256 _days, uint256 _principal, uint256 _fixedInterest, uint256 _dailyInterest
    ) external {
        _mockLOANTokenOwner(loanId, notOriginalLender);

        _days = bound(_days, 0, loanDurationInDays - 1);
        _principal = bound(_principal, 1, 1e40);
        _fixedInterest = bound(_fixedInterest, 0, 1e40);
        _dailyInterest = bound(_dailyInterest, 1, 274e8);

        simpleLoan.principalAmount = _principal;
        simpleLoan.fixedInterestAmount = _fixedInterest;
        simpleLoan.accruingInterestDailyRate = uint40(_dailyInterest);
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.startTimestamp + _days * 1 days);

        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(loanId);
        fungibleAsset.mint(borrower, loanRepaymentAmount);

        vm.expectCall(
            simpleLoan.creditAddress,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)", borrower, address(loan), loanRepaymentAmount
            )
        );

        vm.prank(borrower);
        loan.repayLOAN(loanId, permit);
    }

    function test_shouldTransferCollateralToBorrower() external {
        vm.expectCall(
            simpleLoan.collateral.assetAddress,
            abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256,bytes)",
                address(loan), simpleLoan.borrower, simpleLoan.collateral.id
            )
        );

        loan.repayLOAN(loanId, permit);
    }

    function test_shouldEmitEvent_LOANPaidBack() external {
        vm.expectEmit();
        emit LOANPaidBack(loanId);

        loan.repayLOAN(loanId, permit);
    }

    function test_shouldEmitEvent_LOANClaimed_whenLOANOwnerIsOriginalLender() external {
        vm.expectEmit();
        emit LOANClaimed(loanId, false);

        loan.repayLOAN(loanId, permit);
    }

}


/*----------------------------------------------------------*|
|*  # LOAN REPAYMENT AMOUNT                                 *|
|*----------------------------------------------------------*/

contract PWNSimpleLoan_LoanRepaymentAmount_Test is PWNSimpleLoanTest {

    function test_shouldReturnZero_whenLoanDoesNotExist() external {
        assertEq(loan.loanRepaymentAmount(loanId), 0);
    }

    function testFuzz_shouldReturnFixedInterest_whenZeroAccruedInterest(
        uint256 _days, uint256 _principal, uint256 _fixedInterest
    ) external {
        _days = bound(_days, 0, 2 * loanDurationInDays); // should return non zero value even after loan expiration
        _principal = bound(_principal, 1, 1e40);
        _fixedInterest = bound(_fixedInterest, 0, 1e40);

        simpleLoan.defaultTimestamp = simpleLoan.startTimestamp + 101 * 1 days;
        simpleLoan.principalAmount = _principal;
        simpleLoan.fixedInterestAmount = _fixedInterest;
        simpleLoan.accruingInterestDailyRate = 0;
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.startTimestamp + _days + 1 days); // should not have an effect

        assertEq(loan.loanRepaymentAmount(loanId), _principal + _fixedInterest);
    }

    function test_shouldReturnAccruedInterest_whenNonZeroAccruedInterest(
        uint256 _days, uint256 _principal, uint256 _fixedInterest, uint256 _dailyInterest
    ) external {
        _days = bound(_days, 0, 2 * loanDurationInDays); // should return non zero value even after loan expiration
        _principal = bound(_principal, 1, 1e40);
        _fixedInterest = bound(_fixedInterest, 0, 1e40);
        _dailyInterest = bound(_dailyInterest, 1, 274e8);

        simpleLoan.defaultTimestamp = simpleLoan.startTimestamp + 101 * 1 days;
        simpleLoan.principalAmount = _principal;
        simpleLoan.fixedInterestAmount = _fixedInterest;
        simpleLoan.accruingInterestDailyRate = uint40(_dailyInterest);
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.startTimestamp + _days * 1 days + 1);

        uint256 expectedInterest = _fixedInterest + _principal * _dailyInterest * _days / 1e10;
        uint256 expectedLoanRepaymentAmount = _principal + expectedInterest;
        assertEq(loan.loanRepaymentAmount(loanId), expectedLoanRepaymentAmount);
    }

}


/*----------------------------------------------------------*|
|*  # CLAIM LOAN                                            *|
|*----------------------------------------------------------*/

contract PWNSimpleLoan_ClaimLOAN_Test is PWNSimpleLoanTest {

    function setUp() override public {
        super.setUp();

        simpleLoan.status = 3;
        _mockLOAN(loanId, simpleLoan);

        // Move collateral to vault
        vm.prank(borrower);
        nonFungibleAsset.transferFrom(borrower, address(loan), 2);
    }


    function testFuzz_shouldFail_whenCallerIsNotLOANTokenHolder(address caller) external {
        vm.assume(caller != lender);

        vm.expectRevert(abi.encodeWithSelector(CallerNotLOANTokenHolder.selector));
        vm.prank(caller);
        loan.claimLOAN(loanId);
    }

    function test_shouldFail_whenLoanDoesNotExist() external {
        simpleLoan.status = 0;
        _mockLOAN(loanId, simpleLoan);

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
        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

    function test_shouldPass_whenLoanIsDefaulted() external {
        simpleLoan.status = 2;
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.defaultTimestamp);

        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

    function test_shouldDeleteLoanData() external {
        vm.prank(lender);
        loan.claimLOAN(loanId);

        _assertLOANEq(loanId, nonExistingLoan);
    }

    function test_shouldBurnLOANToken() external {
        vm.expectCall(
            loanToken,
            abi.encodeWithSignature("burn(uint256)", loanId)
        );

        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

    function testFuzz_shouldTransferRepaidAmountToLender_whenLoanIsRepaid(
        uint256 _principal, uint256 _fixedInterest
    ) external {
        _principal = bound(_principal, 1, 1e40);
        _fixedInterest = bound(_fixedInterest, 0, 1e40);

        // Note: loan repayment into Vault will reuse `fixedInterestAmount` and store total interest
        // at the time of repayment and set `accruingInterestDailyRate` to zero.
        simpleLoan.principalAmount = _principal;
        simpleLoan.fixedInterestAmount = _fixedInterest;
        simpleLoan.accruingInterestDailyRate = 0;
        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(loanId);

        fungibleAsset.mint(address(loan), loanRepaymentAmount);

        vm.expectCall(
            simpleLoan.creditAddress,
            abi.encodeWithSignature("transfer(address,uint256)", lender, loanRepaymentAmount)
        );

        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

    function test_shouldTransferCollateralToLender_whenLoanIsDefaulted() external {
        simpleLoan.status = 2;
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.defaultTimestamp);

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
        vm.expectEmit();
        emit LOANClaimed(loanId, false);

        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

    function test_shouldEmitEvent_LOANClaimed_whenDefaulted() external {
        simpleLoan.status = 2;
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.defaultTimestamp);

        vm.expectEmit();
        emit LOANClaimed(loanId, true);

        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

}


/*----------------------------------------------------------*|
|*  # MAKE EXTENSION PROPOSAL                               *|
|*----------------------------------------------------------*/

contract PWNSimpleLoan_MakeExtensionProposal_Test is PWNSimpleLoanTest {

    function testFuzz_shouldFail_whenCallerNotProposer(address caller) external {
        vm.assume(caller != extension.proposer);

        vm.expectRevert(abi.encodeWithSelector(InvalidExtensionSigner.selector, extension.proposer, caller));
        vm.prank(caller);
        loan.makeExtensionProposal(extension);
    }

    function test_shouldStoreMadeFlag() external {
        vm.prank(extension.proposer);
        loan.makeExtensionProposal(extension);

        bytes32 extensionProposalSlot = keccak256(abi.encode(_extensionHash(extension), EXTENSION_PROPOSALS_MADE_SLOT));
        bytes32 isMadeValue = vm.load(address(loan), extensionProposalSlot);
        assertEq(uint256(isMadeValue), 1);
    }

    function test_shouldEmit_ExtensionProposalMade() external {
        bytes32 extensionHash = _extensionHash(extension);

        vm.expectEmit();
        emit ExtensionProposalMade(extensionHash, extension.proposer, extension);

        vm.prank(extension.proposer);
        loan.makeExtensionProposal(extension);
    }

}


/*----------------------------------------------------------*|
|*  # EXTEND LOAN                                           *|
|*----------------------------------------------------------*/

contract PWNSimpleLoan_ExtendLOAN_Test is PWNSimpleLoanTest {

    uint256 lenderPk;
    uint256 borrowerPk;

    function setUp() override public {
        super.setUp();

        _mockLOAN(loanId, simpleLoan);

        (, lenderPk) = makeAddrAndKey("lender");
        (, borrowerPk) = makeAddrAndKey("borrower");

        // borrower as proposer, lender accepting extension
        extension.proposer = borrower;
    }


    // Helpers

    function _signExtension(uint256 pk, PWNSimpleLoan.ExtensionProposal memory _extension) private view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _extensionHash(_extension));
        return abi.encodePacked(r, s, v);
    }

    // Tests

    function test_shouldFail_whenLoanDoesNotExist() external {
        simpleLoan.status = 0;
        _mockLOAN(loanId, simpleLoan);

        vm.expectRevert(abi.encodeWithSelector(NonExistingLoan.selector));
        vm.prank(lender);
        loan.extendLOAN(extension, "", permit);
    }

    function test_shouldFail_whenLoanIsRepaid() external {
        simpleLoan.status = 3;
        _mockLOAN(loanId, simpleLoan);

        vm.expectRevert(abi.encodeWithSelector(InvalidLoanStatus.selector, 3));
        vm.prank(lender);
        loan.extendLOAN(extension, "", permit);
    }

    function testFuzz_shouldFail_whenInvalidSignature_whenEOA(uint256 pk) external {
        pk = boundPrivateKey(pk);
        vm.assume(pk != borrowerPk);

        vm.expectRevert(abi.encodeWithSelector(InvalidSignature.selector, extension.proposer, _extensionHash(extension)));
        vm.prank(lender);
        loan.extendLOAN(extension, _signExtension(pk, extension), permit);
    }

    function testFuzz_shouldFail_whenOfferExpirated(uint40 expiration) external {
        uint256 timestamp = 300;
        vm.warp(timestamp);

        extension.expiration = uint40(bound(expiration, 0, timestamp));
        _mockExtensionProposalMade(extension);

        vm.expectRevert(abi.encodeWithSelector(Expired.selector, block.timestamp, extension.expiration));
        vm.prank(lender);
        loan.extendLOAN(extension, "", permit);
    }

    function test_shouldFail_whenOfferNonceNotUsable() external {
        _mockExtensionProposalMade(extension);

        vm.mockCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)", extension.proposer, extension.nonceSpace, extension.nonce),
            abi.encode(false)
        );

        vm.expectRevert(abi.encodeWithSelector(
            NonceNotUsable.selector, extension.proposer, extension.nonceSpace, extension.nonce
        ));
        vm.prank(lender);
        loan.extendLOAN(extension, "", permit);
    }

    function testFuzz_shouldFail_whenCallerIsNotBorrowerNorLoanOwner(address caller) external {
        vm.assume(caller != borrower && caller != lender);
        _mockExtensionProposalMade(extension);

        vm.expectRevert(abi.encodeWithSelector(InvalidExtensionCaller.selector));
        vm.prank(caller);
        loan.extendLOAN(extension, "", permit);
    }

    function testFuzz_shouldFail_whenCallerIsBorrower_andProposerIsNotLoanOwner(address proposer) external {
        vm.assume(proposer != lender);

        extension.proposer = proposer;
        _mockExtensionProposalMade(extension);

        vm.expectRevert(abi.encodeWithSelector(InvalidExtensionSigner.selector, lender, proposer));
        vm.prank(borrower);
        loan.extendLOAN(extension, "", permit);
    }

    function testFuzz_shouldFail_whenCallerIsLoanOwner_andProposerIsNotBorrower(address proposer) external {
        vm.assume(proposer != borrower);

        extension.proposer = proposer;
        _mockExtensionProposalMade(extension);

        vm.expectRevert(abi.encodeWithSelector(InvalidExtensionSigner.selector, borrower, proposer));
        vm.prank(lender);
        loan.extendLOAN(extension, "", permit);
    }

    function testFuzz_shouldFail_whenExtensionDurationLessThanMin(uint40 duration) external {
        uint256 minDuration = loan.MIN_EXTENSION_DURATION();
        duration = uint40(bound(duration, 0, minDuration - 1));

        extension.duration = duration;
        _mockExtensionProposalMade(extension);

        vm.expectRevert(abi.encodeWithSelector(InvalidExtensionDuration.selector, duration, minDuration));
        vm.prank(lender);
        loan.extendLOAN(extension, "", permit);
    }

    function testFuzz_shouldFail_whenExtensionDurationMoreThanMax(uint40 duration) external {
        uint256 maxDuration = loan.MAX_EXTENSION_DURATION();
        duration = uint40(bound(duration, maxDuration + 1, type(uint40).max));

        extension.duration = duration;
        _mockExtensionProposalMade(extension);

        vm.expectRevert(abi.encodeWithSelector(InvalidExtensionDuration.selector, duration, maxDuration));
        vm.prank(lender);
        loan.extendLOAN(extension, "", permit);
    }

    function testFuzz_shouldRevokeExtensionNonce(uint256 nonceSpace, uint256 nonce) external {
        extension.nonceSpace = nonceSpace;
        extension.nonce = nonce;
        _mockExtensionProposalMade(extension);

        vm.expectCall(
            revokedNonce,
            abi.encodeWithSignature("revokeNonce(address,uint256,uint256)", extension.proposer, nonceSpace, nonce)
        );

        vm.prank(lender);
        loan.extendLOAN(extension, "", permit);
    }

    function testFuzz_shouldUpdateLoanData(uint40 duration) external {
        duration = uint40(bound(duration, loan.MIN_EXTENSION_DURATION(), loan.MAX_EXTENSION_DURATION()));

        extension.duration = duration;
        _mockExtensionProposalMade(extension);

        vm.prank(lender);
        loan.extendLOAN(extension, "", permit);

        simpleLoan.defaultTimestamp = simpleLoan.defaultTimestamp + duration;
        _assertLOANEq(loanId, simpleLoan);
    }

    function testFuzz_shouldEmit_LOANExtended(uint40 duration) external {
        duration = uint40(bound(duration, loan.MIN_EXTENSION_DURATION(), loan.MAX_EXTENSION_DURATION()));

        extension.duration = duration;
        _mockExtensionProposalMade(extension);

        vm.expectEmit();
        emit LOANExtended(loanId, simpleLoan.defaultTimestamp, simpleLoan.defaultTimestamp + duration);

        vm.prank(lender);
        loan.extendLOAN(extension, "", permit);
    }

    function test_shouldNotTransferCredit_whenAmountZero() external {
        extension.compensationAddress = address(fungibleAsset);
        extension.compensationAmount = 0;
        _mockExtensionProposalMade(extension);

        vm.expectCall({
            callee: extension.compensationAddress,
            data: abi.encodeWithSignature("transferFrom(address,address,uint256)", borrower, lender, 0),
            count: 0
        });

        vm.prank(lender);
        loan.extendLOAN(extension, "", permit);
    }

    function test_shouldNotTransferCredit_whenAddressZero() external {
        extension.compensationAddress = address(0);
        extension.compensationAmount = 3123;
        _mockExtensionProposalMade(extension);

        vm.expectCall({
            callee: extension.compensationAddress,
            data: abi.encodeWithSignature("transferFrom(address,address,uint256)", borrower, lender, extension.compensationAmount),
            count: 0
        });

        vm.prank(lender);
        loan.extendLOAN(extension, "", permit);
    }

    function test_shouldFail_whenInvalidCompensationAsset() external {
        extension.compensationAddress = address(0x1);
        extension.compensationAmount = 3123;
        _mockExtensionProposalMade(extension);

        vm.mockCall(
            categoryRegistry,
            abi.encodeWithSignature("registeredCategoryValue(address)", extension.compensationAddress),
            abi.encode(1) // ERC721
        );

        vm.expectRevert(abi.encodeWithSelector(InvalidMultiTokenAsset.selector, 0, extension.compensationAddress, 0, extension.compensationAmount));
        vm.prank(lender);
        loan.extendLOAN(extension, "", permit);
    }

    function testFuzz_shouldFail_whenInvalidPermitData_permitOwner(address permitOwner) external {
        _mockExtensionProposalMade(extension);

        vm.assume(permitOwner != lender && permitOwner != address(0));
        permit.asset = extension.compensationAddress;
        permit.owner = permitOwner;

        callerSpec.permit = permit;

        vm.expectRevert(abi.encodeWithSelector(InvalidPermitOwner.selector, permitOwner, lender));
        vm.prank(lender);
        loan.extendLOAN(extension, "", permit);
    }

    function testFuzz_shouldFail_whenInvalidPermitData_permitAsset(address permitAsset) external {
        _mockExtensionProposalMade(extension);

        vm.assume(permitAsset != extension.compensationAddress && permitAsset != address(0));
        permit.asset = permitAsset;
        permit.owner = lender;

        callerSpec.permit = permit;

        vm.expectRevert(abi.encodeWithSelector(InvalidPermitAsset.selector, permitAsset, extension.compensationAddress));
        vm.prank(lender);
        loan.extendLOAN(extension, "", permit);
    }

    function test_shouldCallPermit_whenProvided() external {
        _mockExtensionProposalMade(extension);

        permit.asset = extension.compensationAddress;
        permit.owner = lender;
        permit.amount = 321;
        permit.deadline = 2;
        permit.v = 3;
        permit.r = bytes32(uint256(4));
        permit.s = bytes32(uint256(5));

        vm.expectCall(
            permit.asset,
            abi.encodeWithSignature(
                "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
                permit.owner, address(loan), permit.amount, permit.deadline, permit.v, permit.r, permit.s
            )
        );

        vm.prank(lender);
        loan.extendLOAN(extension, "", permit);
    }

    function testFuzz_shouldTransferCompensation_whenDefined(uint256 amount) external {
        amount = bound(amount, 1, 1e40);

        extension.compensationAmount = amount;
        _mockExtensionProposalMade(extension);
        fungibleAsset.mint(borrower, amount);

        vm.mockCall(
            categoryRegistry,
            abi.encodeWithSignature("registeredCategoryValue(address)", extension.compensationAddress),
            abi.encode(0) // ER20
        );

        vm.expectCall(
            extension.compensationAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", borrower, lender, amount)
        );

        vm.prank(lender);
        loan.extendLOAN(extension, "", permit);
    }

    function test_shouldPass_whenBorrowerSignature_whenLenderAccepts() external {
        extension.proposer = borrower;

        vm.prank(lender);
        loan.extendLOAN(extension, _signExtension(borrowerPk, extension), permit);
    }

    function test_shouldPass_whenLenderSignature_whenBorrowerAccepts() external {
        extension.proposer = lender;

        vm.prank(borrower);
        loan.extendLOAN(extension, _signExtension(lenderPk, extension), permit);
    }

}


/*----------------------------------------------------------*|
|*  # GET EXTENSION HASH                                    *|
|*----------------------------------------------------------*/

contract PWNSimpleLoan_GetExtensionHash_Test is PWNSimpleLoanTest {

    function test_shouldReturnExtensionHash() external {
        assertEq(_extensionHash(extension), loan.getExtensionHash(extension));
    }

}


/*----------------------------------------------------------*|
|*  # GET LOAN                                              *|
|*----------------------------------------------------------*/

contract PWNSimpleLoan_GetLOAN_Test is PWNSimpleLoanTest {

    function testFuzz_shouldReturnStaticLOANData(
        uint40 _startTimestamp,
        uint40 _defaultTimestamp,
        address _borrower,
        address _originalLender,
        uint40 _accruingInterestDailyRate,
        uint256 _fixedInterestAmount,
        address _creditAddress,
        uint256 _principalAmount,
        uint8 _collateralCategory,
        address _collateralAssetAddress,
        uint256 _collateralId,
        uint256 _collateralAmount
    ) external {
        _startTimestamp = uint40(bound(_startTimestamp, 0, type(uint40).max - 1));
        _defaultTimestamp = uint40(bound(_defaultTimestamp, _startTimestamp + 1, type(uint40).max));
        _accruingInterestDailyRate = uint40(bound(_accruingInterestDailyRate, 0, 274e8));
        _fixedInterestAmount = bound(_fixedInterestAmount, 0, type(uint256).max - _principalAmount);

        simpleLoan.startTimestamp = _startTimestamp;
        simpleLoan.defaultTimestamp = _defaultTimestamp;
        simpleLoan.borrower = _borrower;
        simpleLoan.originalLender = _originalLender;
        simpleLoan.accruingInterestDailyRate = _accruingInterestDailyRate;
        simpleLoan.fixedInterestAmount = _fixedInterestAmount;
        simpleLoan.creditAddress = _creditAddress;
        simpleLoan.principalAmount = _principalAmount;
        simpleLoan.collateral.category = MultiToken.Category(_collateralCategory % 4);
        simpleLoan.collateral.assetAddress = _collateralAssetAddress;
        simpleLoan.collateral.id = _collateralId;
        simpleLoan.collateral.amount = _collateralAmount;
        _mockLOAN(loanId, simpleLoan);

        vm.warp(_startTimestamp);

        // test every property separately to avoid stack too deep error
        {
            (,uint40 startTimestamp,,,,,,,,,) = loan.getLOAN(loanId);
            assertEq(startTimestamp, _startTimestamp);
        }
        {
            (,,uint40 defaultTimestamp,,,,,,,,) = loan.getLOAN(loanId);
            assertEq(defaultTimestamp, _defaultTimestamp);
        }
        {
            (,,,address borrower,,,,,,,) = loan.getLOAN(loanId);
            assertEq(borrower, _borrower);
        }
        {
            (,,,,address originalLender,,,,,,) = loan.getLOAN(loanId);
            assertEq(originalLender, _originalLender);
        }
        {
            (,,,,,,uint40 accruingInterestDailyRate,,,,) = loan.getLOAN(loanId);
            assertEq(accruingInterestDailyRate, _accruingInterestDailyRate);
        }
        {
            (,,,,,,,uint256 fixedInterestAmount,,,) = loan.getLOAN(loanId);
            assertEq(fixedInterestAmount, _fixedInterestAmount);
        }
        {
            (,,,,,,,,MultiToken.Asset memory credit,,) = loan.getLOAN(loanId);
            assertEq(credit.assetAddress, _creditAddress);
            assertEq(credit.amount, _principalAmount);
        }
        {
            (,,,,,,,,,MultiToken.Asset memory collateral,) = loan.getLOAN(loanId);
            assertEq(collateral.assetAddress, _collateralAssetAddress);
            assertEq(uint8(collateral.category), _collateralCategory % 4);
            assertEq(collateral.id, _collateralId);
            assertEq(collateral.amount, _collateralAmount);
        }
    }

    function test_shouldReturnCorrectStatus() external {
        _mockLOAN(loanId, simpleLoan);

        (uint8 status,,,,,,,,,,) = loan.getLOAN(loanId);
        assertEq(status, 2);

        vm.warp(simpleLoan.defaultTimestamp);

        (status,,,,,,,,,,) = loan.getLOAN(loanId);
        assertEq(status, 4);

        simpleLoan.status = 3;
        _mockLOAN(loanId, simpleLoan);

        (status,,,,,,,,,,) = loan.getLOAN(loanId);
        assertEq(status, 3);
    }

    function testFuzz_shouldReturnLOANTokenOwner(address _loanOwner) external {
        _mockLOAN(loanId, simpleLoan);
        _mockLOANTokenOwner(loanId, _loanOwner);

        (,,,,, address loanOwner,,,,,) = loan.getLOAN(loanId);
        assertEq(loanOwner, _loanOwner);
    }

    function testFuzz_shouldReturnRepaymentAmount(
        uint256 _days,
        uint256 _principalAmount,
        uint40 _accruingInterestDailyRate,
        uint256 _fixedInterestAmount
    ) external {
        _days = bound(_days, 0, 2 * loanDurationInDays);
        _principalAmount = bound(_principalAmount, 1, 1e40);
        _accruingInterestDailyRate = uint40(bound(_accruingInterestDailyRate, 0, 274e8));
        _fixedInterestAmount = bound(_fixedInterestAmount, 0, _principalAmount);

        simpleLoan.accruingInterestDailyRate = _accruingInterestDailyRate;
        simpleLoan.fixedInterestAmount = _fixedInterestAmount;
        simpleLoan.principalAmount = _principalAmount;
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.startTimestamp + _days * 1 days);

        (,,,,,,,,,, uint256 repaymentAmount) = loan.getLOAN(loanId);
        assertEq(repaymentAmount, loan.loanRepaymentAmount(loanId));
    }

    function test_shouldReturnEmptyLOANDataForNonExistingLoan() external {
        uint256 nonExistingLoanId = loanId + 1;

        (
            uint8 status,
            uint40 startTimestamp,
            uint40 defaultTimestamp,
            address borrower,
            address originalLender,
            address loanOwner,
            uint40 accruingInterestDailyRate,
            uint256 fixedInterestAmount,
            MultiToken.Asset memory credit,
            MultiToken.Asset memory collateral,
            uint256 repaymentAmount
        ) = loan.getLOAN(nonExistingLoanId);

        assertEq(status, 0);
        assertEq(startTimestamp, 0);
        assertEq(defaultTimestamp, 0);
        assertEq(borrower, address(0));
        assertEq(originalLender, address(0));
        assertEq(loanOwner, address(0));
        assertEq(accruingInterestDailyRate, 0);
        assertEq(fixedInterestAmount, 0);
        assertEq(credit.assetAddress, address(0));
        assertEq(credit.amount, 0);
        assertEq(collateral.assetAddress, address(0));
        assertEq(uint8(collateral.category), 0);
        assertEq(collateral.id, 0);
        assertEq(collateral.amount, 0);
        assertEq(repaymentAmount, 0);
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

    function test_shouldUpdateStateFingerprint_whenLoanDefaulted() external {
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.defaultTimestamp - 1);
        assertEq(
            loan.getStateFingerprint(loanId),
            keccak256(abi.encode(2, simpleLoan.defaultTimestamp, simpleLoan.fixedInterestAmount, simpleLoan.accruingInterestDailyRate))
        );

        vm.warp(simpleLoan.defaultTimestamp);
        assertEq(
            loan.getStateFingerprint(loanId),
            keccak256(abi.encode(4, simpleLoan.defaultTimestamp, simpleLoan.fixedInterestAmount, simpleLoan.accruingInterestDailyRate))
        );
    }

    function testFuzz_shouldReturnCorrectStateFingerprint(
        uint256 fixedInterestAmount, uint40 accruingInterestDailyRate
    ) external {
        simpleLoan.fixedInterestAmount = fixedInterestAmount;
        simpleLoan.accruingInterestDailyRate = accruingInterestDailyRate;
        _mockLOAN(loanId, simpleLoan);

        assertEq(
            loan.getStateFingerprint(loanId),
            keccak256(abi.encode(2, simpleLoan.defaultTimestamp, simpleLoan.fixedInterestAmount, simpleLoan.accruingInterestDailyRate))
        );
    }

}
