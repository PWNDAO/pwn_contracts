// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken, IERC20 } from "MultiToken/MultiToken.sol";

import {
    IChainlinkAggregatorLike,
    IChainlinkFeedRegistryLike,
    ChainlinkDenominations
} from "src/loan/terms/simple/proposal/PWNSimpleLoanElasticChainlinkProposal.sol";

import {
    IPWNDeployer,
    PWNHub,
    PWNHubTags,
    DeploymentTest,
    PWNSimpleLoan,
    PWNSimpleLoanElasticChainlinkProposal
} from "test/DeploymentTest.t.sol";


contract PWNSimpleLoanElasticChainlinkProposalForkTest is DeploymentTest {

    function setUp() public override virtual {
        vm.createSelectFork("mainnet");

        super.setUp();
    }


    function test_WETH_USDT() external {
        IERC20 WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        IERC20 USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
        address ETH_USD_Feed = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
        address USDT_USD_Feed = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;

        deal(lender, 10000 ether);
        deal(borrower, 10000 ether);
        deal(address(WETH), borrower, 1e18, false);
        deal(address(USDT), lender, 1000e6, false);

        // Register USDT/USD & ETH/USD feed
        vm.startPrank(deployment.protocolTimelock);
        deployment.chainlinkFeedRegistry.proposeFeed(address(USDT), ChainlinkDenominations.USD, USDT_USD_Feed);
        deployment.chainlinkFeedRegistry.confirmFeed(address(USDT), ChainlinkDenominations.USD, USDT_USD_Feed);
        deployment.chainlinkFeedRegistry.proposeFeed(ChainlinkDenominations.ETH, ChainlinkDenominations.USD, ETH_USD_Feed);
        deployment.chainlinkFeedRegistry.confirmFeed(ChainlinkDenominations.ETH, ChainlinkDenominations.USD, ETH_USD_Feed);
        vm.stopPrank();

        PWNSimpleLoanElasticChainlinkProposal.Proposal memory proposal = PWNSimpleLoanElasticChainlinkProposal.Proposal({
            collateralCategory: MultiToken.Category.ERC20,
            collateralAddress: address(WETH),
            collateralId: 0,
            checkCollateralStateFingerprint: false,
            collateralStateFingerprint: bytes32(0),
            creditAddress: address(USDT),
            loanToValue: 8000,
            minCreditAmount: 1,
            availableCreditLimit: 1000e6,
            utilizedCreditId: 0,
            fixedInterestAmount: 0,
            accruingInterestAPR: 0,
            durationOrDate: 1 days,
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

        PWNSimpleLoanElasticChainlinkProposal.ProposalValues memory values = PWNSimpleLoanElasticChainlinkProposal.ProposalValues({
            creditAmount: 500e6
        });

        vm.prank(borrower);
        WETH.approve(address(deployment.simpleLoan), type(uint256).max);

        // USDT doesn't return bool and IERC20 interface call fails
        vm.prank(lender);
        (bool success, ) = address(USDT).call(abi.encodeWithSignature("approve(address,uint256)", address(deployment.simpleLoan), type(uint256).max));
        require(success);

        bytes memory signature = _sign(lenderPK, deployment.simpleLoanElasticChainlinkProposal.getProposalHash(proposal));
        bytes memory proposalData = deployment.simpleLoanElasticChainlinkProposal.encodeProposalData(proposal, values);

        vm.prank(borrower);
        deployment.simpleLoan.createLOAN({
            proposalSpec: PWNSimpleLoan.ProposalSpec({
                proposalContract: address(deployment.simpleLoanElasticChainlinkProposal),
                proposalData: proposalData,
                proposalInclusionProof: new bytes32[](0),
                signature: signature
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


        (, int256 usdtPrice,,,) = IChainlinkAggregatorLike(USDT_USD_Feed).latestRoundData();
        (, int256 ethPrice,,,) = IChainlinkAggregatorLike(ETH_USD_Feed).latestRoundData();
        // 625e18 = magic value when using credit valued at 500 USD with 80% LTV
        uint256 expectedCollAmount = 625e18 * uint256(usdtPrice) / uint256(ethPrice);

        assertEq(USDT.balanceOf(lender), 500e6);
        assertEq(USDT.balanceOf(borrower), 500e6);
        assertEq(WETH.balanceOf(borrower), 1e18 - expectedCollAmount);
        assertEq(WETH.balanceOf(address(deployment.simpleLoan)), expectedCollAmount);
    }

    function test_ARB_WETH() external {
        IERC20 WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        IERC20 ARB = IERC20(0xB50721BCf8d664c30412Cfbc6cf7a15145234ad1);
        address ETH_USD_Feed = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
        address ARB_USD_Feed = 0x31697852a68433DbCc2Ff612c516d69E3D9bd08F;

        deal(lender, 10000 ether);
        deal(borrower, 10000 ether);
        deal(address(WETH), borrower, 1e18, false);
        deal(address(ARB), lender, 1000e18, false);

        // Register ARB/USD & ETH/USD feed
        vm.startPrank(deployment.protocolTimelock);
        deployment.chainlinkFeedRegistry.proposeFeed(address(ARB), ChainlinkDenominations.USD, ARB_USD_Feed);
        deployment.chainlinkFeedRegistry.confirmFeed(address(ARB), ChainlinkDenominations.USD, ARB_USD_Feed);
        deployment.chainlinkFeedRegistry.proposeFeed(ChainlinkDenominations.ETH, ChainlinkDenominations.USD, ETH_USD_Feed);
        deployment.chainlinkFeedRegistry.confirmFeed(ChainlinkDenominations.ETH, ChainlinkDenominations.USD, ETH_USD_Feed);
        vm.stopPrank();

        PWNSimpleLoanElasticChainlinkProposal.Proposal memory proposal = PWNSimpleLoanElasticChainlinkProposal.Proposal({
            collateralCategory: MultiToken.Category.ERC20,
            collateralAddress: address(WETH),
            collateralId: 0,
            checkCollateralStateFingerprint: false,
            collateralStateFingerprint: bytes32(0),
            creditAddress: address(ARB),
            loanToValue: 8000,
            minCreditAmount: 1,
            availableCreditLimit: 1000e18,
            utilizedCreditId: 0,
            fixedInterestAmount: 0,
            accruingInterestAPR: 0,
            durationOrDate: 1 days,
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

        PWNSimpleLoanElasticChainlinkProposal.ProposalValues memory values = PWNSimpleLoanElasticChainlinkProposal.ProposalValues({
            creditAmount: 500e18
        });

        vm.prank(borrower);
        WETH.approve(address(deployment.simpleLoan), type(uint256).max);
        vm.prank(lender);
        ARB.approve(address(deployment.simpleLoan), type(uint256).max);

        bytes memory signature = _sign(lenderPK, deployment.simpleLoanElasticChainlinkProposal.getProposalHash(proposal));
        bytes memory proposalData = deployment.simpleLoanElasticChainlinkProposal.encodeProposalData(proposal, values);

        vm.prank(borrower);
        deployment.simpleLoan.createLOAN({
            proposalSpec: PWNSimpleLoan.ProposalSpec({
                proposalContract: address(deployment.simpleLoanElasticChainlinkProposal),
                proposalData: proposalData,
                proposalInclusionProof: new bytes32[](0),
                signature: signature
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


        (, int256 arbPrice,,,) = IChainlinkAggregatorLike(ARB_USD_Feed).latestRoundData();
        (, int256 ethPrice,,,) = IChainlinkAggregatorLike(ETH_USD_Feed).latestRoundData();
        // 625e18 = magic value when using credit valued at 500 USD with 80% LTV
        uint256 expectedCollAmount = 625e18 * uint256(arbPrice) / uint256(ethPrice);

        assertEq(ARB.balanceOf(lender), 500e18);
        assertEq(ARB.balanceOf(borrower), 500e18);
        assertEq(WETH.balanceOf(borrower), 1e18 - expectedCollAmount);
        assertEq(WETH.balanceOf(address(deployment.simpleLoan)), expectedCollAmount);
    }

    function test_USDT_ARB() external {
        IERC20 ARB = IERC20(0xB50721BCf8d664c30412Cfbc6cf7a15145234ad1);
        IERC20 USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
        address ARB_USD_Feed = 0x31697852a68433DbCc2Ff612c516d69E3D9bd08F;
        address USDT_USD_Feed = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;

        deal(lender, 10000 ether);
        deal(borrower, 10000 ether);
        deal(address(ARB), borrower, 2000e18, false);
        deal(address(USDT), lender, 1000e6, false);

        // Register ARB/USD & ETH/USD feed
        vm.startPrank(deployment.protocolTimelock);
        deployment.chainlinkFeedRegistry.proposeFeed(address(ARB), ChainlinkDenominations.USD, ARB_USD_Feed);
        deployment.chainlinkFeedRegistry.confirmFeed(address(ARB), ChainlinkDenominations.USD, ARB_USD_Feed);
        deployment.chainlinkFeedRegistry.proposeFeed(address(USDT), ChainlinkDenominations.USD, USDT_USD_Feed);
        deployment.chainlinkFeedRegistry.confirmFeed(address(USDT), ChainlinkDenominations.USD, USDT_USD_Feed);
        vm.stopPrank();

        PWNSimpleLoanElasticChainlinkProposal.Proposal memory proposal = PWNSimpleLoanElasticChainlinkProposal.Proposal({
            collateralCategory: MultiToken.Category.ERC20,
            collateralAddress: address(ARB),
            collateralId: 0,
            checkCollateralStateFingerprint: false,
            collateralStateFingerprint: bytes32(0),
            creditAddress: address(USDT),
            loanToValue: 8000,
            minCreditAmount: 1,
            availableCreditLimit: 1000e6,
            utilizedCreditId: 0,
            fixedInterestAmount: 0,
            accruingInterestAPR: 0,
            durationOrDate: 1 days,
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

        PWNSimpleLoanElasticChainlinkProposal.ProposalValues memory values = PWNSimpleLoanElasticChainlinkProposal.ProposalValues({
            creditAmount: 500e6
        });

        vm.prank(borrower);
        ARB.approve(address(deployment.simpleLoan), type(uint256).max);

        // USDT doesn't return bool and IERC20 interface call fails
        vm.prank(lender);
        (bool success, ) = address(USDT).call(abi.encodeWithSignature("approve(address,uint256)", address(deployment.simpleLoan), type(uint256).max));
        require(success);

        bytes memory signature = _sign(lenderPK, deployment.simpleLoanElasticChainlinkProposal.getProposalHash(proposal));
        bytes memory proposalData = deployment.simpleLoanElasticChainlinkProposal.encodeProposalData(proposal, values);

        vm.prank(borrower);
        deployment.simpleLoan.createLOAN({
            proposalSpec: PWNSimpleLoan.ProposalSpec({
                proposalContract: address(deployment.simpleLoanElasticChainlinkProposal),
                proposalData: proposalData,
                proposalInclusionProof: new bytes32[](0),
                signature: signature
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


        (, int256 usdtPrice,,,) = IChainlinkAggregatorLike(USDT_USD_Feed).latestRoundData();
        (, int256 arbPrice,,,) = IChainlinkAggregatorLike(ARB_USD_Feed).latestRoundData();
        // 625e18 = magic value when using credit valued at 500 USD with 80% LTV
        uint256 expectedCollAmount = 625e18 * uint256(usdtPrice) / uint256(arbPrice);

        assertEq(USDT.balanceOf(lender), 500e6);
        assertEq(USDT.balanceOf(borrower), 500e6);
        assertEq(ARB.balanceOf(borrower), 2000e18 - expectedCollAmount);
        assertEq(ARB.balanceOf(address(deployment.simpleLoan)), expectedCollAmount);
    }

}
