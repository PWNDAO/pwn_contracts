// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { PWNHubTags } from "pwn/hub/PWNHubTags.sol";
import {
    PWNSimpleLoanElasticChainlinkProposal,
    PWNSimpleLoanProposal,
    SimpleTerms,
    IChainlinkAggregatorLike,
    IChainlinkFeedRegistryLike,
    Chainlink
} from "pwn/loan/terms/simple/proposal/PWNSimpleLoanElasticChainlinkProposal.sol";

import { PWNSimpleLoanElasticChainlinkProposalHarness } from "test/harness/PWNSimpleLoanElasticChainlinkProposalHarness.sol";
import { ChainlinkDenominations } from "test/helper/ChainlinkDenominations.sol";
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
    address feed = makeAddr("feed");
    address weth = makeAddr("weth");
    address l2SequencerUptimeFeed = makeAddr("l2SequencerUptimeFeed");

    event ProposalMade(bytes32 indexed proposalHash, address indexed proposer, PWNSimpleLoanElasticChainlinkProposal.Proposal proposal);

    function setUp() virtual public override {
        super.setUp();

        vm.etch(token, "bytes");

        proposalContract = new PWNSimpleLoanElasticChainlinkProposalHarness(hub, revokedNonce, config, utilizedCredit, feedRegistry, address(0), weth);
        proposalContractAddr = PWNSimpleLoanProposal(proposalContract);

        bool[] memory feedInvertFlags = new bool[](1);
        feedInvertFlags[0] = false;

        proposal = PWNSimpleLoanElasticChainlinkProposal.Proposal({
            collateralCategory: MultiToken.Category.ERC1155,
            collateralAddress: token,
            collateralId: 0,
            checkCollateralStateFingerprint: true,
            collateralStateFingerprint: keccak256("some state fingerprint"),
            creditAddress: token,
            feedIntermediaryDenominations: new address[](0),
            feedInvertFlags: feedInvertFlags,
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

        _mockFeed(feed);
        _mockLastRoundData(feed, 1e18, 1);
        _mockFeedDecimals(feed, 18);
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
                keccak256("Proposal(uint8 collateralCategory,address collateralAddress,uint256 collateralId,bool checkCollateralStateFingerprint,bytes32 collateralStateFingerprint,address creditAddress,address[] feedIntermediaryDenominations,bool[] feedInvertFlags,uint256 loanToValue,uint256 minCreditAmount,uint256 availableCreditLimit,bytes32 utilizedCreditId,uint256 fixedInterestAmount,uint24 accruingInterestAPR,uint32 durationOrDate,uint40 expiration,address allowedAcceptor,address proposer,bytes32 proposerSpecHash,bool isOffer,uint256 refinancingLoanId,uint256 nonceSpace,uint256 nonce,address loanContract)"),
                proposalContract.exposed_erc712EncodeProposal(_proposal)
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


    function _callAcceptProposalWith(Params memory _params) internal override returns (bytes32, SimpleTerms memory) {
        _mockLastRoundData(feed, 1e18, block.timestamp); // To avoid "ChainlinkFeedPriceTooOld" error

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

    function _mockFeed(address _feed) internal {
        vm.mockCall(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector),
            abi.encode(_feed)
        );
    }

    function _mockFeed(address _feed, address base, address quote) internal {
        vm.mockCall(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, base, quote),
            abi.encode(_feed)
        );
    }

    function _mockLastRoundData(address _feed, int256 answer, uint256 updatedAt) internal {
        vm.mockCall(
            _feed,
            abi.encodeWithSelector(IChainlinkAggregatorLike.latestRoundData.selector),
            abi.encode(0, answer, 0, updatedAt, 0)
        );
    }

    function _mockFeedDecimals(address _feed, uint8 decimals) internal {
        vm.mockCall(
            _feed,
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
        assertEq(_proposal.feedIntermediaryDenominations.length, proposal.feedIntermediaryDenominations.length);
        for (uint256 i; i < _proposal.feedIntermediaryDenominations.length; ++i) {
            assertEq(_proposal.feedIntermediaryDenominations[i], proposal.feedIntermediaryDenominations[i]);
        }
        assertEq(_proposal.feedInvertFlags.length, proposal.feedInvertFlags.length);
        for (uint256 i; i < _proposal.feedInvertFlags.length; ++i) {
            assertEq(_proposal.feedInvertFlags[i], proposal.feedInvertFlags[i]);
        }
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
    uint256 credAmount = 100e18;
    uint256 loanToValue = 5000; // 50%
    address[] feedIntermediaryDenominations;
    bool[] feedInvertFlags;
    uint256 L2_GRACE_PERIOD;

    function setUp() virtual override public {
        super.setUp();

        feedIntermediaryDenominations = new address[](0);
        feedInvertFlags = new bool[](1);
        feedInvertFlags[0] = false;
        L2_GRACE_PERIOD = Chainlink.L2_GRACE_PERIOD;

        _mockAssetDecimals(collAddr, 18);
        _mockAssetDecimals(credAddr, 18);
    }


    function test_shouldFetchSequencerUptimeFeed_whenFeedSet() external {
        vm.warp(1e9);

        proposalContract = new PWNSimpleLoanElasticChainlinkProposalHarness(hub, revokedNonce, config, utilizedCredit, feedRegistry, l2SequencerUptimeFeed, weth);
        _mockSequencerUptimeFeed(true, block.timestamp - L2_GRACE_PERIOD - 1);
        _mockLastRoundData(feed, 1e18, block.timestamp);

        vm.expectCall(
            l2SequencerUptimeFeed,
            abi.encodeWithSelector(IChainlinkAggregatorLike.latestRoundData.selector)
        );

        proposalContract.getCollateralAmount(credAddr, credAmount, collAddr, feedIntermediaryDenominations, feedInvertFlags, loanToValue);
    }

    function test_shouldFail_whenL2SequencerDown_whenFeedSet() external {
        vm.warp(1e9);

        proposalContract = new PWNSimpleLoanElasticChainlinkProposalHarness(hub, revokedNonce, config, utilizedCredit, feedRegistry, l2SequencerUptimeFeed, weth);
        _mockSequencerUptimeFeed(false, block.timestamp - L2_GRACE_PERIOD - 1);

        vm.expectRevert(abi.encodeWithSelector(Chainlink.L2SequencerDown.selector));
        proposalContract.getCollateralAmount(credAddr, credAmount, collAddr, feedIntermediaryDenominations, feedInvertFlags, loanToValue);
    }

    function testFuzz_shouldFail_whenL2SequencerUp_whenInGracePeriod_whenFeedSet(uint256 startedAt) external {
        vm.warp(1e9);
        startedAt = bound(startedAt, block.timestamp - L2_GRACE_PERIOD, block.timestamp);

        proposalContract = new PWNSimpleLoanElasticChainlinkProposalHarness(hub, revokedNonce, config, utilizedCredit, feedRegistry, l2SequencerUptimeFeed, weth);
        _mockSequencerUptimeFeed(true, startedAt);

        vm.expectRevert(
            abi.encodeWithSelector(
                Chainlink.GracePeriodNotOver.selector,
                block.timestamp - startedAt, L2_GRACE_PERIOD
            )
        );
        proposalContract.getCollateralAmount(credAddr, credAmount, collAddr, feedIntermediaryDenominations, feedInvertFlags, loanToValue);
    }

    function test_shouldNotFetchSequencerUptimeFeed_whenFeedNotSet() external {
        vm.expectCall(
            l2SequencerUptimeFeed,
            abi.encodeWithSelector(IChainlinkAggregatorLike.latestRoundData.selector),
            0
        );

        proposalContract.getCollateralAmount(credAddr, credAmount, collAddr, feedIntermediaryDenominations, feedInvertFlags, loanToValue);
    }

    function test_shouldFail_whenIntermediaryDenominationsOutOfBounds() external {
        feedIntermediaryDenominations = new address[](3);

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNSimpleLoanElasticChainlinkProposal.IntermediaryDenominationsOutOfBounds.selector,
                3, proposalContract.MAX_INTERMEDIARY_DENOMINATIONS()
            )
        );
        proposalContract.getCollateralAmount(credAddr, credAmount, collAddr, feedIntermediaryDenominations, feedInvertFlags, loanToValue);
    }

    function test_shouldFetchCreditAndCollateralPrices() external {
        feedIntermediaryDenominations = new address[](2);
        feedIntermediaryDenominations[0] = makeAddr("inter1");
        feedIntermediaryDenominations[1] = makeAddr("inter2");
        feedInvertFlags = new bool[](3);
        feedInvertFlags[0] = false;
        feedInvertFlags[1] = false;
        feedInvertFlags[2] = false;

        vm.expectCall(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, credAddr, feedIntermediaryDenominations[0])
        );
        vm.expectCall(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, feedIntermediaryDenominations[0], feedIntermediaryDenominations[1])
        );
        vm.expectCall(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, feedIntermediaryDenominations[1], collAddr)
        );

        proposalContract.getCollateralAmount(credAddr, credAmount, collAddr, feedIntermediaryDenominations, feedInvertFlags, loanToValue);
    }

    function test_shouldFetchETHPrice_whenWETH() external {
        _mockAssetDecimals(weth, 18);

        vm.expectCall(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, ChainlinkDenominations.ETH, collAddr)
        );
        proposalContract.getCollateralAmount(weth, credAmount, collAddr, feedIntermediaryDenominations, feedInvertFlags, loanToValue);

        vm.expectCall(
            feedRegistry,
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, credAddr, ChainlinkDenominations.ETH)
        );
        proposalContract.getCollateralAmount(credAddr, credAmount, weth, feedIntermediaryDenominations, feedInvertFlags, loanToValue);
    }

    function test_shouldReturnCorrectDecimals() external {
        // price = 1

        _mockAssetDecimals(collAddr, 18);
        _mockAssetDecimals(credAddr, 6);
        assertEq(
            proposalContract.getCollateralAmount(credAddr, 8e6, collAddr, feedIntermediaryDenominations, feedInvertFlags, 2000),
            40e18
        );

        _mockAssetDecimals(collAddr, 6);
        _mockAssetDecimals(credAddr, 18);
        assertEq(
            proposalContract.getCollateralAmount(credAddr, 8e18, collAddr, feedIntermediaryDenominations, feedInvertFlags, 2000),
            40e6
        );

        _mockAssetDecimals(weth, 0);
        _mockAssetDecimals(credAddr, 18);
        assertEq(
            proposalContract.getCollateralAmount(credAddr, 8e18, weth, feedIntermediaryDenominations, feedInvertFlags, 2000),
            40
        );
    }

    function test_shouldReturnCollateralAmount() external {
        _mockFeedDecimals(feed, 8);

        _mockLastRoundData(feed, 300e8, 1);
        assertEq(
            proposalContract.getCollateralAmount(credAddr, 8e18, collAddr, feedIntermediaryDenominations, feedInvertFlags, 2000),
            12000e18
        );

        _mockLastRoundData(feed, 1e8, 1);
        assertEq(
            proposalContract.getCollateralAmount(credAddr, 0, collAddr, feedIntermediaryDenominations, feedInvertFlags, 2000),
            0
        );

        _mockLastRoundData(feed, 0.5e8, 1);
        assertEq(
            proposalContract.getCollateralAmount(credAddr, 20e18, collAddr, feedIntermediaryDenominations, feedInvertFlags, 8000),
            12.5e18
        );

        _mockLastRoundData(feed, 4e8, 1);
        assertEq(
            proposalContract.getCollateralAmount(credAddr, 20e18, collAddr, feedIntermediaryDenominations, feedInvertFlags, 20000),
            40e18
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

        bytes32 proposalHash = _proposalHash(proposal);

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoanElasticChainlinkProposal.MinCreditAmountNotSet.selector));
        vm.prank(activeLoanContract);
        proposalContract.acceptProposal({
            acceptor: acceptor,
            refinancingLoanId: 0,
            proposalData: abi.encode(proposal, proposalValues),
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, proposalHash)
        });
    }

    function testFuzz_shouldFail_whenCreditAmountLessThanMinCreditAmount(
        uint256 minCreditAmount, uint256 creditAmount
    ) external {
        proposal.minCreditAmount = bound(minCreditAmount, 1, type(uint256).max);
        proposalValues.creditAmount = bound(creditAmount, 0, proposal.minCreditAmount - 1);

        bytes32 proposalHash = _proposalHash(proposal);

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
            signature: _sign(proposerPK, proposalHash)
        });
    }

    function testFuzz_shouldCallLoanContractWithLoanTerms(uint256 creditAmount, bool isOffer) external {
        proposalValues.creditAmount = bound(creditAmount, proposal.minCreditAmount, 1e40);
        proposal.isOffer = isOffer;

        bytes32 proposalHash = _proposalHash(proposal);

        vm.prank(activeLoanContract);
        (bytes32 proposalHash_, SimpleTerms memory terms) = proposalContract.acceptProposal({
            acceptor: acceptor,
            refinancingLoanId: 0,
            proposalData: abi.encode(proposal, proposalValues),
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, proposalHash)
        });

        assertEq(proposalHash_, proposalHash);
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


