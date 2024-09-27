// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { PWNHubTags } from "pwn/hub/PWNHubTags.sol";
import {
    PWNSimpleLoanElasticChainlinkProposal,
    PWNSimpleLoanProposal,
    PWNSimpleLoan,
    IChainlinkAggregatorLike,
    IChainlinkFeedRegistryLike,
    ChainlinkDenominations
} from "pwn/loan/terms/simple/proposal/PWNSimpleLoanElasticChainlinkProposal.sol";

import { PWNSimpleLoanElasticChainlinkProposalHarness } from "test/harness/PWNSimpleLoanElasticChainlinkProposalHarness.sol";
import {
    MultiToken,
    Math,
    PWNSimpleLoanProposalTest,
    PWNSimpleLoanProposal_AcceptProposal_Test
} from "test/unit/PWNSimpleLoanProposal.t.sol";


abstract contract PWNSimpleLoanElasticChainlinkProposalTest is PWNSimpleLoanProposalTest {

    PWNSimpleLoanElasticChainlinkProposalHarness proposalContract;
    PWNSimpleLoanElasticChainlinkProposal.Proposal proposal;
    PWNSimpleLoanElasticChainlinkProposal.ProposalValues proposalValues;

    address feedRegistry = makeAddr("feedRegistry");
    address generalAggregator = makeAddr("generalAggregator");
    address credAggregator = makeAddr("credAggregator");
    address collAggregator = makeAddr("collAggregator");
    address weth = makeAddr("weth");
    address l2SequencerUptimeFeed = makeAddr("l2SequencerUptimeFeed");

    event ProposalMade(bytes32 indexed proposalHash, address indexed proposer, PWNSimpleLoanElasticChainlinkProposal.Proposal proposal);

    function setUp() virtual public override {
        super.setUp();

        vm.etch(token, "bytes");

        proposalContract = new PWNSimpleLoanElasticChainlinkProposalHarness(hub, revokedNonce, config, utilizedCredit, feedRegistry, address(0), weth);
        proposalContractAddr = PWNSimpleLoanProposal(proposalContract);

        proposal = PWNSimpleLoanElasticChainlinkProposal.Proposal({
            collateralCategory: MultiToken.Category.ERC1155,
            collateralAddress: token,
            collateralId: 0,
            checkCollateralStateFingerprint: true,
            collateralStateFingerprint: keccak256("some state fingerprint"),
            creditAddress: token,
            loanToValue: 10000, // 100%
            minCreditAmount: 1,
            availableCreditLimit: 0,
            utilizedCreditId: 0,
            fixedInterestAmount: 1,
            accruingInterestAPR: 0,
            durationOrDate: 1 days,
            expiration: 60303,
            allowedAcceptor: address(0),
            proposer: proposer,
            proposerSpecHash: keccak256("proposer spec"),
            isOffer: true,
            refinancingLoanId: 0,
            nonceSpace: 1,
            nonce: uint256(keccak256("nonce_1")),
            loanContract: activeLoanContract
        });

        proposalValues = PWNSimpleLoanElasticChainlinkProposal.ProposalValues({
            creditAmount: 1000
        });

        _mockFeed(generalAggregator);
        _mockLastRoundData(generalAggregator, 1e18, 1);
        _mockFeedDecimals(generalAggregator, 18);
        _mockSequencerUptimeFeed(true, block.timestamp - 1);
    }


    function _proposalHash(PWNSimpleLoanElasticChainlinkProposal.Proposal memory _proposal) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            "\x19\x01",
            keccak256(abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("PWNSimpleLoanElasticChainlinkProposal"),
                keccak256("1.0"),
                block.chainid,
                proposalContractAddr
            )),
            keccak256(abi.encodePacked(
                keccak256("Proposal(uint8 collateralCategory,address collateralAddress,uint256 collateralId,bool checkCollateralStateFingerprint,bytes32 collateralStateFingerprint,address creditAddress,uint256 loanToValue,uint256 minCreditAmount,uint256 availableCreditLimit,bytes32 utilizedCreditId,uint256 fixedInterestAmount,uint40 accruingInterestAPR,uint32 durationOrDate,uint40 expiration,address allowedAcceptor,address proposer,bytes32 proposerSpecHash,bool isOffer,uint256 refinancingLoanId,uint256 nonceSpace,uint256 nonce,address loanContract)"),
                abi.encode(_proposal)
            ))
        ));
    }

    function _updateProposal(CommonParams memory _params) internal {
        proposal.collateralAddress = _params.collateralAddress;
        proposal.collateralId = _params.collateralId;
        proposal.checkCollateralStateFingerprint = _params.checkCollateralStateFingerprint;
        proposal.collateralStateFingerprint = _params.collateralStateFingerprint;
        proposal.availableCreditLimit = _params.availableCreditLimit;
        proposal.utilizedCreditId = _params.utilizedCreditId;
        proposal.durationOrDate = _params.durationOrDate;
        proposal.expiration = _params.expiration;
        proposal.allowedAcceptor = _params.allowedAcceptor;
        proposal.proposer = _params.proposer;
        proposal.isOffer = _params.isOffer;
        proposal.refinancingLoanId = _params.refinancingLoanId;
        proposal.nonceSpace = _params.nonceSpace;
        proposal.nonce = _params.nonce;
        proposal.loanContract = _params.loanContract;

        proposalValues.creditAmount = _params.creditAmount;

        vm.etch(proposal.collateralAddress, "bytes");
    }


    function _callAcceptProposalWith(Params memory _params) internal override returns (bytes32, PWNSimpleLoan.Terms memory) {
        _mockLastRoundData(generalAggregator, 1e18, block.timestamp); // To avoid "ChainlinkFeedPriceTooOld" error

        _updateProposal(_params.common);
        return proposalContract.acceptProposal({
            acceptor: _params.acceptor,
            refinancingLoanId: _params.refinancingLoanId,
            proposalData: abi.encode(proposal, proposalValues),
            proposalInclusionProof: _params.proposalInclusionProof,
            signature: _params.signature
        });
    }

    function _getProposalHashWith(Params memory _params) internal override returns (bytes32) {
        _updateProposal(_params.common);
        return _proposalHash(proposal);
    }

    function _mockFeed(address aggregator) internal {
        vm.mockCall(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector),
            abi.encode(aggregator)
        );
    }

    function _mockFeed(address aggregator, address base, address quote) internal {
        vm.mockCall(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, base, quote),
            abi.encode(aggregator)
        );
    }

    function _mockLastRoundData(address aggregator, int256 answer, uint256 updatedAt) internal {
        vm.mockCall(
            aggregator,
            abi.encodeWithSelector(IChainlinkAggregatorLike.latestRoundData.selector),
            abi.encode(0, answer, 0, updatedAt, 0)
        );
    }

    function _mockFeedDecimals(address aggregator, uint8 decimals) internal {
        vm.mockCall(
            aggregator,
            abi.encodeWithSelector(IChainlinkAggregatorLike.decimals.selector),
            abi.encode(decimals)
        );
    }

    function _mockSequencerUptimeFeed(bool isUp, uint256 startedAt) internal {
        vm.mockCall(
            l2SequencerUptimeFeed,
            abi.encodeWithSelector(IChainlinkAggregatorLike.latestRoundData.selector),
            abi.encode(0, isUp ? 0 : 1, startedAt, 0, 0)
        );
    }

    function _mockAssetDecimals(address asset, uint8 decimals) internal {
        vm.mockCall(asset, abi.encodeWithSignature("decimals()"), abi.encode(decimals));
    }

}


