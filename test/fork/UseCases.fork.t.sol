// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken, ICryptoKitties, IERC20, IERC721 } from "MultiToken/MultiToken.sol";

import { Permit } from "src/loan/vault/Permit.sol";
import { CompoundAdapter } from "src/pool-adapter/CompoundAdapter.sol";
import { UniV3PosStateFingerpringComputer }  from "src/state-fingerprint-computer/UniV3PosStateFingerpringComputer.sol";
import "src/PWNErrors.sol";

import { T20 } from "test/helper/T20.sol";
import {
    DeploymentTest,
    PWNSimpleLoan,
    PWNSimpleLoanSimpleProposal
} from "test/DeploymentTest.t.sol";


abstract contract UseCasesTest is DeploymentTest {

    // Token mainnet addresses
    address ZRX = 0xE41d2489571d322189246DaFA5ebDe1F4699F498; // no revert on failed
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // no revert on fallback
    address CULT = 0xf0f9D895aCa5c8678f706FB8216fa22957685A13; // tax token
    address CK = 0x06012c8cf97BEaD5deAe237070F9587f8E7A266d; // CryptoKitties
    address USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // no bool return on transfer(From)
    address BNB = 0xB8c77482e45F1F44dE1745F52C74426C631bDD52; // bool return only on transfer
    address DOODLE = 0x8a90CAb2b38dba80c64b7734e58Ee1dB38B8992e;

    T20 credit;
    address lender = makeAddr("lender");
    address borrower = makeAddr("borrower");

    PWNSimpleLoanSimpleProposal.Proposal proposal;


    function setUp() public override {
        vm.createSelectFork("mainnet");

        super.setUp();

        credit = new T20();
        credit.mint(lender, 100e18);
        credit.mint(borrower, 100e18);

        vm.prank(lender);
        credit.approve(address(deployment.simpleLoan), type(uint256).max);

        vm.prank(borrower);
        credit.approve(address(deployment.simpleLoan), type(uint256).max);

        proposal = PWNSimpleLoanSimpleProposal.Proposal({
            collateralCategory: MultiToken.Category.ERC20,
            collateralAddress: address(credit),
            collateralId: 0,
            collateralAmount: 10e18,
            checkCollateralStateFingerprint: false,
            collateralStateFingerprint: bytes32(0),
            creditAddress: address(credit),
            creditAmount: 1e18,
            availableCreditLimit: 0,
            fixedInterestAmount: 0,
            accruingInterestAPR: 0,
            duration: 1 days,
            expiration: uint40(block.timestamp + 7 days),
            allowedAcceptor: address(0),
            proposer: lender,
            proposerSpecHash: deployment.simpleLoan.getLenderSpecHash(PWNSimpleLoan.LenderSpec(lender)),
            isOffer: true,
            refinancingLoanId: 0,
            nonceSpace: 0,
            nonce: 0,
            loanContract: address(deployment.simpleLoan)
        });
    }


    function _createLoan() internal returns (uint256) {
        return _createLoanRevertWith("");
    }

    function _createLoanRevertWith(bytes memory revertData) internal returns (uint256) {
        // Make proposal
        vm.prank(lender);
        deployment.simpleLoanSimpleProposal.makeProposal(proposal);

        bytes memory proposalData = deployment.simpleLoanSimpleProposal.encodeProposalData(proposal);

        // Create a loan
        if (revertData.length > 0) {
            vm.expectRevert(revertData);
        }
        vm.prank(borrower);
        return deployment.simpleLoan.createLOAN({
            proposalSpec: PWNSimpleLoan.ProposalSpec({
                proposalContract: address(deployment.simpleLoanSimpleProposal),
                proposalData: proposalData,
                proposalInclusionProof: new bytes32[](0),
                signature: ""
            }),
            lenderSpec: PWNSimpleLoan.LenderSpec({
                sourceOfFunds: lender
            }),
            callerSpec: PWNSimpleLoan.CallerSpec({
                refinancingLoanId: 0,
                revokeNonce: false,
                nonce: 0,
                permitData: ""
            }),
            extra: ""
        });
    }

}


