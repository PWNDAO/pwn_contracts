// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import {
    PWNSimpleLoan,
    PWNHubTags,
    Math,
    MultiToken,
    PWNSignatureChecker,
    PWNRevokedNonce,
    Permit,
    InvalidPermitOwner,
    InvalidPermitAsset,
    Expired,
    AddressMissingHubTag
} from "pwn/loan/terms/simple/loan/PWNSimpleLoan.sol";

import { T20 } from "test/helper/T20.sol";
import { T721 } from "test/helper/T721.sol";
import { DummyPoolAdapter } from "test/helper/DummyPoolAdapter.sol";


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
    address sourceOfFunds = makeAddr("sourceOfFunds");
    address poolAdapter = address(new DummyPoolAdapter());
    uint256 loanDurationInDays = 101;
    PWNSimpleLoan.LOAN simpleLoan;
    PWNSimpleLoan.LOAN nonExistingLoan;
    PWNSimpleLoan.Terms simpleLoanTerms;
    PWNSimpleLoan.ProposalSpec proposalSpec;
    PWNSimpleLoan.LenderSpec lenderSpec;
    PWNSimpleLoan.CallerSpec callerSpec;
    PWNSimpleLoan.ExtensionProposal extension;
    T20 fungibleAsset;
    T721 nonFungibleAsset;
    Permit permit;

    bytes32 proposalHash = keccak256("proposalHash");

    event LOANCreated(uint256 indexed loanId, bytes32 indexed proposalHash, address indexed proposalContract, uint256 refinancingLoanId, PWNSimpleLoan.Terms terms, PWNSimpleLoan.LenderSpec lenderSpec, bytes extra);
    event LOANPaidBack(uint256 indexed loanId);
    event LOANClaimed(uint256 indexed loanId, bool indexed defaulted);
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
        fungibleAsset.mint(sourceOfFunds, 1e30);
        nonFungibleAsset.mint(borrower, 2);

        vm.prank(lender);
        fungibleAsset.approve(address(loan), type(uint256).max);

        vm.prank(borrower);
        fungibleAsset.approve(address(loan), type(uint256).max);

        vm.prank(address(this));
        fungibleAsset.approve(address(loan), type(uint256).max);

        vm.prank(sourceOfFunds);
        fungibleAsset.approve(poolAdapter, type(uint256).max);

        vm.prank(borrower);
        nonFungibleAsset.approve(address(loan), 2);

        lenderSpec = PWNSimpleLoan.LenderSpec({
            sourceOfFunds: lender
        });

        simpleLoan = PWNSimpleLoan.LOAN({
            status: 2,
            creditAddress: address(fungibleAsset),
            originalSourceOfFunds: lender,
            startTimestamp: uint40(block.timestamp),
            defaultTimestamp: uint40(block.timestamp + loanDurationInDays * 1 days),
            borrower: borrower,
            originalLender: lender,
            accruingInterestAPR: 0,
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
            accruingInterestAPR: 0,
            lenderSpecHash: loan.getLenderSpecHash(lenderSpec),
            borrowerSpecHash: bytes32(0)
        });

        proposalSpec = PWNSimpleLoan.ProposalSpec({
            proposalContract: proposalContract,
            proposalData: proposalData,
            proposalInclusionProof: new bytes32[](0),
            signature: signature
        });

        nonExistingLoan = PWNSimpleLoan.LOAN({
            status: 0,
            creditAddress: address(0),
            originalSourceOfFunds: address(0),
            startTimestamp: 0,
            defaultTimestamp: 0,
            borrower: address(0),
            originalLender: address(0),
            accruingInterestAPR: 0,
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
        vm.mockCall(config, abi.encodeWithSignature("getPoolAdapter(address)"), abi.encode(poolAdapter));

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
        assertEq(_simpleLoan1.originalSourceOfFunds, _simpleLoan2.originalSourceOfFunds);
        assertEq(_simpleLoan1.startTimestamp, _simpleLoan2.startTimestamp);
        assertEq(_simpleLoan1.defaultTimestamp, _simpleLoan2.defaultTimestamp);
        assertEq(_simpleLoan1.borrower, _simpleLoan2.borrower);
        assertEq(_simpleLoan1.originalLender, _simpleLoan2.originalLender);
        assertEq(_simpleLoan1.accruingInterestAPR, _simpleLoan2.accruingInterestAPR);
        assertEq(_simpleLoan1.fixedInterestAmount, _simpleLoan2.fixedInterestAmount);
        assertEq(_simpleLoan1.principalAmount, _simpleLoan2.principalAmount);
        assertEq(uint8(_simpleLoan1.collateral.category), uint8(_simpleLoan2.collateral.category));
        assertEq(_simpleLoan1.collateral.assetAddress, _simpleLoan2.collateral.assetAddress);
        assertEq(_simpleLoan1.collateral.id, _simpleLoan2.collateral.id);
        assertEq(_simpleLoan1.collateral.amount, _simpleLoan2.collateral.amount);
    }

    function _assertLOANEq(uint256 _loanId, PWNSimpleLoan.LOAN memory _simpleLoan) internal {
        uint256 loanSlot = uint256(keccak256(abi.encode(_loanId, LOANS_SLOT)));

        // Status, credit address
        _assertLOANWord(loanSlot + 0, abi.encodePacked(uint88(0), _simpleLoan.creditAddress, _simpleLoan.status));
        // Original source of funds, start timestamp, default timestamp
        _assertLOANWord(loanSlot + 1, abi.encodePacked(uint16(0), _simpleLoan.defaultTimestamp, _simpleLoan.startTimestamp, _simpleLoan.originalSourceOfFunds));
        // Borrower address
        _assertLOANWord(loanSlot + 2, abi.encodePacked(uint96(0), _simpleLoan.borrower));
        // Original lender, accruing interest daily rate
        _assertLOANWord(loanSlot + 3, abi.encodePacked(uint72(0), _simpleLoan.accruingInterestAPR, _simpleLoan.originalLender));
        // Fixed interest amount
        _assertLOANWord(loanSlot + 4, abi.encodePacked(_simpleLoan.fixedInterestAmount));
        // Principal amount
        _assertLOANWord(loanSlot + 5, abi.encodePacked(_simpleLoan.principalAmount));
        // Collateral category, collateral asset address
        _assertLOANWord(loanSlot + 6, abi.encodePacked(uint88(0), _simpleLoan.collateral.assetAddress, _simpleLoan.collateral.category));
        // Collateral id
        _assertLOANWord(loanSlot + 7, abi.encodePacked(_simpleLoan.collateral.id));
        // Collateral amount
        _assertLOANWord(loanSlot + 8, abi.encodePacked(_simpleLoan.collateral.amount));
    }


    function _mockLOAN(uint256 _loanId, PWNSimpleLoan.LOAN memory _simpleLoan) internal {
        uint256 loanSlot = uint256(keccak256(abi.encode(_loanId, LOANS_SLOT)));

        // Status, credit address
        _storeLOANWord(loanSlot + 0, abi.encodePacked(uint88(0), _simpleLoan.creditAddress, _simpleLoan.status));
        // Original source of funds, start timestamp, default timestamp
        _storeLOANWord(loanSlot + 1, abi.encodePacked(uint16(0), _simpleLoan.defaultTimestamp, _simpleLoan.startTimestamp, _simpleLoan.originalSourceOfFunds));
        // Borrower address
        _storeLOANWord(loanSlot + 2, abi.encodePacked(uint96(0), _simpleLoan.borrower));
        // Original lender, accruing interest daily rate
        _storeLOANWord(loanSlot + 3, abi.encodePacked(uint72(0), _simpleLoan.accruingInterestAPR, _simpleLoan.originalLender));
        // Fixed interest amount
        _storeLOANWord(loanSlot + 4, abi.encodePacked(_simpleLoan.fixedInterestAmount));
        // Principal amount
        _storeLOANWord(loanSlot + 5, abi.encodePacked(_simpleLoan.principalAmount));
        // Collateral category, collateral asset address
        _storeLOANWord(loanSlot + 6, abi.encodePacked(uint88(0), _simpleLoan.collateral.assetAddress, _simpleLoan.collateral.category));
        // Collateral id
        _storeLOANWord(loanSlot + 7, abi.encodePacked(_simpleLoan.collateral.id));
        // Collateral amount
        _storeLOANWord(loanSlot + 8, abi.encodePacked(_simpleLoan.collateral.amount));
    }

    function _mockLoanTerms(PWNSimpleLoan.Terms memory _terms) internal {
        vm.mockCall(
            proposalContract,
            abi.encodeWithSignature("acceptProposal(address,uint256,bytes,bytes32[],bytes)"),
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
|*  # GET LENDER SPEC HASH                                  *|
|*----------------------------------------------------------*/

contract PWNSimpleLoan_GetLenderSpecHash_Test is PWNSimpleLoanTest {

    function test_shouldReturnLenderSpecHash() external {
        assertEq(keccak256(abi.encode(lenderSpec)), loan.getLenderSpecHash(lenderSpec));
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
            lenderSpec: lenderSpec,
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
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldNotRevokeCallersNonce_whenFlagIsFalse(address caller, uint256 nonce) external {
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
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldCallProposalContract(
        address caller, bytes memory _proposalData, bytes32[] memory _proposalInclusionProof, bytes memory _signature
    ) external {
        proposalSpec.proposalData = _proposalData;
        proposalSpec.proposalInclusionProof = _proposalInclusionProof;
        proposalSpec.signature = _signature;

        vm.expectCall(
            proposalContract,
            abi.encodeWithSignature(
                "acceptProposal(address,uint256,bytes,bytes32[],bytes)",
                caller, 0, _proposalData, _proposalInclusionProof, _signature
            )
        );

        vm.prank(caller);
        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldFail_whenCallerNotLender_whenLenderSpecHashMismatch(bytes32 lenderSpecHash) external {
        bytes32 correctLenderSpecHash = loan.getLenderSpecHash(lenderSpec);
        vm.assume(lenderSpecHash != correctLenderSpecHash);

        simpleLoanTerms.lenderSpecHash = lenderSpecHash;
        _mockLoanTerms(simpleLoanTerms);

        vm.expectRevert(
            abi.encodeWithSelector(PWNSimpleLoan.InvalidLenderSpecHash.selector, lenderSpecHash, correctLenderSpecHash)
        );
        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function test_shouldNotFail_whenCallerLender_whenLenderSpecHashMismatch() external {
        simpleLoanTerms.lenderSpecHash = bytes32(0);
        _mockLoanTerms(simpleLoanTerms);

        vm.prank(lender);
        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
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

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoan.InvalidDuration.selector, duration, minDuration));
        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldFail_whenLoanTermsInterestAPROutOfBounds(uint256 interestAPR) external {
        uint256 maxInterest = loan.MAX_ACCRUING_INTEREST_APR();
        interestAPR = bound(interestAPR, maxInterest + 1, type(uint24).max);
        simpleLoanTerms.accruingInterestAPR = uint24(interestAPR);
        _mockLoanTerms(simpleLoanTerms);

        vm.expectRevert(
            abi.encodeWithSelector(PWNSimpleLoan.InterestAPROutOfBounds.selector, interestAPR, maxInterest)
        );
        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
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
                PWNSimpleLoan.InvalidMultiTokenAsset.selector,
                uint8(simpleLoanTerms.credit.category),
                simpleLoanTerms.credit.assetAddress,
                simpleLoanTerms.credit.id,
                simpleLoanTerms.credit.amount
            )
        );
        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
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
                PWNSimpleLoan.InvalidMultiTokenAsset.selector,
                uint8(simpleLoanTerms.collateral.category),
                simpleLoanTerms.collateral.assetAddress,
                simpleLoanTerms.collateral.id,
                simpleLoanTerms.collateral.amount
            )
        );
        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function test_shouldMintLOANToken() external {
        vm.expectCall(address(loanToken), abi.encodeWithSignature("mint(address)", lender));

        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function test_shouldStoreLoanData() external {
        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });

        _assertLOANEq(loanId, simpleLoan);
    }

    function testFuzz_shouldFail_whenInvalidPermitData_permitOwner(address permitOwner) external {
        vm.assume(permitOwner != borrower && permitOwner != address(0));
        permit.asset = simpleLoan.creditAddress;
        permit.owner = permitOwner;

        callerSpec.permitData = abi.encode(permit);

        vm.expectRevert(abi.encodeWithSelector(InvalidPermitOwner.selector, permitOwner, borrower));
        vm.prank(borrower);
        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldFail_whenInvalidPermitData_permitAsset(address permitAsset) external {
        vm.assume(permitAsset != simpleLoan.creditAddress && permitAsset != address(0));
        permit.asset = permitAsset;
        permit.owner = borrower;

        callerSpec.permitData = abi.encode(permit);

        vm.expectRevert(abi.encodeWithSelector(InvalidPermitAsset.selector, permitAsset, simpleLoan.creditAddress));
        vm.prank(borrower);
        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
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

        callerSpec.permitData = abi.encode(permit);

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
            lenderSpec: lenderSpec,
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
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function test_shouldFail_whenPoolAdapterNotRegistered_whenPoolSourceOfFunds() external {
        lenderSpec.sourceOfFunds = sourceOfFunds;
        simpleLoanTerms.lenderSpecHash = loan.getLenderSpecHash(lenderSpec);
        _mockLoanTerms(simpleLoanTerms);

        vm.mockCall(config, abi.encodeWithSignature("getPoolAdapter(address)", sourceOfFunds), abi.encode(address(0)));

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoan.InvalidSourceOfFunds.selector, sourceOfFunds));
        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldCallWithdraw_whenPoolSourceOfFunds(uint256 loanAmount) external {
        loanAmount = bound(loanAmount, 1, 1e40);

        lenderSpec.sourceOfFunds = sourceOfFunds;
        simpleLoanTerms.lenderSpecHash = loan.getLenderSpecHash(lenderSpec);
        simpleLoanTerms.credit.amount = loanAmount;
        _mockLoanTerms(simpleLoanTerms);

        fungibleAsset.mint(sourceOfFunds, loanAmount);

        vm.expectCall(
            poolAdapter,
            abi.encodeWithSignature(
                "withdraw(address,address,address,uint256)",
                sourceOfFunds, lender, simpleLoanTerms.credit.assetAddress, loanAmount
            )
        );

        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldTransferCredit_toBorrowerAndFeeCollector(
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
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function test_shouldEmit_LOANCreated() external {
        vm.expectEmit();
        emit LOANCreated(loanId, proposalHash, proposalContract, 0, simpleLoanTerms, lenderSpec, "lil extra");

        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: "lil extra"
        });
    }

    function testFuzz_shouldReturnNewLoanId(uint256 _loanId) external {
        _mockLOANMint(_loanId);

        uint256 createdLoanId = loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });

        assertEq(createdLoanId, _loanId);
    }

}


/*----------------------------------------------------------*|
|*  # REFINANCE LOAN                                        *|
|*----------------------------------------------------------*/

/// @dev This contract tests only different behaviour of `createLOAN` with refinancingLoanId > 0.
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
            originalSourceOfFunds: lender,
            startTimestamp: uint40(block.timestamp),
            defaultTimestamp: uint40(block.timestamp + 40039),
            borrower: borrower,
            originalLender: lender,
            accruingInterestAPR: 0,
            fixedInterestAmount: 6631,
            principalAmount: 100e18,
            collateral: MultiToken.ERC721(address(nonFungibleAsset), 2)
        });

        refinancedLoanTerms = PWNSimpleLoan.Terms({
            lender: lender,
            borrower: borrower,
            duration: 40039,
            collateral: MultiToken.ERC721(address(nonFungibleAsset), 2),
            credit: MultiToken.ERC20(address(fungibleAsset), 100e18),
            fixedInterestAmount: 6631,
            accruingInterestAPR: 0,
            lenderSpecHash: loan.getLenderSpecHash(lenderSpec),
            borrowerSpecHash: bytes32(0)
        });

        _mockLoanTerms(refinancedLoanTerms);
        _mockLOAN(refinancingLoanId, simpleLoan);
        _mockLOANTokenOwner(refinancingLoanId, lender);
        callerSpec.refinancingLoanId = refinancingLoanId;

        vm.prank(newLender);
        fungibleAsset.approve(address(loan), type(uint256).max);

        fungibleAsset.mint(newLender, 100e18);
        fungibleAsset.mint(lender, 100e18);
        fungibleAsset.mint(address(loan), 100e18);
    }


    function test_shouldFail_whenLoanDoesNotExist() external {
        simpleLoan.status = 0;
        _mockLOAN(refinancingLoanId, simpleLoan);

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoan.NonExistingLoan.selector));
        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function test_shouldFail_whenLoanIsNotRunning() external {
        simpleLoan.status = 3;
        _mockLOAN(refinancingLoanId, simpleLoan);

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoan.LoanNotRunning.selector));
        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function test_shouldFail_whenLoanIsDefaulted() external {
        vm.warp(simpleLoan.defaultTimestamp);

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoan.LoanDefaulted.selector, simpleLoan.defaultTimestamp));
        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldFail_whenCreditAssetMismatch(address _assetAddress) external {
        vm.assume(_assetAddress != simpleLoan.creditAddress);
        refinancedLoanTerms.credit.assetAddress = _assetAddress;
        _mockLoanTerms(refinancedLoanTerms);

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoan.RefinanceCreditMismatch.selector));
        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function test_shouldFail_whenCreditAssetAmountZero() external {
        refinancedLoanTerms.credit.amount = 0;
        _mockLoanTerms(refinancedLoanTerms);

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoan.RefinanceCreditMismatch.selector));
        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldFail_whenCollateralCategoryMismatch(uint8 _category) external {
        _category = _category % 4;
        vm.assume(_category != uint8(simpleLoan.collateral.category));
        refinancedLoanTerms.collateral.category = MultiToken.Category(_category);
        _mockLoanTerms(refinancedLoanTerms);

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoan.RefinanceCollateralMismatch.selector));
        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldFail_whenCollateralAddressMismatch(address _assetAddress) external {
        vm.assume(_assetAddress != simpleLoan.collateral.assetAddress);
        refinancedLoanTerms.collateral.assetAddress = _assetAddress;
        _mockLoanTerms(refinancedLoanTerms);

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoan.RefinanceCollateralMismatch.selector));
        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldFail_whenCollateralIdMismatch(uint256 _id) external {
        vm.assume(_id != simpleLoan.collateral.id);
        refinancedLoanTerms.collateral.id = _id;
        _mockLoanTerms(refinancedLoanTerms);

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoan.RefinanceCollateralMismatch.selector));
        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldFail_whenCollateralAmountMismatch(uint256 _amount) external {
        vm.assume(_amount != simpleLoan.collateral.amount);
        refinancedLoanTerms.collateral.amount = _amount;
        _mockLoanTerms(refinancedLoanTerms);

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoan.RefinanceCollateralMismatch.selector));
        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldFail_whenBorrowerMismatch(address _borrower) external {
        vm.assume(_borrower != simpleLoan.borrower);
        refinancedLoanTerms.borrower = _borrower;
        _mockLoanTerms(refinancedLoanTerms);

        vm.expectRevert(
            abi.encodeWithSelector(PWNSimpleLoan.RefinanceBorrowerMismatch.selector, simpleLoan.borrower, _borrower)
        );
        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function test_shouldEmit_LOANPaidBack() external {
        vm.expectEmit();
        emit LOANPaidBack(refinancingLoanId);

        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function test_shouldEmit_LOANCreated() external {
        vm.expectEmit();
        emit LOANCreated(loanId, proposalHash, proposalContract, refinancingLoanId, refinancedLoanTerms, lenderSpec, "lil extra");

        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: "lil extra"
        });
    }

    function test_shouldDeleteLoan_whenLOANOwnerIsOriginalLender() external {
        vm.expectCall(loanToken, abi.encodeWithSignature("burn(uint256)", refinancingLoanId));

        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
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
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function test_shouldUpdateLoanData_whenLOANOwnerIsNotOriginalLender() external {
        _mockLOANTokenOwner(refinancingLoanId, makeAddr("notOriginalLender"));

        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });

        // Update loan and compare
        simpleLoan.status = 3; // move loan to repaid state
        simpleLoan.fixedInterestAmount = loan.loanRepaymentAmount(refinancingLoanId) - simpleLoan.principalAmount; // stored accrued interest at the time of repayment
        simpleLoan.accruingInterestAPR = 0; // stop accruing interest
        _assertLOANEq(refinancingLoanId, simpleLoan);
    }

    function test_shouldUpdateLoanData_whenLOANOwnerIsOriginalLender_whenDirectRepaymentFails() external {
        refinancedLoanTerms.credit.amount = simpleLoan.principalAmount - 1;
        _mockLoanTerms(refinancedLoanTerms);
        _mockLOANTokenOwner(refinancingLoanId, lender);

        vm.mockCallRevert(simpleLoan.creditAddress, abi.encodeWithSignature("transfer(address,uint256)"), "");

        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });

        // Update loan and compare
        simpleLoan.status = 3; // move loan to repaid state
        simpleLoan.fixedInterestAmount = loan.loanRepaymentAmount(refinancingLoanId) - simpleLoan.principalAmount; // stored accrued interest at the time of repayment
        simpleLoan.accruingInterestAPR = 0; // stop accruing interest
        _assertLOANEq(refinancingLoanId, simpleLoan);
    }

    // Pool withdraw

    function test_shouldFail_whenPoolAdapterNotRegistered_whenPoolSourceOfFunds() external {
        lenderSpec.sourceOfFunds = sourceOfFunds;
        simpleLoanTerms.lenderSpecHash = loan.getLenderSpecHash(lenderSpec);
        _mockLoanTerms(simpleLoanTerms);

        vm.mockCall(config, abi.encodeWithSignature("getPoolAdapter(address)", sourceOfFunds), abi.encode(address(0)));

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoan.InvalidSourceOfFunds.selector, sourceOfFunds));
        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function test_shouldWithdrawFullCreditAmount_whenShouldTransferCommon_whenPoolSourceOfFunds() external {
        lenderSpec.sourceOfFunds = sourceOfFunds;
        refinancedLoanTerms.lenderSpecHash = loan.getLenderSpecHash(lenderSpec);
        _mockLoanTerms(refinancedLoanTerms);

        vm.expectCall(
            poolAdapter,
            abi.encodeWithSignature(
                "withdraw(address,address,address,uint256)",
                sourceOfFunds, lender, refinancedLoanTerms.credit.assetAddress, refinancedLoanTerms.credit.amount
            )
        );

        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function test_shouldWithdrawCreditWithoutCommon_whenShouldNotTransferCommon_whenPoolSourceOfFunds() external {
        lenderSpec.sourceOfFunds = sourceOfFunds;
        refinancedLoanTerms.lender = newLender;
        refinancedLoanTerms.lenderSpecHash = loan.getLenderSpecHash(lenderSpec);
        _mockLoanTerms(refinancedLoanTerms);
        _mockLOANTokenOwner(refinancingLoanId, newLender);

        vm.assume(refinancedLoanTerms.credit.amount > loan.loanRepaymentAmount(refinancingLoanId));

        uint256 common = Math.min(
            refinancedLoanTerms.credit.amount, // fee is zero, use whole amount
            loan.loanRepaymentAmount(refinancingLoanId)
        );

        vm.expectCall(
            poolAdapter,
            abi.encodeWithSignature(
                "withdraw(address,address,address,uint256)",
                sourceOfFunds, newLender, refinancedLoanTerms.credit.assetAddress, refinancedLoanTerms.credit.amount - common
            )
        );

        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function test_shouldNotWithdrawCredit_whenShouldNotTransferCommon_whenNoSurplus_whenNoFee_whenPoolSourceOfFunds() external {
        lenderSpec.sourceOfFunds = sourceOfFunds;
        refinancedLoanTerms.lender = newLender;
        refinancedLoanTerms.lenderSpecHash = loan.getLenderSpecHash(lenderSpec);
        refinancedLoanTerms.credit.amount = loan.loanRepaymentAmount(refinancingLoanId);
        _mockLoanTerms(refinancedLoanTerms);
        _mockLOANTokenOwner(refinancingLoanId, newLender);

        vm.expectCall({
            callee: poolAdapter,
            data: abi.encodeWithSignature("withdraw(address,address,address,uint256)"),
            count: 0
        });

        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    // Fee

    function testFuzz_shouldTransferFeeToCollector(uint256 fee) external {
        fee = bound(fee, 1, 9999); // 0.01 - 99.99%

        uint256 feeAmount = Math.mulDiv(refinancedLoanTerms.credit.amount, fee, 1e4);

        vm.mockCall(config, abi.encodeWithSignature("fee()"), abi.encode(fee));

        vm.expectCall(
            refinancedLoanTerms.credit.assetAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", lender, feeCollector, feeAmount)
        );

        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    // Transfer of common

    function test_shouldTransferCommonToVaul_whenLenderNotLoanOwner() external {
        lenderSpec.sourceOfFunds = newLender;
        refinancedLoanTerms.lender = newLender;
        refinancedLoanTerms.lenderSpecHash = loan.getLenderSpecHash(lenderSpec);
        _mockLoanTerms(refinancedLoanTerms);
        _mockLOANTokenOwner(refinancingLoanId, makeAddr("loanOwner"));

        uint256 common = Math.min(
            refinancedLoanTerms.credit.amount,
            loan.loanRepaymentAmount(refinancingLoanId)
        );

        vm.expectCall(
            refinancedLoanTerms.credit.assetAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", newLender, address(loan), common)
        );

        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldTransferCommonToVaul_whenLenderOriginalLender_whenDifferentSourceOfFunds() external {
        lenderSpec.sourceOfFunds = newLender;
        refinancedLoanTerms.lender = newLender;
        refinancedLoanTerms.lenderSpecHash = loan.getLenderSpecHash(lenderSpec);
        _mockLoanTerms(refinancedLoanTerms);
        simpleLoan.originalLender = newLender;
        simpleLoan.originalSourceOfFunds = sourceOfFunds;
        _mockLOAN(refinancingLoanId, simpleLoan);
        _mockLOANTokenOwner(refinancingLoanId, newLender);

        uint256 common = Math.min(
            refinancedLoanTerms.credit.amount,
            loan.loanRepaymentAmount(refinancingLoanId)
        );

        vm.expectCall(
            refinancedLoanTerms.credit.assetAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", newLender, address(loan), common)
        );

        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    /// forge-config: default.fuzz.runs = 2
    function testFuzz_shouldNotTransferCommonToVaul_whenLenderLoanOwner_whenLenderOriginalLender_whenSameSourceOfFunds(bool sourceOfFundsflag) external {
        lenderSpec.sourceOfFunds = sourceOfFundsflag ? newLender : sourceOfFunds;
        refinancedLoanTerms.lender = newLender;
        refinancedLoanTerms.lenderSpecHash = loan.getLenderSpecHash(lenderSpec);
        _mockLoanTerms(refinancedLoanTerms);
        simpleLoan.originalLender = newLender;
        simpleLoan.originalSourceOfFunds = sourceOfFundsflag ? newLender : sourceOfFunds;
        _mockLOAN(refinancingLoanId, simpleLoan);
        _mockLOANTokenOwner(refinancingLoanId, newLender);

        vm.expectCall({
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature("transferFrom(address,address,uint256)", newLender, address(loan)),
            count: 0
        });

        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    // Surplus

    function test_shouldTransferSurplusToBorrower() external {
        lenderSpec.sourceOfFunds = newLender;
        refinancedLoanTerms.lender = newLender;
        refinancedLoanTerms.lenderSpecHash = loan.getLenderSpecHash(lenderSpec);
        _mockLoanTerms(refinancedLoanTerms);

        uint256 surplus = refinancedLoanTerms.credit.amount - loan.loanRepaymentAmount(refinancingLoanId);

        vm.expectCall(
            refinancedLoanTerms.credit.assetAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", newLender, borrower, surplus)
        );

        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function test_shouldNotTransferSurplusToBorrower_whenNoSurplus() external {
        lenderSpec.sourceOfFunds = newLender;
        refinancedLoanTerms.lender = newLender;
        refinancedLoanTerms.lenderSpecHash = loan.getLenderSpecHash(lenderSpec);
        _mockLoanTerms(refinancedLoanTerms);

        vm.expectCall({
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature("transferFrom(address,address,uint256)", newLender, borrower, 0),
            count: 0
        });

        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    // Shortage

    function test_shouldTransferShortageFromBorrowerToVaul() external {
        simpleLoan.principalAmount = refinancedLoanTerms.credit.amount + 1;
        _mockLOAN(refinancingLoanId, simpleLoan);

        uint256 shortage = loan.loanRepaymentAmount(refinancingLoanId) - refinancedLoanTerms.credit.amount;

        vm.expectCall(
            refinancedLoanTerms.credit.assetAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", borrower, address(loan), shortage)
        );

        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function test_shouldNotTransferShortageFromBorrowerToVaul_whenNoShortage() external {
        refinancedLoanTerms.credit.amount = loan.loanRepaymentAmount(refinancingLoanId);
        _mockLoanTerms(refinancedLoanTerms);

        vm.expectCall({
            callee: refinancedLoanTerms.credit.assetAddress,
            data: abi.encodeWithSignature("transferFrom(address,address,uint256)", borrower, address(loan), 0),
            count: 0
        });

        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    // Try claim repaid LOAN

    function testFuzz_shouldTryClaimRepaidLOAN_fullAmount_whenShouldTransferCommon(address loanOwner) external {
        vm.assume(loanOwner != address(0) && loanOwner != lender);
        _mockLOANTokenOwner(refinancingLoanId, loanOwner);

        vm.expectCall(
            address(loan),
            abi.encodeWithSignature(
                "tryClaimRepaidLOAN(uint256,uint256,address)",
                refinancingLoanId, loan.loanRepaymentAmount(refinancingLoanId), loanOwner
            )
        );

        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function testFuzz_shouldTryClaimRepaidLOAN_shortageAmount_whenShouldNotTransferCommon(uint256 shortage) external {
        simpleLoan.principalAmount = refinancedLoanTerms.credit.amount + 1;
        _mockLOAN(refinancingLoanId, simpleLoan);

        uint256 repaymentAmount = loan.loanRepaymentAmount(refinancingLoanId);
        shortage = bound(shortage, 0, repaymentAmount - 1);

        fungibleAsset.mint(borrower, shortage);

        refinancedLoanTerms.credit.amount = repaymentAmount - shortage;
        _mockLoanTerms(refinancedLoanTerms);

        vm.expectCall(
            address(loan),
            abi.encodeWithSignature(
                "tryClaimRepaidLOAN(uint256,uint256,address)",
                refinancingLoanId, shortage, lender
            )
        );

        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });
    }

    function test_shouldNotFail_whenTryClaimRepaidLOANFails() external {
        vm.mockCallRevert(
            address(loan),
            abi.encodeWithSignature("tryClaimRepaidLOAN(uint256,uint256,address)"),
            ""
        );

        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });

        simpleLoan.status = 3;
        simpleLoan.fixedInterestAmount = loan.loanRepaymentAmount(refinancingLoanId) - simpleLoan.principalAmount;
        simpleLoan.accruingInterestAPR = 0;
        _assertLOANEq(refinancingLoanId, simpleLoan);

    }

    // More overall tests

    function testFuzz_shouldRepayOriginalLoan(
        uint256 _days, uint256 principal, uint256 fixedInterest, uint256 interestAPR, uint256 refinanceAmount
    ) external {
        _days = bound(_days, 0, loanDurationInDays - 1);
        principal = bound(principal, 1, 1e40);
        fixedInterest = bound(fixedInterest, 0, 1e40);
        interestAPR = bound(interestAPR, 1, 16e6);

        simpleLoan.principalAmount = principal;
        simpleLoan.fixedInterestAmount = fixedInterest;
        simpleLoan.accruingInterestAPR = uint24(interestAPR);
        _mockLOAN(refinancingLoanId, simpleLoan);

        vm.warp(simpleLoan.startTimestamp + _days * 1 days);

        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(refinancingLoanId);
        refinanceAmount = bound(
            refinanceAmount, 1, type(uint256).max - loanRepaymentAmount - fungibleAsset.totalSupply()
        );

        lenderSpec.sourceOfFunds = newLender;
        refinancedLoanTerms.credit.amount = refinanceAmount;
        refinancedLoanTerms.lender = newLender;
        refinancedLoanTerms.lenderSpecHash = loan.getLenderSpecHash(lenderSpec);
        _mockLoanTerms(refinancedLoanTerms);
        _mockLOANTokenOwner(refinancingLoanId, lender);

        fungibleAsset.mint(newLender, refinanceAmount);
        if (loanRepaymentAmount > refinanceAmount) {
            fungibleAsset.mint(borrower, loanRepaymentAmount - refinanceAmount);
        }

        uint256 originalBalance = fungibleAsset.balanceOf(lender);

        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });

        assertEq(fungibleAsset.balanceOf(lender), originalBalance + loanRepaymentAmount);
    }

    function testFuzz_shouldCollectProtocolFee(
        uint256 _days, uint256 principal, uint256 fixedInterest, uint256 interestAPR, uint256 refinanceAmount, uint256 fee
    ) external {
        _days = bound(_days, 0, loanDurationInDays - 1);
        principal = bound(principal, 1, 1e40);
        fixedInterest = bound(fixedInterest, 0, 1e40);
        interestAPR = bound(interestAPR, 1, 16e6);

        simpleLoan.principalAmount = principal;
        simpleLoan.fixedInterestAmount = fixedInterest;
        simpleLoan.accruingInterestAPR = uint24(interestAPR);
        _mockLOAN(refinancingLoanId, simpleLoan);

        vm.warp(simpleLoan.startTimestamp + _days * 1 days);

        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(refinancingLoanId);
        fee = bound(fee, 1, 9999); // 0 - 99.99%
        refinanceAmount = bound(
            refinanceAmount, 1, type(uint256).max - loanRepaymentAmount - fungibleAsset.totalSupply()
        );
        uint256 feeAmount = Math.mulDiv(refinanceAmount, fee, 1e4);

        lenderSpec.sourceOfFunds = newLender;
        refinancedLoanTerms.credit.amount = refinanceAmount;
        refinancedLoanTerms.lender = newLender;
        refinancedLoanTerms.lenderSpecHash = loan.getLenderSpecHash(lenderSpec);
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
            lenderSpec: lenderSpec,
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

        lenderSpec.sourceOfFunds = newLender;
        refinancedLoanTerms.credit.amount = refinanceAmount;
        refinancedLoanTerms.lender = newLender;
        refinancedLoanTerms.lenderSpecHash = loan.getLenderSpecHash(lenderSpec);
        _mockLoanTerms(refinancedLoanTerms);
        _mockLOANTokenOwner(refinancingLoanId, lender);

        fungibleAsset.mint(newLender, refinanceAmount);
        uint256 originalBalance = fungibleAsset.balanceOf(borrower);

        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
            callerSpec: callerSpec,
            extra: ""
        });

        assertEq(fungibleAsset.balanceOf(borrower), originalBalance + surplus);
    }

    function testFuzz_shouldTransferShortageFromBorrower(uint256 refinanceAmount) external {
        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(refinancingLoanId);
        refinanceAmount = bound(refinanceAmount, 1, loanRepaymentAmount - 1);
        uint256 contribution = loanRepaymentAmount - refinanceAmount;

        lenderSpec.sourceOfFunds = newLender;
        refinancedLoanTerms.credit.amount = refinanceAmount;
        refinancedLoanTerms.lender = newLender;
        refinancedLoanTerms.lenderSpecHash = loan.getLenderSpecHash(lenderSpec);
        _mockLoanTerms(refinancedLoanTerms);
        _mockLOANTokenOwner(refinancingLoanId, lender);

        fungibleAsset.mint(newLender, refinanceAmount);
        uint256 originalBalance = fungibleAsset.balanceOf(borrower);

        loan.createLOAN({
            proposalSpec: proposalSpec,
            lenderSpec: lenderSpec,
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

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoan.NonExistingLoan.selector));
        loan.repayLOAN(loanId, "");
    }

    function testFuzz_shouldFail_whenLoanIsNotRunning(uint8 status) external {
        vm.assume(status != 0 && status != 2);

        simpleLoan.status = status;
        _mockLOAN(loanId, simpleLoan);

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoan.LoanNotRunning.selector));
        loan.repayLOAN(loanId, "");
    }

    function test_shouldFail_whenLoanIsDefaulted() external {
        vm.warp(simpleLoan.defaultTimestamp);

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoan.LoanDefaulted.selector, simpleLoan.defaultTimestamp));
        loan.repayLOAN(loanId, "");
    }

    function testFuzz_shouldFail_whenInvalidPermitOwner_whenPermitProvided(address permitOwner) external {
        vm.assume(permitOwner != borrower && permitOwner != address(0));
        permit.asset = simpleLoan.creditAddress;
        permit.owner = permitOwner;

        vm.expectRevert(abi.encodeWithSelector(InvalidPermitOwner.selector, permitOwner, borrower));
        vm.prank(borrower);
        loan.repayLOAN(loanId, abi.encode(permit));
    }

    function testFuzz_shouldFail_whenInvalidPermitAsset_whenPermitProvided(address permitAsset) external {
        vm.assume(permitAsset != simpleLoan.creditAddress && permitAsset != address(0));
        permit.asset = permitAsset;
        permit.owner = borrower;

        vm.expectRevert(abi.encodeWithSelector(InvalidPermitAsset.selector, permitAsset, simpleLoan.creditAddress));
        vm.prank(borrower);
        loan.repayLOAN(loanId, abi.encode(permit));
    }

    function test_shouldCallPermit_whenPermitProvided() external {
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
        loan.repayLOAN(loanId, abi.encode(permit));
    }

    function testFuzz_shouldUpdateLoanData_whenLOANOwnerIsNotOriginalLender(
        uint256 _days, uint256 _principal, uint256 _fixedInterest, uint256 _interestAPR
    ) external {
        _mockLOANTokenOwner(loanId, notOriginalLender);

        _days = bound(_days, 0, loanDurationInDays - 1);
        _principal = bound(_principal, 1, 1e40);
        _fixedInterest = bound(_fixedInterest, 0, 1e40);
        _interestAPR = bound(_interestAPR, 1, 16e6);

        simpleLoan.principalAmount = _principal;
        simpleLoan.fixedInterestAmount = _fixedInterest;
        simpleLoan.accruingInterestAPR = uint24(_interestAPR);
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.startTimestamp + _days * 1 days);

        uint256 loanRepaymentAmount = loan.loanRepaymentAmount(loanId);
        fungibleAsset.mint(borrower, loanRepaymentAmount);

        vm.prank(borrower);
        loan.repayLOAN(loanId, "");

        // Update loan and compare
        simpleLoan.status = 3; // move loan to repaid state
        simpleLoan.fixedInterestAmount = loanRepaymentAmount - _principal; // stored accrued interest at the time of repayment
        simpleLoan.accruingInterestAPR = 0; // stop accruing interest
        _assertLOANEq(loanId, simpleLoan);
    }

    function test_shouldDeleteLoanData_whenLOANOwnerIsOriginalLender() external {
        loan.repayLOAN(loanId, "");

        _assertLOANEq(loanId, nonExistingLoan);
    }

    function test_shouldBurnLOANToken_whenLOANOwnerIsOriginalLender() external {
        vm.expectCall(loanToken, abi.encodeWithSignature("burn(uint256)", loanId));

        loan.repayLOAN(loanId, "");
    }

    function testFuzz_shouldTransferRepaidAmountToVault(
        uint256 _days, uint256 _principal, uint256 _fixedInterest, uint256 _interestAPR
    ) external {
        _days = bound(_days, 0, loanDurationInDays - 1);
        _principal = bound(_principal, 1, 1e40);
        _fixedInterest = bound(_fixedInterest, 0, 1e40);
        _interestAPR = bound(_interestAPR, 1, 16e6);

        simpleLoan.principalAmount = _principal;
        simpleLoan.fixedInterestAmount = _fixedInterest;
        simpleLoan.accruingInterestAPR = uint24(_interestAPR);
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
        loan.repayLOAN(loanId, "");
    }

    function test_shouldTransferCollateralToBorrower() external {
        vm.expectCall(
            simpleLoan.collateral.assetAddress,
            abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256,bytes)",
                address(loan), simpleLoan.borrower, simpleLoan.collateral.id
            )
        );

        loan.repayLOAN(loanId, "");
    }

    function test_shouldEmit_LOANPaidBack() external {
        vm.expectEmit();
        emit LOANPaidBack(loanId);

        loan.repayLOAN(loanId, "");
    }

    function testFuzz_shouldCall_tryClaimRepaidLOAN(address loanOwner) external {
        vm.assume(loanOwner != address(0));
        _mockLOANTokenOwner(loanId, loanOwner);

        vm.expectCall(
            address(loan),
            abi.encodeWithSignature(
                "tryClaimRepaidLOAN(uint256,uint256,address)", loanId, loan.loanRepaymentAmount(loanId), loanOwner
            )
        );

        loan.repayLOAN(loanId, "");
    }

    function test_shouldNotFail_whenTryClaimRepaidLOANFails() external {
        vm.mockCallRevert(
            address(loan),
            abi.encodeWithSignature("tryClaimRepaidLOAN(uint256,uint256,address)"),
            ""
        );

        loan.repayLOAN(loanId, "");

        simpleLoan.status = 3;
        simpleLoan.fixedInterestAmount = loan.loanRepaymentAmount(loanId) - simpleLoan.principalAmount;
        simpleLoan.accruingInterestAPR = 0;
        _assertLOANEq(loanId, simpleLoan);
    }

    function test_shouldEmit_LOANClaimed_whenLOANOwnerIsOriginalLender() external {
        vm.expectEmit();
        emit LOANClaimed(loanId, false);

        loan.repayLOAN(loanId, "");
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
        simpleLoan.accruingInterestAPR = 0;
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.startTimestamp + _days + 1 days); // should not have an effect

        assertEq(loan.loanRepaymentAmount(loanId), _principal + _fixedInterest);
    }

    function testFuzz_shouldReturnAccruedInterest_whenNonZeroAccruedInterest(
        uint256 _minutes, uint256 _principal, uint256 _fixedInterest, uint256 _interestAPR
    ) external {
        _minutes = bound(_minutes, 0, 2 * loanDurationInDays * 24 * 60); // should return non zero value even after loan expiration
        _principal = bound(_principal, 1, 1e40);
        _fixedInterest = bound(_fixedInterest, 0, 1e40);
        _interestAPR = bound(_interestAPR, 1, 16e6);

        simpleLoan.defaultTimestamp = simpleLoan.startTimestamp + 101 * 1 days;
        simpleLoan.principalAmount = _principal;
        simpleLoan.fixedInterestAmount = _fixedInterest;
        simpleLoan.accruingInterestAPR = uint24(_interestAPR);
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.startTimestamp + _minutes * 1 minutes + 1);

        uint256 expectedInterest = _fixedInterest + _principal * _interestAPR * _minutes / (1e2 * 60 * 24 * 365) / 100;
        uint256 expectedLoanRepaymentAmount = _principal + expectedInterest;
        assertEq(loan.loanRepaymentAmount(loanId), expectedLoanRepaymentAmount);
    }

    function test_shouldReturnAccuredInterest() external {
        simpleLoan.defaultTimestamp = simpleLoan.startTimestamp + 101 * 1 days;
        simpleLoan.principalAmount = 100e18;
        simpleLoan.fixedInterestAmount = 10e18;
        simpleLoan.accruingInterestAPR = uint24(365e2);
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.startTimestamp);
        assertEq(loan.loanRepaymentAmount(loanId), simpleLoan.principalAmount + simpleLoan.fixedInterestAmount);

        vm.warp(simpleLoan.startTimestamp + 1 days);
        assertEq(loan.loanRepaymentAmount(loanId), simpleLoan.principalAmount + simpleLoan.fixedInterestAmount + 1e18);

        simpleLoan.accruingInterestAPR = uint24(100e2);
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.startTimestamp + 365 days);
        assertEq(loan.loanRepaymentAmount(loanId), 2 * simpleLoan.principalAmount + simpleLoan.fixedInterestAmount);
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

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoan.CallerNotLOANTokenHolder.selector));
        vm.prank(caller);
        loan.claimLOAN(loanId);
    }

    function test_shouldFail_whenLoanDoesNotExist() external {
        simpleLoan.status = 0;
        _mockLOAN(loanId, simpleLoan);

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoan.NonExistingLoan.selector));
        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

    function test_shouldFail_whenLoanIsNotRepaidNorExpired() external {
        simpleLoan.status = 2;
        _mockLOAN(loanId, simpleLoan);

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoan.LoanRunning.selector));
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
        // at the time of repayment and set `accruingInterestAPR` to zero.
        simpleLoan.principalAmount = _principal;
        simpleLoan.fixedInterestAmount = _fixedInterest;
        simpleLoan.accruingInterestAPR = 0;
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

    function test_shouldEmit_LOANClaimed_whenRepaid() external {
        vm.expectEmit();
        emit LOANClaimed(loanId, false);

        vm.prank(lender);
        loan.claimLOAN(loanId);
    }

    function test_shouldEmit_LOANClaimed_whenDefaulted() external {
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
|*  # TRY CLAIM REPAID LOAN                                 *|
|*----------------------------------------------------------*/

contract PWNSimpleLoan_TryClaimRepaidLOAN_Test is PWNSimpleLoanTest {

    uint256 public creditAmount;

    function setUp() override public {
        super.setUp();

        simpleLoan.status = 3;
        _mockLOAN(loanId, simpleLoan);

        // Move collateral to vault
        vm.prank(borrower);
        nonFungibleAsset.transferFrom(borrower, address(loan), 2);

        creditAmount = 100;
    }


    function testFuzz_shouldFail_whenCallerIsNotVault(address caller) external {
        vm.assume(caller != address(loan));

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoan.CallerNotVault.selector));
        vm.prank(caller);
        loan.tryClaimRepaidLOAN(loanId, creditAmount, lender);
    }

    function testFuzz_shouldNotProceed_whenLoanNotInRepaidState(uint8 status) external {
        vm.assume(status != 3);

        simpleLoan.status = status;
        _mockLOAN(loanId, simpleLoan);

        vm.expectCall({ // Expect no call
            callee: loanToken,
            data: abi.encodeWithSignature("burn(uint256)", loanId),
            count: 0
        });

        vm.prank(address(loan));
        loan.tryClaimRepaidLOAN(loanId, creditAmount, lender);

        _assertLOANEq(loanId, simpleLoan);
    }

    function testFuzz_shouldNotProceed_whenOriginalLenderNotEqualToLoanOwner(address loanOwner) external {
        vm.assume(loanOwner != lender);

        vm.expectCall({ // Expect no call
            callee: loanToken,
            data: abi.encodeWithSignature("burn(uint256)", loanId),
            count: 0
        });

        vm.prank(address(loan));
        loan.tryClaimRepaidLOAN(loanId, creditAmount, loanOwner);

        _assertLOANEq(loanId, simpleLoan);
    }

    function test_shouldBurnLOANToken() external {
        vm.expectCall(loanToken, abi.encodeWithSignature("burn(uint256)", loanId));

        vm.prank(address(loan));
        loan.tryClaimRepaidLOAN(loanId, creditAmount, lender);
    }

    function test_shouldDeleteLOANData() external {
        vm.prank(address(loan));
        loan.tryClaimRepaidLOAN(loanId, creditAmount, lender);

        _assertLOANEq(loanId, nonExistingLoan);
    }

    function test_shouldNotCallTransfer_whenCreditAmountIsZero() external {
        simpleLoan.originalSourceOfFunds = lender;
        _mockLOAN(loanId, simpleLoan);

        vm.expectCall({
            callee: simpleLoan.creditAddress,
            data: abi.encodeWithSignature("transfer(address,uint256)", lender, 0),
            count: 0
        });

        vm.prank(address(loan));
        loan.tryClaimRepaidLOAN(loanId, 0, lender);
    }

    function test_shouldTransferToOriginalLender_whenSourceOfFundsEqualToOriginalLender() external {
        simpleLoan.originalSourceOfFunds = lender;
        _mockLOAN(loanId, simpleLoan);

        vm.expectCall(
            simpleLoan.creditAddress,
            abi.encodeWithSignature("transfer(address,uint256)", lender, creditAmount)
        );

        vm.prank(address(loan));
        loan.tryClaimRepaidLOAN(loanId, creditAmount, lender);
    }

    function test_shouldFail_whenPoolAdapterNotRegistered_whenSourceOfFundsNotEqualToOriginalLender() external {
        simpleLoan.originalSourceOfFunds = sourceOfFunds;
        _mockLOAN(loanId, simpleLoan);

        vm.mockCall(
            config, abi.encodeWithSignature("getPoolAdapter(address)", sourceOfFunds), abi.encode(address(0))
        );

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoan.InvalidSourceOfFunds.selector, sourceOfFunds));
        vm.prank(address(loan));
        loan.tryClaimRepaidLOAN(loanId, creditAmount, lender);
    }

    function test_shouldTransferAmountToPoolAdapter_whenSourceOfFundsNotEqualToOriginalLender() external {
        simpleLoan.originalSourceOfFunds = sourceOfFunds;
        _mockLOAN(loanId, simpleLoan);

        vm.expectCall(
            simpleLoan.creditAddress,
            abi.encodeWithSignature("transfer(address,uint256)", poolAdapter, creditAmount)
        );

        vm.prank(address(loan));
        loan.tryClaimRepaidLOAN(loanId, creditAmount, lender);
    }

    function test_shouldCallSupplyOnPoolAdapter_whenSourceOfFundsNotEqualToOriginalLender() external {
        simpleLoan.originalSourceOfFunds = sourceOfFunds;
        _mockLOAN(loanId, simpleLoan);

        vm.expectCall(
            poolAdapter,
            abi.encodeWithSignature(
                "supply(address,address,address,uint256)", sourceOfFunds, lender, simpleLoan.creditAddress, creditAmount
            )
        );

        vm.prank(address(loan));
        loan.tryClaimRepaidLOAN(loanId, creditAmount, lender);
    }

    function test_shouldFail_whenTransferFails_whenSourceOfFundsEqualToOriginalLender() external {
        simpleLoan.originalSourceOfFunds = lender;
        _mockLOAN(loanId, simpleLoan);

        vm.mockCallRevert(simpleLoan.creditAddress, abi.encodeWithSignature("transfer(address,uint256)"), "");

        vm.expectRevert();
        vm.prank(address(loan));
        loan.tryClaimRepaidLOAN(loanId, creditAmount, lender);
    }

    function test_shouldFail_whenTransferFails_whenSourceOfFundsNotEqualToOriginalLender() external {
        simpleLoan.originalSourceOfFunds = sourceOfFunds;
        _mockLOAN(loanId, simpleLoan);

        vm.mockCallRevert(poolAdapter, abi.encodeWithSignature("supply(address,address,address,uint256)"), "");

        vm.expectRevert();
        vm.prank(address(loan));
        loan.tryClaimRepaidLOAN(loanId, creditAmount, lender);
    }

    function test_shouldEmit_LOANClaimed() external {
        vm.expectEmit();
        emit LOANClaimed(loanId, false);

        vm.prank(address(loan));
        loan.tryClaimRepaidLOAN(loanId, creditAmount, lender);
    }

}