/*----------------------------------------------------------*|
|*  # REVOKE NONCE                                          *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanElasticChainlinkProposal_RevokeNonce_Test is PWNSimpleLoanElasticChainlinkProposalTest {

    function testFuzz_shouldCallRevokeNonce(address caller, uint256 nonceSpace, uint256 nonce) external {
        vm.expectCall(
            revokedNonce,
            abi.encodeWithSignature("revokeNonce(address,uint256,uint256)", caller, nonceSpace, nonce)
        );

        vm.prank(caller);
        proposalContract.revokeNonce(nonceSpace, nonce);
    }

}


/*----------------------------------------------------------*|
|*  # GET PROPOSAL HASH                                     *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanElasticChainlinkProposal_GetProposalHash_Test is PWNSimpleLoanElasticChainlinkProposalTest {

    function test_shouldReturnProposalHash() external {
        assertEq(_proposalHash(proposal), proposalContract.getProposalHash(proposal));
    }

}


/*----------------------------------------------------------*|
|*  # MAKE PROPOSAL                                         *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanElasticChainlinkProposal_MakeProposal_Test is PWNSimpleLoanElasticChainlinkProposalTest {

    function testFuzz_shouldFail_whenCallerIsNotProposer(address caller) external {
        vm.assume(caller != proposal.proposer);

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoanProposal.CallerIsNotStatedProposer.selector, proposal.proposer));
        vm.prank(caller);
        proposalContract.makeProposal(proposal);
    }

    function test_shouldEmit_ProposalMade() external {
        vm.expectEmit();
        emit ProposalMade(_proposalHash(proposal), proposal.proposer, proposal);

        vm.prank(proposal.proposer);
        proposalContract.makeProposal(proposal);
    }

    function test_shouldMakeProposal() external {
        vm.prank(proposal.proposer);
        proposalContract.makeProposal(proposal);

        assertTrue(proposalContract.proposalsMade(_proposalHash(proposal)));
    }

    function test_shouldReturnProposalHash() external {
        vm.prank(proposal.proposer);
        assertEq(proposalContract.makeProposal(proposal), _proposalHash(proposal));
    }

}


/*----------------------------------------------------------*|
|*  # ENCODE PROPOSAL DATA                                  *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanElasticChainlinkProposal_EncodeProposalData_Test is PWNSimpleLoanElasticChainlinkProposalTest {

    function test_shouldReturnEncodedProposalData() external {
        assertEq(
            proposalContract.encodeProposalData(proposal, proposalValues),
            abi.encode(proposal, proposalValues)
        );
    }

}


/*----------------------------------------------------------*|
|*  # DECODE PROPOSAL DATA                                  *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanElasticChainlinkProposal_DecodeProposalData_Test is PWNSimpleLoanElasticChainlinkProposalTest {

    function test_shouldReturnDecodedProposalData() external {
        (
            PWNSimpleLoanElasticChainlinkProposal.Proposal memory _proposal,
            PWNSimpleLoanElasticChainlinkProposal.ProposalValues memory _proposalValues
        ) = proposalContract.decodeProposalData(abi.encode(proposal, proposalValues));

        assertEq(uint8(_proposal.collateralCategory), uint8(proposal.collateralCategory));
        assertEq(_proposal.collateralAddress, proposal.collateralAddress);
        assertEq(_proposal.collateralId, proposal.collateralId);
        assertEq(_proposal.checkCollateralStateFingerprint, proposal.checkCollateralStateFingerprint);
        assertEq(_proposal.collateralStateFingerprint, proposal.collateralStateFingerprint);
        assertEq(_proposal.creditAddress, proposal.creditAddress);
        assertEq(_proposal.loanToValue, proposal.loanToValue);
        assertEq(_proposal.minCreditAmount, proposal.minCreditAmount);
        assertEq(_proposal.availableCreditLimit, proposal.availableCreditLimit);
        assertEq(_proposal.utilizedCreditId, proposal.utilizedCreditId);
        assertEq(_proposal.fixedInterestAmount, proposal.fixedInterestAmount);
        assertEq(_proposal.accruingInterestAPR, proposal.accruingInterestAPR);
        assertEq(_proposal.durationOrDate, proposal.durationOrDate);
        assertEq(_proposal.expiration, proposal.expiration);
        assertEq(_proposal.allowedAcceptor, proposal.allowedAcceptor);
        assertEq(_proposal.proposer, proposal.proposer);
        assertEq(_proposal.isOffer, proposal.isOffer);
        assertEq(_proposal.refinancingLoanId, proposal.refinancingLoanId);
        assertEq(_proposal.nonceSpace, proposal.nonceSpace);
        assertEq(_proposal.nonce, proposal.nonce);
        assertEq(_proposal.loanContract, proposal.loanContract);

        assertEq(_proposalValues.creditAmount, proposalValues.creditAmount);
    }

}


/*----------------------------------------------------------*|
|*  # GET COLLATERAL AMOUNT                                 *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanElasticChainlinkProposal_GetCollateralAmount_Test is PWNSimpleLoanElasticChainlinkProposalTest {

    address collAddr = makeAddr("collAddr");
    address credAddr = makeAddr("credAddr");
    uint256 credAmount = 100e8;
    uint256 loanToValue = 5000; // 50%
    uint256 L2_GRACE_PERIOD;

    function setUp() virtual override public {
        super.setUp();

        L2_GRACE_PERIOD = proposalContract.L2_GRACE_PERIOD();

        _mockAssetDecimals(collAddr, 18);
        _mockAssetDecimals(credAddr, 18);

        _mockFeed(collAggregator, collAddr, ChainlinkDenominations.USD);
        _mockFeed(collAggregator, collAddr, ChainlinkDenominations.ETH);
        _mockLastRoundData(collAggregator, 1e18, 1);
        _mockFeedDecimals(collAggregator, 18);

        _mockFeed(credAggregator, credAddr, ChainlinkDenominations.USD);
        _mockFeed(credAggregator, credAddr, ChainlinkDenominations.ETH);
        _mockLastRoundData(credAggregator, 1e18, 1);
        _mockFeedDecimals(credAggregator, 18);

        _mockFeed(generalAggregator, ChainlinkDenominations.ETH, ChainlinkDenominations.USD);
        _mockLastRoundData(generalAggregator, 1e18, 1);
        _mockFeedDecimals(generalAggregator, 18);
    }


    function test_shouldFetchSequencerUptimeFeed_whenFeedSet() external {
        vm.warp(1e9);

        proposalContract = new PWNSimpleLoanElasticChainlinkProposalHarness(hub, revokedNonce, config, utilizedCredit, feedRegistry, l2SequencerUptimeFeed, weth);
        _mockSequencerUptimeFeed(true, block.timestamp - L2_GRACE_PERIOD - 1);
        _mockLastRoundData(collAggregator, 1e18, block.timestamp);
        _mockLastRoundData(credAggregator, 1e18, block.timestamp);

        vm.expectCall(
            l2SequencerUptimeFeed,
            abi.encodeWithSelector(IChainlinkAggregatorLike.latestRoundData.selector)
        );

        proposalContract.getCollateralAmount(credAddr, credAmount, collAddr, loanToValue);
    }

    function test_shouldFail_whenL2SequencerDown_whenFeedSet() external {
        vm.warp(1e9);

        proposalContract = new PWNSimpleLoanElasticChainlinkProposalHarness(hub, revokedNonce, config, utilizedCredit, feedRegistry, l2SequencerUptimeFeed, weth);
        _mockSequencerUptimeFeed(false, block.timestamp - L2_GRACE_PERIOD - 1);

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoanElasticChainlinkProposal.L2SequencerDown.selector));
        proposalContract.getCollateralAmount(credAddr, credAmount, collAddr, loanToValue);
    }

    function testFuzz_shouldFail_whenL2SequencerUp_whenInGracePeriod_whenFeedSet(uint256 startedAt) external {
        vm.warp(1e9);
        startedAt = bound(startedAt, block.timestamp - L2_GRACE_PERIOD, block.timestamp);

        proposalContract = new PWNSimpleLoanElasticChainlinkProposalHarness(hub, revokedNonce, config, utilizedCredit, feedRegistry, l2SequencerUptimeFeed, weth);
        _mockSequencerUptimeFeed(true, startedAt);

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNSimpleLoanElasticChainlinkProposal.GracePeriodNotOver.selector,
                block.timestamp - startedAt, L2_GRACE_PERIOD
            )
        );
        proposalContract.getCollateralAmount(credAddr, credAmount, collAddr, loanToValue);
    }

    function test_shouldNotFetchSequencerUptimeFeed_whenFeedNotSet() external {
        vm.expectCall(
            l2SequencerUptimeFeed,
            abi.encodeWithSelector(IChainlinkAggregatorLike.latestRoundData.selector),
            0
        );

        proposalContract.getCollateralAmount(credAddr, credAmount, collAddr, loanToValue);
    }

    function test_shouldFetchCreditAndCollateralPrices() external {
        vm.expectCall(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, credAddr, ChainlinkDenominations.USD)
        );
        vm.expectCall(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, collAddr, ChainlinkDenominations.USD)
        );

        proposalContract.getCollateralAmount(credAddr, credAmount, collAddr, loanToValue);
    }

    function test_shouldFetchETHPriceInUSD_whenCreditPriceInUSD_whenCollateralPriceNotInUSD() external {
        vm.mockCallRevert(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, credAddr, ChainlinkDenominations.ETH),
            "whatnot"
        );
        vm.mockCallRevert(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, collAddr, ChainlinkDenominations.USD),
            "whatnot"
        );

        vm.expectCall(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, ChainlinkDenominations.ETH, ChainlinkDenominations.USD)
        );

        proposalContract.getCollateralAmount(credAddr, credAmount, collAddr, loanToValue);
    }

    function test_shouldFetchETHPriceInUSD_whenCreditPriceNotInUSD_whenCollateralPriceInUSD() external {
        vm.mockCallRevert(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, credAddr, ChainlinkDenominations.USD),
            "whatnot"
        );
        vm.mockCallRevert(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, collAddr, ChainlinkDenominations.ETH),
            "whatnot"
        );

        vm.expectCall(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, ChainlinkDenominations.ETH, ChainlinkDenominations.USD)
        );

        proposalContract.getCollateralAmount(credAddr, credAmount, collAddr, loanToValue);
    }

    function test_shouldNotFetchETHPriceInUSD_whenCreditPriceInUSD_whenCollateralPriceInUSD() external {
        vm.mockCallRevert(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, credAddr, ChainlinkDenominations.ETH),
            "whatnot"
        );
        vm.mockCallRevert(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, collAddr, ChainlinkDenominations.ETH),
            "whatnot"
        );

        vm.expectCall(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, ChainlinkDenominations.ETH, ChainlinkDenominations.USD),
            0
        );

        proposalContract.getCollateralAmount(credAddr, credAmount, collAddr, loanToValue);
    }

    function test_shouldNotFetchETHPriceInUSD_whenCreditPriceInETH_whenCollateralPriceInETH() external {
        vm.mockCallRevert(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, credAddr, ChainlinkDenominations.USD),
            "whatnot"
        );
        vm.mockCallRevert(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, collAddr, ChainlinkDenominations.USD),
            "whatnot"
        );

        vm.expectCall(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, ChainlinkDenominations.ETH, ChainlinkDenominations.USD),
            0
        );

        proposalContract.getCollateralAmount(credAddr, credAmount, collAddr, loanToValue);
    }

    function test_shouldFail_whenNoCommonDenominator() external {
        vm.mockCallRevert(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, credAddr, ChainlinkDenominations.ETH),
            "whatnot"
        );
        vm.mockCallRevert(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, collAddr, ChainlinkDenominations.USD),
            "whatnot"
        );
        vm.mockCallRevert(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, ChainlinkDenominations.ETH, ChainlinkDenominations.USD),
            "whatnot"
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNSimpleLoanElasticChainlinkProposal.ChainlinkFeedCommonDenominatorNotFound.selector, credAddr, collAddr
            )
        );
        proposalContract.getCollateralAmount(credAddr, credAmount, collAddr, loanToValue);
    }

    function test_shouldReturnCollateralAmount_whenBothPricesInUSD() external {
        _mockLastRoundData(credAggregator, 1e8, 1);
        _mockFeedDecimals(credAggregator, 8);
        _mockLastRoundData(collAggregator, 1e18, 1);
        _mockFeedDecimals(collAggregator, 18);
        assertEq(
            proposalContract.getCollateralAmount(credAddr, 9876, collAddr, 10000),
            9876
        );
        assertEq(
            proposalContract.getCollateralAmount(credAddr, 6890, collAddr, 5000),
            13780
        );
        assertEq(
            proposalContract.getCollateralAmount(credAddr, 5000, collAddr, 100),
            500000
        );

        _mockLastRoundData(credAggregator, 1e25, 1);
        _mockFeedDecimals(credAggregator, 25);
        _mockLastRoundData(collAggregator, 200e18, 1);
        _mockFeedDecimals(collAggregator, 18);
        assertEq(
            proposalContract.getCollateralAmount(credAddr, 100e18, collAddr, 10000),
            0.5e18
        );
        assertEq(
            proposalContract.getCollateralAmount(credAddr, 100e18, collAddr, 5000),
            1e18
        );
        assertEq(
            proposalContract.getCollateralAmount(credAddr, 100e18, collAddr, 100),
            50e18
        );
    }

    function test_shouldReturnCollateralAmount_whenBothPricesInETH() external {
        vm.mockCallRevert(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, credAddr, ChainlinkDenominations.USD),
            "whatnot"
        );
        vm.mockCallRevert(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, collAddr, ChainlinkDenominations.USD),
            "whatnot"
        );

        _mockLastRoundData(credAggregator, 1e8, 1);
        _mockFeedDecimals(credAggregator, 8);
        _mockLastRoundData(collAggregator, 1e18, 1);
        _mockFeedDecimals(collAggregator, 18);
        assertEq(
            proposalContract.getCollateralAmount(credAddr, 9876, collAddr, 10000),
            9876
        );
        assertEq(
            proposalContract.getCollateralAmount(credAddr, 6890, collAddr, 5000),
            13780
        );
        assertEq(
            proposalContract.getCollateralAmount(credAddr, 5000, collAddr, 100),
            500000
        );

        _mockLastRoundData(credAggregator, 1e25, 1);
        _mockFeedDecimals(credAggregator, 25);
        _mockLastRoundData(collAggregator, 200e18, 1);
        _mockFeedDecimals(collAggregator, 18);
        assertEq(
            proposalContract.getCollateralAmount(credAddr, 100e18, collAddr, 10000),
            0.5e18
        );
        assertEq(
            proposalContract.getCollateralAmount(credAddr, 100e18, collAddr, 5000),
            1e18
        );
        assertEq(
            proposalContract.getCollateralAmount(credAddr, 100e18, collAddr, 100),
            50e18
        );
    }

    function test_shouldReturnCollateralAmount_whenCreditInUSD_whenCollateralInETH() external {
        vm.mockCallRevert(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, credAddr, ChainlinkDenominations.ETH),
            "whatnot"
        );
        vm.mockCallRevert(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, collAddr, ChainlinkDenominations.USD),
            "whatnot"
        );

        _mockLastRoundData(credAggregator, 2500e2, 1);
        _mockFeedDecimals(credAggregator, 2);
        _mockLastRoundData(collAggregator, 1e18, 1);
        _mockFeedDecimals(collAggregator, 18);
        _mockLastRoundData(generalAggregator, 2500e8, 1);
        _mockFeedDecimals(generalAggregator, 8);
        assertEq(
            proposalContract.getCollateralAmount(credAddr, 9876, collAddr, 10000),
            9876
        );
        assertEq(
            proposalContract.getCollateralAmount(credAddr, 6890, collAddr, 5000),
            13780
        );
        assertEq(
            proposalContract.getCollateralAmount(credAddr, 5000, collAddr, 100),
            500000
        );

        _mockLastRoundData(credAggregator, 2500e25, 1);
        _mockFeedDecimals(credAggregator, 25);
        _mockLastRoundData(collAggregator, 200e18, 1);
        _mockFeedDecimals(collAggregator, 18);
        _mockLastRoundData(generalAggregator, 2500e8, 1);
        _mockFeedDecimals(generalAggregator, 8);
        assertEq(
            proposalContract.getCollateralAmount(credAddr, 100e18, collAddr, 10000),
            0.5e18
        );
        assertEq(
            proposalContract.getCollateralAmount(credAddr, 100e18, collAddr, 5000),
            1e18
        );
        assertEq(
            proposalContract.getCollateralAmount(credAddr, 100e18, collAddr, 100),
            50e18
        );
    }

    function test_shouldReturnCollateralAmountWithCorrectDecimals() external {
        _mockLastRoundData(credAggregator, 1e8, 1);
        _mockFeedDecimals(credAggregator, 8);
        _mockLastRoundData(collAggregator, 2500e8, 1);
        _mockFeedDecimals(collAggregator, 8);

        _mockAssetDecimals(collAddr, 18);
        _mockAssetDecimals(credAddr, 6);
        assertEq(
            proposalContract.getCollateralAmount(credAddr, 500e6, collAddr, 8000),
            0.25e18
        );

        _mockAssetDecimals(collAddr, 6);
        _mockAssetDecimals(credAddr, 18);
        assertEq(
            proposalContract.getCollateralAmount(credAddr, 500e18, collAddr, 8000),
            0.25e6
        );
    }

    function test_shouldUseZeroDecimals_whenDecimalsNotImplemented() external {
        address credAddrWithoutDecimals = makeAddr("credAddrWithoutDecimals");
        vm.etch(credAddrWithoutDecimals, "bytes");

        _mockFeed(credAggregator, credAddrWithoutDecimals, ChainlinkDenominations.USD);
        _mockLastRoundData(credAggregator, 1e8, 1);
        _mockFeedDecimals(credAggregator, 8);
        _mockLastRoundData(collAggregator, 2500e8, 1);
        _mockFeedDecimals(collAggregator, 8);

        _mockAssetDecimals(collAddr, 18);
        assertEq(
            proposalContract.getCollateralAmount(credAddrWithoutDecimals, 500, collAddr, 8000),
            0.25e18
        );
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT PROPOSAL                                       *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanElasticChainlinkProposal_AcceptProposal_Test is PWNSimpleLoanElasticChainlinkProposalTest, PWNSimpleLoanProposal_AcceptProposal_Test {

    function setUp() virtual public override(PWNSimpleLoanElasticChainlinkProposalTest, PWNSimpleLoanProposalTest) {
        super.setUp();
    }


    function test_shouldFail_whenZeroMinCreditAmount() external {
        proposal.minCreditAmount = 0;

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoanElasticChainlinkProposal.MinCreditAmountNotSet.selector));
        vm.prank(activeLoanContract);
        proposalContract.acceptProposal({
            acceptor: acceptor,
            refinancingLoanId: 0,
            proposalData: abi.encode(proposal, proposalValues),
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, _proposalHash(proposal))
        });
    }

    function testFuzz_shouldFail_whenCreditAmountLessThanMinCreditAmount(
        uint256 minCreditAmount, uint256 creditAmount
    ) external {
        proposal.minCreditAmount = bound(minCreditAmount, 1, type(uint256).max);
        proposalValues.creditAmount = bound(creditAmount, 0, proposal.minCreditAmount - 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNSimpleLoanElasticChainlinkProposal.InsufficientCreditAmount.selector,
                proposalValues.creditAmount,
                proposal.minCreditAmount
            )
        );
        vm.prank(activeLoanContract);
        proposalContract.acceptProposal({
            acceptor: acceptor,
            refinancingLoanId: 0,
            proposalData: abi.encode(proposal, proposalValues),
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, _proposalHash(proposal))
        });
    }

    function testFuzz_shouldCallLoanContractWithLoanTerms(uint256 creditAmount, bool isOffer) external {
        proposalValues.creditAmount = bound(creditAmount, proposal.minCreditAmount, 1e40);
        proposal.isOffer = isOffer;

        vm.prank(activeLoanContract);
        (bytes32 proposalHash, PWNSimpleLoan.Terms memory terms) = proposalContract.acceptProposal({
            acceptor: acceptor,
            refinancingLoanId: 0,
            proposalData: abi.encode(proposal, proposalValues),
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, _proposalHash(proposal))
        });

        assertEq(proposalHash, _proposalHash(proposal));
        assertEq(terms.lender, isOffer ? proposal.proposer : acceptor);
        assertEq(terms.borrower, isOffer ? acceptor : proposal.proposer);
        assertEq(terms.duration, proposal.durationOrDate);
        assertEq(uint8(terms.collateral.category), uint8(proposal.collateralCategory));
        assertEq(terms.collateral.assetAddress, proposal.collateralAddress);
        assertEq(terms.collateral.id, proposal.collateralId);
        assertEq(terms.collateral.amount, proposalValues.creditAmount); // with LTV = 100%
        assertEq(uint8(terms.credit.category), uint8(MultiToken.Category.ERC20));
        assertEq(terms.credit.assetAddress, proposal.creditAddress);
        assertEq(terms.credit.id, 0);
        assertEq(terms.credit.amount, proposalValues.creditAmount);
        assertEq(terms.fixedInterestAmount, proposal.fixedInterestAmount);
        assertEq(terms.accruingInterestAPR, proposal.accruingInterestAPR);
        assertEq(terms.lenderSpecHash, isOffer ? proposal.proposerSpecHash : bytes32(0));
        assertEq(terms.borrowerSpecHash, isOffer ? bytes32(0) : proposal.proposerSpecHash);
    }

}


// Testing exposed internals

/*----------------------------------------------------------*|
|*  # EXPOSED - FIND PRICE                                  *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanElasticChainlinkProposal_Exposed_findPrice_Test is PWNSimpleLoanElasticChainlinkProposalTest {

    address asset = makeAddr("asset");

    function testFuzz_shouldReturnUSDUSDPrice_whenAvailable(uint256 _price, uint8 _decimals) external {
        _price = bound(_price, 0, uint256(type(int256).max));

        _mockLastRoundData(generalAggregator, int256(_price), 1);
        _mockFeedDecimals(generalAggregator, _decimals);

        vm.expectCall(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, asset, ChainlinkDenominations.USD),
            1
        );
        vm.expectCall(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, asset, ChainlinkDenominations.ETH),
            0
        );

        (uint256 price, uint8 decimals, address denominator) = proposalContract.exposed_findPrice(asset);
        assertEq(price, _price);
        assertEq(decimals, _decimals);
        assertEq(denominator, ChainlinkDenominations.USD);
    }

    function testFuzz_shouldFetchETHPrice_whenUSDNotAvailable(uint256 _price, uint8 _decimals) external {
        _price = bound(_price, 0, uint256(type(int256).max));

        _mockLastRoundData(generalAggregator, int256(_price), 1);
        _mockFeedDecimals(generalAggregator, _decimals);
        vm.mockCallRevert(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, asset, ChainlinkDenominations.USD),
            "whatnot"
        );

        vm.expectCall(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, asset, ChainlinkDenominations.USD),
            1
        );
        vm.expectCall(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, asset, ChainlinkDenominations.ETH),
            1
        );

        (uint256 price, uint8 decimals, address denominator) = proposalContract.exposed_findPrice(asset);
        assertEq(price, _price);
        assertEq(decimals, _decimals);
        assertEq(denominator, ChainlinkDenominations.ETH);
    }

    function test_shouldFail_whenPriceNotFoundInUSDOrETH() external {
        vm.mockCallRevert(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, asset, ChainlinkDenominations.USD),
            "whatnot"
        );
        vm.mockCallRevert(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, asset, ChainlinkDenominations.ETH),
            "whatnot"
        );

        vm.expectRevert(
            abi.encodeWithSelector(PWNSimpleLoanElasticChainlinkProposal.ChainlinkFeedNotFound.selector, asset)
        );
        proposalContract.exposed_findPrice(asset);
    }

}


/*----------------------------------------------------------*|
|*  # EXPOSED - FETCH PRICE                                 *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanElasticChainlinkProposal_Exposed_fetchPrice_Test is PWNSimpleLoanElasticChainlinkProposalTest {

    address asset = makeAddr("asset");
    address denominator = makeAddr("denominator");

    function testFuzz_shouldGetFeedFromRegistry(address _asset, address _denominator) external {
        vm.expectCall(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, _asset, _denominator)
        );

        proposalContract.exposed_fetchPrice(_asset, _denominator);
    }

    function test_shouldFetchETHPrice_whenWETH() external {
        vm.expectCall(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, ChainlinkDenominations.ETH, denominator)
        );

        proposalContract.exposed_fetchPrice(weth, denominator);
    }

    function test_shouldReturnFalse_whenAggregatorNotRegistered() external {
        vm.mockCallRevert(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, asset, denominator),
            "whatnot"
        );

        (bool success, uint256 price, uint8 decimals) = proposalContract.exposed_fetchPrice(asset, denominator);
        assertFalse(success);
        assertEq(price, 0);
        assertEq(decimals, 0);
    }

    function test_shouldFail_whenNegativePrice() external {
        _mockLastRoundData(generalAggregator, -1, 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNSimpleLoanElasticChainlinkProposal.ChainlinkFeedReturnedNegativePrice.selector, asset, denominator, -1
            )
        );
        proposalContract.exposed_fetchPrice(asset, denominator);
    }

    function test_shouldFail_whenPriceTooOld() external {
        _mockLastRoundData(generalAggregator, 1, 1);

        vm.warp(proposalContract.MAX_CHAINLINK_FEED_PRICE_AGE() + 2);

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNSimpleLoanElasticChainlinkProposal.ChainlinkFeedPriceTooOld.selector, asset, 1
            )
        );
        proposalContract.exposed_fetchPrice(asset, denominator);
    }

    function testFuzz_shouldReturnPriceAndDecimals(uint256 _price, uint8 _decimals) external {
        _price = bound(_price, 0, uint256(type(int256).max));

        _mockFeedDecimals(generalAggregator, _decimals);
        _mockLastRoundData(generalAggregator, int256(_price), 1);

        (bool success, uint256 price, uint8 decimals) = proposalContract.exposed_fetchPrice(asset, denominator);

        assertTrue(success);
        assertEq(price, _price);
        assertEq(decimals, _decimals);
    }

}


/*----------------------------------------------------------*|
|*  # EXPOSED - CONVERT USD DENOMINATOR TO ETH              *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanElasticChainlinkProposal_Exposed_convertUSDDenominatorToETH_Test is PWNSimpleLoanElasticChainlinkProposalTest {

    function test_shouldFetchETHPriceInUSD() external {
        vm.expectCall(
            feedRegistry,
            abi.encodeWithSelector(
                IChainlinkFeedRegistryLike.getFeed.selector, ChainlinkDenominations.ETH, ChainlinkDenominations.USD
            )
        );

        proposalContract.exposed_convertUSDDenominatorToETH(1e18, 18);
    }

    function testFuzz_shouldReturnSameValues_whenFailedToFetchPrice(uint256 nPrice, uint8 nDecimals) external {
        vm.mockCallRevert(
            feedRegistry,
            abi.encodeWithSelector(
                IChainlinkFeedRegistryLike.getFeed.selector, ChainlinkDenominations.ETH, ChainlinkDenominations.USD
            ),
            "whatnot"
        );

        (bool success, uint256 price, uint8 decimals)
            = proposalContract.exposed_convertUSDDenominatorToETH(nPrice, nDecimals);
        assertFalse(success);
        assertEq(price, nPrice);
        assertEq(decimals, nDecimals);
    }

    function testFuzz_shouldScaleToBiggerDecimals(uint8 nDecimals, uint8 feedDecimals) external {
        feedDecimals = uint8(bound(feedDecimals, 0, 70));
        nDecimals = uint8(bound(nDecimals, 0, 70));
        uint8 resultDecimals = uint8(Math.max(nDecimals, feedDecimals));

        _mockLastRoundData(generalAggregator, int256(10 ** feedDecimals), 1);
        _mockFeedDecimals(generalAggregator, feedDecimals);

        (, uint256 price, uint8 decimals) = proposalContract.exposed_convertUSDDenominatorToETH(10 ** nDecimals, nDecimals);

        assertEq(price, 10 ** resultDecimals);
        assertEq(decimals, resultDecimals);
    }

    function test_shouldConvertPrice() external {
        _mockFeedDecimals(generalAggregator, 8);

        _mockLastRoundData(generalAggregator, 3000e8, 1);
        (, uint256 price, uint8 decimals) = proposalContract.exposed_convertUSDDenominatorToETH(6000e8, 8);
        assertEq(price, 2e8);

        _mockLastRoundData(generalAggregator, 500e8, 1);
        (, price, decimals) = proposalContract.exposed_convertUSDDenominatorToETH(100e8, 8);
        assertEq(price, 0.2e8);

        _mockLastRoundData(generalAggregator, 5000e8, 1);
        (, price, decimals) = proposalContract.exposed_convertUSDDenominatorToETH(1e8, 8);
        assertEq(price, 0.0002e8);
    }

    function test_shouldReturnSuccess() external {
        (bool success,,) = proposalContract.exposed_convertUSDDenominatorToETH(1e18, 18);
        assertTrue(success);
    }

}


/*----------------------------------------------------------*|
|*  # EXPOSED - SCALE PRICE                                 *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanElasticChainlinkProposal_Exposed_scalePrice_Test is PWNSimpleLoanElasticChainlinkProposalTest {

    function test_shouldUpdateValueDecimals() external {
        assertEq(proposalContract.exposed_scalePrice(1e18, 18, 19), 1e19);
        assertEq(proposalContract.exposed_scalePrice(5e18, 18, 17), 5e17);
        assertEq(proposalContract.exposed_scalePrice(3319200, 3, 1), 33192);
        assertEq(proposalContract.exposed_scalePrice(0, 1, 10), 0);
    }

}