contract InvalidCollateralAssetCategoryTest is UseCasesTest {

    // “No Revert on Failure” tokens can be used to steal from lender
    function testUseCase_shouldFail_when20CollateralPassedWith721Category() external {
        // Borrower has not ZRX tokens

        // Define proposal
        proposal.collateralCategory = MultiToken.Category.ERC721;
        proposal.collateralAddress = ZRX;
        proposal.collateralId = 10e18;
        proposal.collateralAmount = 0;

        // Create loan
        _createLoanRevertWith(abi.encodeWithSelector(InvalidMultiTokenAsset.selector, 1, ZRX, 10e18, 0));
    }

    // Borrower can steal lender’s assets by using WETH as collateral
    function testUseCase_shouldFail_when20CollateralPassedWith1155Category() external {
        // Borrower has not WETH tokens

        // Define proposal
        proposal.collateralCategory = MultiToken.Category.ERC1155;
        proposal.collateralAddress = WETH;
        proposal.collateralId = 0;
        proposal.collateralAmount = 10e18;

        // Create loan
        _createLoanRevertWith(abi.encodeWithSelector(InvalidMultiTokenAsset.selector, 2, WETH, 0, 10e18));
    }

    // CryptoKitties token is locked when using it as ERC721 type collateral
    function testUseCase_shouldFail_whenCryptoKittiesCollateralPassedWith721Category() external {
        uint256 ckId = 42;

        // Mock CK
        address originalCkOwner = ICryptoKitties(CK).ownerOf(ckId);
        vm.prank(originalCkOwner);
        ICryptoKitties(CK).transfer(borrower, ckId);

        vm.prank(borrower);
        ICryptoKitties(CK).approve(address(deployment.simpleLoan), ckId);

        // Define proposal
        proposal.collateralCategory = MultiToken.Category.ERC721;
        proposal.collateralAddress = CK;
        proposal.collateralId = ckId;
        proposal.collateralAmount = 0;

        // Create loan
        _createLoanRevertWith(abi.encodeWithSelector(InvalidMultiTokenAsset.selector, 1, CK, ckId, 0));
    }

}


contract InvalidCreditTest is UseCasesTest {

    function testUseCase_shouldFail_whenUsingERC721AsCredit() external {
        uint256 doodleId = 42;

        // Mock DOODLE
        address originalDoodleOwner = IERC721(DOODLE).ownerOf(doodleId);
        vm.prank(originalDoodleOwner);
        IERC721(DOODLE).transferFrom(originalDoodleOwner, lender, doodleId);

        vm.prank(lender);
        IERC721(DOODLE).approve(address(deployment.simpleLoan), doodleId);

        // Define proposal
        proposal.creditAddress = DOODLE;
        proposal.creditAmount = doodleId;

        // Create loan
        _createLoanRevertWith(abi.encodeWithSelector(InvalidMultiTokenAsset.selector, 0, DOODLE, 0, doodleId));
    }

    function testUseCase_shouldFail_whenUsingCryptoKittiesAsCredit() external {
        uint256 ckId = 42;

        // Mock CK
        address originalCkOwner = ICryptoKitties(CK).ownerOf(ckId);
        vm.prank(originalCkOwner);
        ICryptoKitties(CK).transfer(lender, ckId);

        vm.prank(lender);
        ICryptoKitties(CK).approve(address(deployment.simpleLoan), ckId);

        // Define proposal
        proposal.creditAddress = CK;
        proposal.creditAmount = ckId;

        // Create loan
        _createLoanRevertWith(abi.encodeWithSelector(InvalidMultiTokenAsset.selector, 0, CK, 0, ckId));
    }

}