/*----------------------------------------------------------*|
|*  # ERC712 ENCODE PROPOSAL                                *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanElasticChainlinkProposal_Erc712EncodeProposal_Test is PWNSimpleLoanElasticChainlinkProposalTest {

    struct Proposal_ERC712 {
        MultiToken.Category collateralCategory;
        address collateralAddress;
        uint256 collateralId;
        bool checkCollateralStateFingerprint;
        bytes32 collateralStateFingerprint;
        address creditAddress;
        bytes32 feedIntermediaryDenominationsHash; // encode array hash
        bytes32 feedInvertFlagsHash; // encode array hash
        uint256 loanToValue;
        uint256 minCreditAmount;
        uint256 availableCreditLimit;
        bytes32 utilizedCreditId;
        uint256 fixedInterestAmount;
        uint24 accruingInterestAPR;
        uint32 durationOrDate;
        uint40 expiration;
        address allowedAcceptor;
        address proposer;
        bytes32 proposerSpecHash;
        bool isOffer;
        uint256 refinancingLoanId;
        uint256 nonceSpace;
        uint256 nonce;
        address loanContract;
    }


    function test_shouldERC712EncodeProposal() external {
        Proposal_ERC712 memory proposalErc712 = Proposal_ERC712(
            proposal.collateralCategory,
            proposal.collateralAddress,
            proposal.collateralId,
            proposal.checkCollateralStateFingerprint,
            proposal.collateralStateFingerprint,
            proposal.creditAddress,
            keccak256(abi.encodePacked(proposal.feedIntermediaryDenominations)),
            keccak256(abi.encodePacked(proposal.feedInvertFlags)),
            proposal.loanToValue,
            proposal.minCreditAmount,
            proposal.availableCreditLimit,
            proposal.utilizedCreditId,
            proposal.fixedInterestAmount,
            proposal.accruingInterestAPR,
            proposal.durationOrDate,
            proposal.expiration,
            proposal.allowedAcceptor,
            proposal.proposer,
            proposal.proposerSpecHash,
            proposal.isOffer,
            proposal.refinancingLoanId,
            proposal.nonceSpace,
            proposal.nonce,
            proposal.loanContract
        );

        assertEq(
            keccak256(abi.encode(proposalErc712)),
            keccak256(proposalContract.exposed_erc712EncodeProposal(proposal))
        );
    }

}