/*----------------------------------------------------------*|
|*  # MAKE EXTENSION PROPOSAL                               *|
|*----------------------------------------------------------*/

contract PWNSimpleLoan_MakeExtensionProposal_Test is PWNSimpleLoanTest {

    function testFuzz_shouldFail_whenCallerNotProposer(address caller) external {
        vm.assume(caller != extension.proposer);

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoan.InvalidExtensionSigner.selector, extension.proposer, caller));
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

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoan.NonExistingLoan.selector));
        vm.prank(lender);
        loan.extendLOAN(extension, "", "");
    }

    function test_shouldFail_whenLoanIsRepaid() external {
        simpleLoan.status = 3;
        _mockLOAN(loanId, simpleLoan);

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoan.LoanRepaid.selector));
        vm.prank(lender);
        loan.extendLOAN(extension, "", "");
    }

    function testFuzz_shouldFail_whenInvalidSignature_whenEOA(uint256 pk) external {
        pk = boundPrivateKey(pk);
        vm.assume(pk != borrowerPk);

        vm.expectRevert(abi.encodeWithSelector(PWNSignatureChecker.InvalidSignature.selector, extension.proposer, _extensionHash(extension)));
        vm.prank(lender);
        loan.extendLOAN(extension, _signExtension(pk, extension), "");
    }

    function testFuzz_shouldFail_whenOfferExpirated(uint40 expiration) external {
        uint256 timestamp = 300;
        vm.warp(timestamp);

        extension.expiration = uint40(bound(expiration, 0, timestamp));
        _mockExtensionProposalMade(extension);

        vm.expectRevert(abi.encodeWithSelector(Expired.selector, block.timestamp, extension.expiration));
        vm.prank(lender);
        loan.extendLOAN(extension, "", "");
    }

    function test_shouldFail_whenOfferNonceNotUsable() external {
        _mockExtensionProposalMade(extension);

        vm.mockCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)", extension.proposer, extension.nonceSpace, extension.nonce),
            abi.encode(false)
        );

        vm.expectRevert(abi.encodeWithSelector(
            PWNRevokedNonce.NonceNotUsable.selector, extension.proposer, extension.nonceSpace, extension.nonce
        ));
        vm.prank(lender);
        loan.extendLOAN(extension, "", "");
    }

    function testFuzz_shouldFail_whenCallerIsNotBorrowerNorLoanOwner(address caller) external {
        vm.assume(caller != borrower && caller != lender);
        _mockExtensionProposalMade(extension);

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoan.InvalidExtensionCaller.selector));
        vm.prank(caller);
        loan.extendLOAN(extension, "", "");
    }

    function testFuzz_shouldFail_whenCallerIsBorrower_andProposerIsNotLoanOwner(address proposer) external {
        vm.assume(proposer != lender);

        extension.proposer = proposer;
        _mockExtensionProposalMade(extension);

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoan.InvalidExtensionSigner.selector, lender, proposer));
        vm.prank(borrower);
        loan.extendLOAN(extension, "", "");
    }

    function testFuzz_shouldFail_whenCallerIsLoanOwner_andProposerIsNotBorrower(address proposer) external {
        vm.assume(proposer != borrower);

        extension.proposer = proposer;
        _mockExtensionProposalMade(extension);

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoan.InvalidExtensionSigner.selector, borrower, proposer));
        vm.prank(lender);
        loan.extendLOAN(extension, "", "");
    }

    function testFuzz_shouldFail_whenExtensionDurationLessThanMin(uint40 duration) external {
        uint256 minDuration = loan.MIN_EXTENSION_DURATION();
        duration = uint40(bound(duration, 0, minDuration - 1));

        extension.duration = duration;
        _mockExtensionProposalMade(extension);

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoan.InvalidExtensionDuration.selector, duration, minDuration));
        vm.prank(lender);
        loan.extendLOAN(extension, "", "");
    }

    function testFuzz_shouldFail_whenExtensionDurationMoreThanMax(uint40 duration) external {
        uint256 maxDuration = loan.MAX_EXTENSION_DURATION();
        duration = uint40(bound(duration, maxDuration + 1, type(uint40).max));

        extension.duration = duration;
        _mockExtensionProposalMade(extension);

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoan.InvalidExtensionDuration.selector, duration, maxDuration));
        vm.prank(lender);
        loan.extendLOAN(extension, "", "");
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
        loan.extendLOAN(extension, "", "");
    }

    function testFuzz_shouldUpdateLoanData(uint40 duration) external {
        duration = uint40(bound(duration, loan.MIN_EXTENSION_DURATION(), loan.MAX_EXTENSION_DURATION()));

        extension.duration = duration;
        _mockExtensionProposalMade(extension);

        vm.prank(lender);
        loan.extendLOAN(extension, "", "");

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
        loan.extendLOAN(extension, "", "");
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
        loan.extendLOAN(extension, "", "");
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
        loan.extendLOAN(extension, "", "");
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

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNSimpleLoan.InvalidMultiTokenAsset.selector,
                0,
                extension.compensationAddress,
                0,
                extension.compensationAmount
            )
        );
        vm.prank(lender);
        loan.extendLOAN(extension, "", "");
    }

    function testFuzz_shouldFail_whenInvalidPermitData_permitOwner(address permitOwner) external {
        _mockExtensionProposalMade(extension);

        vm.assume(permitOwner != lender && permitOwner != address(0));
        permit.asset = extension.compensationAddress;
        permit.owner = permitOwner;

        vm.expectRevert(abi.encodeWithSelector(InvalidPermitOwner.selector, permitOwner, lender));
        vm.prank(lender);
        loan.extendLOAN(extension, "", abi.encode(permit));
    }

    function testFuzz_shouldFail_whenInvalidPermitData_permitAsset(address permitAsset) external {
        _mockExtensionProposalMade(extension);

        vm.assume(permitAsset != extension.compensationAddress && permitAsset != address(0));
        permit.asset = permitAsset;
        permit.owner = lender;

        vm.expectRevert(abi.encodeWithSelector(InvalidPermitAsset.selector, permitAsset, extension.compensationAddress));
        vm.prank(lender);
        loan.extendLOAN(extension, "", abi.encode(permit));
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
        loan.extendLOAN(extension, "", abi.encode(permit));
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
        loan.extendLOAN(extension, "", "");
    }

    function test_shouldPass_whenBorrowerSignature_whenLenderAccepts() external {
        extension.proposer = borrower;

        vm.prank(lender);
        loan.extendLOAN(extension, _signExtension(borrowerPk, extension), "");
    }

    function test_shouldPass_whenLenderSignature_whenBorrowerAccepts() external {
        extension.proposer = lender;

        vm.prank(borrower);
        loan.extendLOAN(extension, _signExtension(lenderPk, extension), "");
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

    function testFuzz_shouldReturnStaticLOANData_FirstPart(
        uint40 _startTimestamp,
        uint40 _defaultTimestamp,
        address _borrower,
        address _originalLender,
        uint24 _accruingInterestAPR,
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
        _accruingInterestAPR = uint24(bound(_accruingInterestAPR, 0, 16e6));
        _fixedInterestAmount = bound(_fixedInterestAmount, 0, type(uint256).max - _principalAmount);

        simpleLoan.startTimestamp = _startTimestamp;
        simpleLoan.defaultTimestamp = _defaultTimestamp;
        simpleLoan.borrower = _borrower;
        simpleLoan.originalLender = _originalLender;
        simpleLoan.accruingInterestAPR = _accruingInterestAPR;
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
            (, uint40 startTimestamp,,,,,,,,,,) = loan.getLOAN(loanId);
            assertEq(startTimestamp, _startTimestamp);
        }
        {
            (,, uint40 defaultTimestamp,,,,,,,,,) = loan.getLOAN(loanId);
            assertEq(defaultTimestamp, _defaultTimestamp);
        }
        {
            (,,, address borrower,,,,,,,,) = loan.getLOAN(loanId);
            assertEq(borrower, _borrower);
        }
        {
            (,,,, address originalLender,,,,,,,) = loan.getLOAN(loanId);
            assertEq(originalLender, _originalLender);
        }
        {
            (,,,,,, uint24 accruingInterestAPR,,,,,) = loan.getLOAN(loanId);
            assertEq(accruingInterestAPR, _accruingInterestAPR);
        }
        {
            (,,,,,,, uint256 fixedInterestAmount,,,,) = loan.getLOAN(loanId);
            assertEq(fixedInterestAmount, _fixedInterestAmount);
        }
        {
            (,,,,,,,, MultiToken.Asset memory credit,,,) = loan.getLOAN(loanId);
            assertEq(credit.assetAddress, _creditAddress);
            assertEq(credit.amount, _principalAmount);
        }
        {
            (,,,,,,,,, MultiToken.Asset memory collateral,,) = loan.getLOAN(loanId);
            assertEq(collateral.assetAddress, _collateralAssetAddress);
            assertEq(uint8(collateral.category), _collateralCategory % 4);
            assertEq(collateral.id, _collateralId);
            assertEq(collateral.amount, _collateralAmount);
        }
    }

    function testFuzz_shouldReturnStaticLOANData_SecondPart(
        address _originalSourceOfFunds
    ) external {
        simpleLoan.originalSourceOfFunds = _originalSourceOfFunds;

        _mockLOAN(loanId, simpleLoan);

        // test every property separately to avoid stack too deep error
        {
            (,,,,,,,,,, address originalSourceOfFunds,) = loan.getLOAN(loanId);
            assertEq(originalSourceOfFunds, _originalSourceOfFunds);
        }
    }

    function test_shouldReturnCorrectStatus() external {
        _mockLOAN(loanId, simpleLoan);

        (uint8 status,,,,,,,,,,,) = loan.getLOAN(loanId);
        assertEq(status, 2);

        vm.warp(simpleLoan.defaultTimestamp);

        (status,,,,,,,,,,,) = loan.getLOAN(loanId);
        assertEq(status, 4);

        simpleLoan.status = 3;
        _mockLOAN(loanId, simpleLoan);

        (status,,,,,,,,,,,) = loan.getLOAN(loanId);
        assertEq(status, 3);
    }

    function testFuzz_shouldReturnLOANTokenOwner(address _loanOwner) external {
        _mockLOAN(loanId, simpleLoan);
        _mockLOANTokenOwner(loanId, _loanOwner);

        (,,,,, address loanOwner,,,,,,) = loan.getLOAN(loanId);
        assertEq(loanOwner, _loanOwner);
    }

    function testFuzz_shouldReturnRepaymentAmount(
        uint256 _days,
        uint256 _principalAmount,
        uint24 _accruingInterestAPR,
        uint256 _fixedInterestAmount
    ) external {
        _days = bound(_days, 0, 2 * loanDurationInDays);
        _principalAmount = bound(_principalAmount, 1, 1e40);
        _accruingInterestAPR = uint24(bound(_accruingInterestAPR, 0, 16e6));
        _fixedInterestAmount = bound(_fixedInterestAmount, 0, _principalAmount);

        simpleLoan.accruingInterestAPR = _accruingInterestAPR;
        simpleLoan.fixedInterestAmount = _fixedInterestAmount;
        simpleLoan.principalAmount = _principalAmount;
        _mockLOAN(loanId, simpleLoan);

        vm.warp(simpleLoan.startTimestamp + _days * 1 days);

        (,,,,,,,,,,, uint256 repaymentAmount) = loan.getLOAN(loanId);
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
            uint24 accruingInterestAPR,
            uint256 fixedInterestAmount,
            MultiToken.Asset memory credit,
            MultiToken.Asset memory collateral,
            address originalSourceOfFunds,
            uint256 repaymentAmount
        ) = loan.getLOAN(nonExistingLoanId);

        assertEq(status, 0);
        assertEq(startTimestamp, 0);
        assertEq(defaultTimestamp, 0);
        assertEq(borrower, address(0));
        assertEq(originalLender, address(0));
        assertEq(loanOwner, address(0));
        assertEq(accruingInterestAPR, 0);
        assertEq(fixedInterestAmount, 0);
        assertEq(credit.assetAddress, address(0));
        assertEq(credit.amount, 0);
        assertEq(collateral.assetAddress, address(0));
        assertEq(uint8(collateral.category), 0);
        assertEq(collateral.id, 0);
        assertEq(collateral.amount, 0);
        assertEq(originalSourceOfFunds, address(0));
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
            keccak256(abi.encode(2, simpleLoan.defaultTimestamp, simpleLoan.fixedInterestAmount, simpleLoan.accruingInterestAPR))
        );

        vm.warp(simpleLoan.defaultTimestamp);
        assertEq(
            loan.getStateFingerprint(loanId),
            keccak256(abi.encode(4, simpleLoan.defaultTimestamp, simpleLoan.fixedInterestAmount, simpleLoan.accruingInterestAPR))
        );
    }

    function testFuzz_shouldReturnCorrectStateFingerprint(
        uint256 fixedInterestAmount, uint24 accruingInterestAPR
    ) external {
        simpleLoan.fixedInterestAmount = fixedInterestAmount;
        simpleLoan.accruingInterestAPR = accruingInterestAPR;
        _mockLOAN(loanId, simpleLoan);

        assertEq(
            loan.getStateFingerprint(loanId),
            keccak256(abi.encode(2, simpleLoan.defaultTimestamp, simpleLoan.fixedInterestAmount, simpleLoan.accruingInterestAPR))
        );
    }

}