contract TaxTokensTest is UseCasesTest {

    // Fee-on-transfer tokens can be locked in the vault
    function testUseCase_shouldFail_whenUsingTaxTokenAsCollateral() external {
        // Transfer CULT to borrower
        vm.prank(CULT);
        T20(CULT).transfer(borrower, 20e18);

        vm.prank(borrower);
        T20(CULT).approve(address(deployment.simpleLoan), type(uint256).max);

        // Define proposal
        proposal.collateralCategory = MultiToken.Category.ERC20;
        proposal.collateralAddress = CULT;
        proposal.collateralId = 0;
        proposal.collateralAmount = 10e18;

        // Create loan
        _createLoanRevertWith(abi.encodeWithSelector(IncompleteTransfer.selector));
    }

    // Fee-on-transfer tokens can be locked in the vault
    function testUseCase_shouldFail_whenUsingTaxTokenAsCredit() external {
        // Transfer CULT to lender
        vm.prank(CULT);
        T20(CULT).transfer(lender, 20e18);

        vm.prank(lender);
        T20(CULT).approve(address(deployment.simpleLoan), type(uint256).max);

        // Define proposal
        proposal.creditAddress = CULT;
        proposal.creditAmount = 10e18;

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
        (success, ) = USDT.call(abi.encodeWithSignature("approve(address,uint256)", address(deployment.simpleLoan), type(uint256).max));
        require(success);

        // Define proposal
        proposal.collateralCategory = MultiToken.Category.ERC20;
        proposal.collateralAddress = USDT;
        proposal.collateralId = 0;
        proposal.collateralAmount = 10e6; // USDT has 6 decimals

        // Check balance
        assertEq(T20(USDT).balanceOf(borrower), 10e6);
        assertEq(T20(USDT).balanceOf(address(deployment.simpleLoan)), 0);

        // Create loan
        uint256 loanId = _createLoan();

        // Check balance
        assertEq(T20(USDT).balanceOf(borrower), 0);
        assertEq(T20(USDT).balanceOf(address(deployment.simpleLoan)), 10e6);

        // Repay loan
        vm.prank(borrower);
        deployment.simpleLoan.repayLOAN({
            loanId: loanId,
            permitData: ""
        });

        // Check balance
        assertEq(T20(USDT).balanceOf(borrower), 10e6);
        assertEq(T20(USDT).balanceOf(address(deployment.simpleLoan)), 0);
    }

    function testUseCase_shouldPass_when20TokenTransferNotReturnsBool_whenUsedAsCredit() external {
        address TetherTreasury = 0x5754284f345afc66a98fbB0a0Afe71e0F007B949;

        // Transfer USDT to lender
        bool success;
        vm.prank(TetherTreasury);
        (success, ) = USDT.call(abi.encodeWithSignature("transfer(address,uint256)", lender, 10e6));
        require(success);

        vm.prank(lender);
        (success, ) = USDT.call(abi.encodeWithSignature("approve(address,uint256)", address(deployment.simpleLoan), type(uint256).max));
        require(success);

        vm.prank(borrower);
        (success, ) = USDT.call(abi.encodeWithSignature("approve(address,uint256)", address(deployment.simpleLoan), type(uint256).max));
        require(success);

        // Define proposal
        proposal.creditAddress = USDT;
        proposal.creditAmount = 10e6; // USDT has 6 decimals

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
        deployment.simpleLoan.repayLOAN({
            loanId: loanId,
            permitData: ""
        });

        // Check balance - repaid directly to lender
        assertEq(T20(USDT).balanceOf(lender), 10e6);
        assertEq(T20(USDT).balanceOf(address(deployment.simpleLoan)), 0);
    }

}


contract CategoryRegistryForIncompleteERCTokensTest is UseCasesTest {

    function test_shouldPass_whenInvalidERC165Support() external {
        address catCoinBank = 0xdeDf88899D7c9025F19C6c9F188DEb98D49CD760;

        // Register category
        vm.prank(deployment.protocolSafe);
        deployment.categoryRegistry.registerCategoryValue(catCoinBank, uint8(MultiToken.Category.ERC721));

        // Prepare collateral
        uint256 collId = 2;
        address originalOwner = IERC721(catCoinBank).ownerOf(collId);
        vm.prank(originalOwner);
        IERC721(catCoinBank).transferFrom(originalOwner, borrower, collId);

        vm.prank(borrower);
        IERC721(catCoinBank).setApprovalForAll(address(deployment.simpleLoan), true);

        // Update proposal
        proposal.collateralCategory = MultiToken.Category.ERC721;
        proposal.collateralAddress = catCoinBank;
        proposal.collateralId = collId;
        proposal.collateralAmount = 0;

        // Create loan
        _createLoan();

        // Check balance
        assertEq(IERC721(catCoinBank).ownerOf(collId), address(deployment.simpleLoan));
    }

}


interface UniV3PostLike {
    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    /// @notice Decreases the amount of liquidity in a position and accounts it to the position
    /// @param params tokenId The ID of the token for which liquidity is being decreased,
    /// amount The amount by which liquidity will be decreased,
    /// amount0Min The minimum amount of token0 that should be accounted for the burned liquidity,
    /// amount1Min The minimum amount of token1 that should be accounted for the burned liquidity,
    /// deadline The time by which the transaction must be included to effect the change
    /// @return amount0 The amount of token0 accounted to the position's tokens owed
    /// @return amount1 The amount of token1 accounted to the position's tokens owed
    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);
}

