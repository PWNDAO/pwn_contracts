// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { console2 } from "forge-std/Test.sol";

import { MultiToken, IERC20, IERC721 } from "MultiToken/MultiToken.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {
    PWNSimpleLoanUniswapV3LPProposal,
    PWNSimpleLoan,
    INonfungiblePositionManager,
    IChainlinkAggregatorLike
} from "src/loan/terms/simple/proposal/PWNSimpleLoanUniswapV3LPProposal.sol";

import { ChainlinkDenominations } from "test/helper/ChainlinkDenominations.sol";
import { DeploymentTest } from "test/DeploymentTest.t.sol";


interface IUSDT {
    function approve(address spender, uint256 amount) external;
}

contract PWNSimpleLoanUniswapV3LPProposalForkTest is DeploymentTest {
    IERC20 WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 WBTC = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    IERC20 USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 DAI  = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 UNI  = IERC20(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984);

    PWNSimpleLoanUniswapV3LPProposal.Proposal proposal;
    PWNSimpleLoanUniswapV3LPProposal.ProposalValues proposalValues;

    function setUp() public override virtual {
        vm.createSelectFork("mainnet");

        super.setUp();

        deal(lender, 10000 ether);
        deal(address(USDT), lender, 1_000_000e6, false);
        deal(address(DAI), lender, 1_000_000e6, false);

        vm.startPrank(lender);
        IUSDT(address(USDT)).approve(address(deployment.simpleLoan), type(uint256).max);
        DAI.approve(address(deployment.simpleLoan), type(uint256).max);
        vm.stopPrank();

        vm.prank(borrower);
        IERC721(externalAddrs.uniswapV3NFTPositionManager).setApprovalForAll(address(deployment.simpleLoan), true);

        _registerFeed(address(USDC), ChainlinkDenominations.USD, 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);
        _registerFeed(address(USDT), ChainlinkDenominations.USD, 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D);
        _registerFeed(address(UNI), ChainlinkDenominations.USD, 0x553303d460EE0afB37EdFf9bE42922D8FF63220e);
    }

    function _transferLPOwnership(uint256 tokenId) internal {
        address owner = IERC721(externalAddrs.uniswapV3NFTPositionManager).ownerOf(tokenId);
        vm.prank(owner);
        IERC721(externalAddrs.uniswapV3NFTPositionManager).transferFrom(owner, borrower, tokenId);
    }

    function _registerFeed(address base, address quote, address feed) internal {
        try deployment.chainlinkFeedRegistry.getFeed(base, quote) returns (IChainlinkAggregatorLike) {
            return;
        } catch {
            vm.startPrank(deployment.protocolTimelock);
            deployment.chainlinkFeedRegistry.proposeFeed(base, quote, feed);
            deployment.chainlinkFeedRegistry.confirmFeed(base, quote, feed);
            vm.stopPrank();
        }
    }

    function _test(
        uint256 tokenId,
        uint256 tokenAIndex,
        uint256 tokenBIndex
    ) internal {
        _test(tokenId, tokenAIndex, tokenBIndex, "");
    }

    function _test(
        uint256 tokenId,
        uint256 tokenAIndex,
        uint256 tokenBIndex,
        bytes memory err
    ) internal {
        if (tokenId != 851566) _transferLPOwnership(tokenId); // use token id 851566 to test call for non-existent token

        proposal = PWNSimpleLoanUniswapV3LPProposal.Proposal({
            tokenAAllowlist: new address[](0),
            tokenBAllowlist: new address[](0),
            creditAddress: address(USDT),
            feedIntermediaryDenominations: new address[](0),
            feedInvertFlags: new bool[](0),
            loanToValue: 7500,
            minCreditAmount: 1,
            availableCreditLimit: 0,
            utilizedCreditId: 0,
            fixedInterestAmount: 0,
            accruingInterestAPR: 0,
            durationOrDate: 1 days,
            expiration: uint40(block.timestamp + 7 days),
            acceptorController: address(0),
            acceptorControllerData: "",
            proposer: lender,
            proposerSpecHash: deployment.simpleLoan.getLenderSpecHash(PWNSimpleLoan.LenderSpec(lender)),
            isOffer: true,
            refinancingLoanId: 0,
            nonceSpace: 0,
            nonce: 0,
            loanContract: address(deployment.simpleLoan)
        });
        proposal.tokenAAllowlist.push(address(DAI));
        proposal.tokenAAllowlist.push(address(USDC));
        proposal.tokenAAllowlist.push(address(USDT));
        proposal.tokenAAllowlist.push(address(UNI));
        proposal.tokenBAllowlist.push(address(WBTC));
        proposal.tokenBAllowlist.push(address(WETH));
        proposal.feedIntermediaryDenominations.push(ChainlinkDenominations.USD);
        proposal.feedInvertFlags.push(false);
        proposal.feedInvertFlags.push(true);

        vm.prank(lender);
        deployment.simpleLoanUniswapV3LPProposal.makeProposal(proposal);

        proposalValues = PWNSimpleLoanUniswapV3LPProposal.ProposalValues({
            collateralId: tokenId,
            tokenAIndex: tokenAIndex,
            tokenBIndex: tokenBIndex,
            acceptorControllerData: ""
        });

        bytes memory proposalData = deployment.simpleLoanUniswapV3LPProposal.encodeProposalData(proposal, proposalValues);

        if (err.length > 0) { vm.expectRevert(err); }
        vm.prank(borrower);
        deployment.simpleLoan.createLOAN({
            proposalSpec: PWNSimpleLoan.ProposalSpec({
                proposalContract: address(deployment.simpleLoanUniswapV3LPProposal),
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
                nonce: 0
            }),
            extra: ""
        });

        console2.log(USDT.balanceOf(borrower));
    }


    function test_shouldFail_whenInvalidId() external {
        // https://app.uniswap.org/positions/v3/ethereum/3
        // usdc/weth (closed)
        _test(3, 1, 1, abi.encodeWithSelector(PWNSimpleLoanUniswapV3LPProposal.InsufficientCreditAmount.selector, 0, 1));
    }

    function test_shouldFail_whenPairNotAllowlisted() external {
        // https://app.uniswap.org/positions/v3/ethereum/951568
        // plume/usdc
        _test(951568, 1, 0, abi.encodeWithSelector(PWNSimpleLoanUniswapV3LPProposal.InvalidLPTokenPair.selector));
    }

    function test_sanity_WETH_USDT() external {
        // https://app.uniswap.org/positions/v3/ethereum/951577
        _test(951577, 2, 1); // weth/usdt
    }

    function test_sanity_USDC_WETH() external {
        // https://app.uniswap.org/positions/v3/ethereum/951572
        _test(951572, 1, 1); // usdc/weth
    }

    function test_sanity_UNI_WETH_inRage() external {
        // https://app.uniswap.org/positions/v3/ethereum/951567
        _test(951567, 3, 1); // uni/weth
    }

    function test_sanity_UNI_WETH_outOfRange() external {
        // https://app.uniswap.org/positions/v3/ethereum/1
        _test(1, 3, 1); // uni/weth
    }

}