contract StateFingerprintTest is UseCasesTest {

    address constant UNI_V3_POS = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    function test_shouldFail_whenUniV3PosStateChanges() external {
        UniV3PosStateFingerpringComputer computer = new UniV3PosStateFingerpringComputer(UNI_V3_POS);
        deployment.config.registerStateFingerprintComputer(UNI_V3_POS, address(computer));

        uint256 collId = 1;
        address originalOwner = IERC721(UNI_V3_POS).ownerOf(collId);
        vm.prank(originalOwner);
        IERC721(UNI_V3_POS).transferFrom(originalOwner, borrower, collId);

        vm.prank(borrower);
        IERC721(UNI_V3_POS).setApprovalForAll(address(deployment.simpleLoan), true);

        // Define proposal
        proposal.collateralCategory = MultiToken.Category.ERC721;
        proposal.collateralAddress = UNI_V3_POS;
        proposal.collateralId = collId;
        proposal.collateralAmount = 0;
        proposal.checkCollateralStateFingerprint = true;
        proposal.collateralStateFingerprint = computer.computeStateFingerprint(UNI_V3_POS, collId);

        vm.prank(borrower);
        UniV3PostLike(UNI_V3_POS).decreaseLiquidity(UniV3PostLike.DecreaseLiquidityParams({
            tokenId: collId,
            liquidity: 100,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp + 1 days
        }));
        bytes32 currentFingerprint = computer.computeStateFingerprint(UNI_V3_POS, collId);

        assertNotEq(currentFingerprint, proposal.collateralStateFingerprint);

        // Create loan
        _createLoanRevertWith(
            abi.encodeWithSelector(InvalidCollateralStateFingerprint.selector, currentFingerprint, proposal.collateralStateFingerprint)
        );
    }

    function test_shouldPass_whenUniV3PosStateDoesNotChange() external {
        UniV3PosStateFingerpringComputer computer = new UniV3PosStateFingerpringComputer(UNI_V3_POS);
        deployment.config.registerStateFingerprintComputer(UNI_V3_POS, address(computer));

        uint256 collId = 1;
        address originalOwner = IERC721(UNI_V3_POS).ownerOf(collId);
        vm.prank(originalOwner);
        IERC721(UNI_V3_POS).transferFrom(originalOwner, borrower, collId);

        vm.prank(borrower);
        IERC721(UNI_V3_POS).setApprovalForAll(address(deployment.simpleLoan), true);

        // Define proposal
        proposal.collateralCategory = MultiToken.Category.ERC721;
        proposal.collateralAddress = UNI_V3_POS;
        proposal.collateralId = collId;
        proposal.collateralAmount = 0;
        proposal.checkCollateralStateFingerprint = true;
        proposal.collateralStateFingerprint = computer.computeStateFingerprint(UNI_V3_POS, collId);

        // Create loan
        _createLoan();

        // Check balance
        assertEq(IERC721(UNI_V3_POS).ownerOf(collId), address(deployment.simpleLoan));
    }

}


interface ICometLike {
    function allow(address manager, bool isAllowed) external;
    function supply(address asset, uint amount) external;
    function withdraw(address asset, uint amount) external;
}

contract PoolAdapterTest is UseCasesTest {

    address constant CMP_USDC = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    function test_shouldWithdrawAndRepayToPool() external {
        CompoundAdapter adapter = new CompoundAdapter(address(deployment.hub));
        deployment.config.registerPoolAdapter(CMP_USDC, address(adapter));

        vm.prank(0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503);
        IERC20(USDC).transfer(lender, 1000e6);

        // Supply to pool 1k USDC
        vm.startPrank(lender);
        IERC20(USDC).approve(CMP_USDC, type(uint256).max);
        ICometLike(CMP_USDC).supply(USDC, 1000e6);
        ICometLike(CMP_USDC).allow(address(adapter), true);
        vm.stopPrank();

        vm.prank(borrower);
        IERC20(USDC).approve(address(deployment.simpleLoan), type(uint256).max);

        // Update lender spec
        PWNSimpleLoan.LenderSpec memory lenderSpec = PWNSimpleLoan.LenderSpec({
            sourceOfFunds: CMP_USDC
        });

        // Update proposal
        proposal.creditAddress = USDC;
        proposal.creditAmount = 100e6; // 100 USDC
        proposal.proposerSpecHash = deployment.simpleLoan.getLenderSpecHash(lenderSpec);

        assertEq(IERC20(USDC).balanceOf(lender), 0);
        assertEq(IERC20(USDC).balanceOf(borrower), 0);

        // Make proposal
        vm.prank(lender);
        deployment.simpleLoanSimpleProposal.makeProposal(proposal);

        bytes memory proposalData = deployment.simpleLoanSimpleProposal.encodeProposalData(proposal);

        // Create loan
        vm.prank(borrower);
        uint256 loanId = deployment.simpleLoan.createLOAN({
            proposalSpec: PWNSimpleLoan.ProposalSpec({
                proposalContract: address(deployment.simpleLoanSimpleProposal),
                proposalData: proposalData,
                proposalInclusionProof: new bytes32[](0),
                signature: ""
            }),
            lenderSpec: lenderSpec,
            callerSpec: PWNSimpleLoan.CallerSpec({
                refinancingLoanId: 0,
                revokeNonce: false,
                nonce: 0,
                permitData: ""
            }),
            extra: ""
        });

        // Check balance
        assertEq(IERC20(USDC).balanceOf(lender), 0);
        assertEq(IERC20(USDC).balanceOf(borrower), 100e6);

        // Move in time
        vm.warp(block.timestamp + 20 hours);

        // Repay loan
        vm.prank(borrower);
        deployment.simpleLoan.repayLOAN({
            loanId: loanId,
            permitData: ""
        });

        // LOAN token owner is original lender -> repay funds to the pool
        assertEq(IERC20(USDC).balanceOf(lender), 0);
        assertEq(IERC20(USDC).balanceOf(borrower), 0);
        vm.expectRevert("ERC721: invalid token ID");
        deployment.loanToken.ownerOf(loanId);
    }

    function test_shouldWithdrawFromPoolAndRepayToVault() external {
        CompoundAdapter adapter = new CompoundAdapter(address(deployment.hub));
        deployment.config.registerPoolAdapter(CMP_USDC, address(adapter));

        vm.prank(0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503);
        IERC20(USDC).transfer(lender, 1000e6);

        // Supply to pool 1k USDC
        vm.startPrank(lender);
        IERC20(USDC).approve(CMP_USDC, type(uint256).max);
        ICometLike(CMP_USDC).supply(USDC, 1000e6);
        ICometLike(CMP_USDC).allow(address(adapter), true);
        vm.stopPrank();

        vm.prank(borrower);
        IERC20(USDC).approve(address(deployment.simpleLoan), type(uint256).max);

        // Update lender spec
        PWNSimpleLoan.LenderSpec memory lenderSpec = PWNSimpleLoan.LenderSpec({
            sourceOfFunds: CMP_USDC
        });

        // Update proposal
        proposal.creditAddress = USDC;
        proposal.creditAmount = 100e6; // 100 USDC
        proposal.proposerSpecHash = deployment.simpleLoan.getLenderSpecHash(lenderSpec);

        assertEq(IERC20(USDC).balanceOf(lender), 0);
        assertEq(IERC20(USDC).balanceOf(borrower), 0);

        // Make proposal
        vm.prank(lender);
        deployment.simpleLoanSimpleProposal.makeProposal(proposal);

        bytes memory proposalData = deployment.simpleLoanSimpleProposal.encodeProposalData(proposal);

        // Create loan
        vm.prank(borrower);
        uint256 loanId = deployment.simpleLoan.createLOAN({
            proposalSpec: PWNSimpleLoan.ProposalSpec({
                proposalContract: address(deployment.simpleLoanSimpleProposal),
                proposalData: proposalData,
                proposalInclusionProof: new bytes32[](0),
                signature: ""
            }),
            lenderSpec: lenderSpec,
            callerSpec: PWNSimpleLoan.CallerSpec({
                refinancingLoanId: 0,
                revokeNonce: false,
                nonce: 0,
                permitData: ""
            }),
            extra: ""
        });

        // Check balance
        assertEq(IERC20(USDC).balanceOf(lender), 0);
        assertEq(IERC20(USDC).balanceOf(borrower), 100e6);

        // Move in time
        vm.warp(block.timestamp + 20 hours);

        address newLender = makeAddr("new lender");

        vm.prank(lender);
        deployment.loanToken.transferFrom(lender, newLender, loanId);

        uint256 originalBalance = IERC20(USDC).balanceOf(address(deployment.simpleLoan));

        // Repay loan
        vm.prank(borrower);
        deployment.simpleLoan.repayLOAN({
            loanId: loanId,
            permitData: ""
        });

        // LOAN token owner is not original lender -> repay funds to the Vault
        assertEq(IERC20(USDC).balanceOf(address(deployment.simpleLoan)), originalBalance + 100e6);
        assertEq(deployment.loanToken.ownerOf(loanId), newLender);
    }

}
