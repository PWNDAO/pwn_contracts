// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import {
    PWNSimpleLoanUniswapV3LPProposal,
    PWNSimpleLoanProposal,
    PWNSimpleLoan,
    IChainlinkFeedRegistryLike,
    IChainlinkAggregatorLike,
    INonfungiblePositionManager
} from "pwn/loan/terms/simple/proposal/PWNSimpleLoanUniswapV3LPProposal.sol";

import { PWNSimpleLoanUniswapV3LPProposalHarness } from "test/harness/PWNSimpleLoanUniswapV3LPProposalHarness.sol";
import {
    MultiToken,
    Math,
    PWNSimpleLoanProposalTest,
    PWNSimpleLoanProposal_AcceptProposal_Test,
    PWNUtilizedCredit
} from "test/unit/PWNSimpleLoanProposal.t.sol";


abstract contract PWNSimpleLoanUniswapV3LPProposalTest is PWNSimpleLoanProposalTest {

    PWNSimpleLoanUniswapV3LPProposalHarness proposalContract;
    PWNSimpleLoanUniswapV3LPProposal.Proposal proposal;
    PWNSimpleLoanUniswapV3LPProposal.ProposalValues proposalValues;

    address uniswapV3Factory = makeAddr("uniswapV3Factory");
    address uniswapNFTPositionManager = makeAddr("uniswapNFTPositionManager");
    address feedRegistry = makeAddr("feedRegistry");
    address feed = makeAddr("feed");
    address weth = makeAddr("weth");
    address l2SequencerUptimeFeed = makeAddr("l2SequencerUptimeFeed");

    uint256 collateralId = 420;
    address token0 = makeAddr("token0");
    address token1 = makeAddr("token1");
    uint24 fee = 3000;
    address pool = 0xb44E273AE4071AA4a0F2b05ee96f20BB6FfD568b;
    uint256 token0Value = 101572;
    uint256 token1Value = 331794706808;

    event ProposalMade(bytes32 indexed proposalHash, address indexed proposer, PWNSimpleLoanUniswapV3LPProposal.Proposal proposal);

    function setUp() virtual public override {
        super.setUp();

        vm.etch(token, "bytes");
        vm.etch(uniswapNFTPositionManager, "bytes");

        proposalContract = new PWNSimpleLoanUniswapV3LPProposalHarness(hub, revokedNonce, config, utilizedCredit, uniswapV3Factory, uniswapNFTPositionManager, feedRegistry, address(0), weth);
        proposalContractAddr = PWNSimpleLoanProposal(proposalContract);

        proposal = PWNSimpleLoanUniswapV3LPProposal.Proposal({
            tokenAAllowlist: new address[](0),
            tokenBAllowlist: new address[](0),
            creditAddress: token0,
            feedIntermediaryDenominations: new address[](0),
            feedInvertFlags: new bool[](0),
            loanToValue: 10000, // 100%
            minCreditAmount: 1,
            availableCreditLimit: 0,
            utilizedCreditId: 0,
            fixedInterestAmount: 1,
            accruingInterestAPR: 0,
            durationOrDate: 1 days,
            expiration: 60303,
            acceptorController: address(0),
            acceptorControllerData: "",
            proposer: proposer,
            proposerSpecHash: keccak256("proposer spec"),
            isOffer: true,
            refinancingLoanId: 0,
            nonceSpace: 1,
            nonce: uint256(keccak256("nonce_1")),
            loanContract: activeLoanContract
        });
        proposal.tokenAAllowlist.push(token0);
        proposal.tokenBAllowlist.push(token1);

        proposalValues = PWNSimpleLoanUniswapV3LPProposal.ProposalValues({
            collateralId: collateralId,
            tokenAIndex: 0,
            tokenBIndex: 0,
            acceptorControllerData: ""
        });

        vm.mockCall(address(uniswapNFTPositionManager), abi.encodeWithSignature("factory()"), abi.encode(uniswapV3Factory));
    }


    function _proposalHash(PWNSimpleLoanUniswapV3LPProposal.Proposal memory _proposal) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            "\x19\x01",
            keccak256(abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("PWNSimpleLoanUniswapV3LPProposal"),
                keccak256("1.0"),
                block.chainid,
                proposalContractAddr
            )),
            keccak256(abi.encodePacked(
                keccak256("Proposal(address[] tokenAAllowlist,address[] tokenBAllowlist,address creditAddress,address[] feedIntermediaryDenominations,bool[] feedInvertFlags,uint256 loanToValue,uint256 minCreditAmount,uint256 availableCreditLimit,bytes32 utilizedCreditId,uint256 fixedInterestAmount,uint24 accruingInterestAPR,uint32 durationOrDate,uint40 expiration,address acceptorController,bytes acceptorControllerData,address proposer,bytes32 proposerSpecHash,bool isOffer,uint256 refinancingLoanId,uint256 nonceSpace,uint256 nonce,address loanContract)"),
                proposalContract.exposed_erc712EncodeProposal(_proposal)
            ))
        ));
    }

    function _updateProposal(CommonParams memory _params) internal {
        proposal.availableCreditLimit = _params.availableCreditLimit;
        proposal.utilizedCreditId = _params.utilizedCreditId;
        proposal.durationOrDate = _params.durationOrDate;
        proposal.expiration = _params.expiration;
        proposal.acceptorController = _params.acceptorController;
        proposal.acceptorControllerData = _params.acceptorControllerProposerData;
        proposal.proposer = _params.proposer;
        proposal.isOffer = _params.isOffer;
        proposal.refinancingLoanId = _params.refinancingLoanId;
        proposal.nonceSpace = _params.nonceSpace;
        proposal.nonce = _params.nonce;
        proposal.loanContract = _params.loanContract;

        proposalValues.collateralId = _params.collateralId;
        proposalValues.acceptorControllerData = _params.acceptorControllerAcceptorData;
    }


    function _callAcceptProposalWith(Params memory _params) internal override returns (bytes32, PWNSimpleLoan.Terms memory) {
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

    function _mockPosition(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 tokensOwed0,
        uint256 tokensOwed1
    ) internal {
        vm.mockCall(
            address(uniswapNFTPositionManager),
            abi.encodeWithSelector(INonfungiblePositionManager.positions.selector),
            abi.encode(0, 0, token0, token1, fee, tickLower, tickUpper, liquidity, 0, 0, tokensOwed0, tokensOwed1)
        );
    }

    function _mockPool(address _pool, int24 currentTick) internal {
        vm.mockCall(_pool, abi.encodeWithSignature("slot0()"), abi.encode(0, currentTick, 0, 2, 0, 0, 0));
        vm.mockCall(_pool, abi.encodeWithSignature("observations(uint256)"), abi.encode(0, 0, 0, 0));
        vm.mockCall(_pool, abi.encodeWithSignature("liquidity()"), abi.encode(0)); // need to not revert
        vm.mockCall(_pool, abi.encodeWithSignature("feeGrowthGlobal0X128()"), abi.encode(0));
        vm.mockCall(_pool, abi.encodeWithSignature("feeGrowthGlobal1X128()"), abi.encode(0));
        vm.mockCall(_pool, abi.encodeWithSignature("ticks(int24)"), abi.encode(0, 0, 0, 0, 0, 0, 0, 0));
    }

}


/*----------------------------------------------------------*|
|*  # REVOKE NONCE                                          *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanUniswapV3LPProposal_RevokeNonce_Test is PWNSimpleLoanUniswapV3LPProposalTest {

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

contract PWNSimpleLoanUniswapV3LPProposal_GetProposalHash_Test is PWNSimpleLoanUniswapV3LPProposalTest {

    function test_shouldReturnProposalHash() external {
        assertEq(_proposalHash(proposal), proposalContract.getProposalHash(proposal));
    }

}


/*----------------------------------------------------------*|
|*  # MAKE PROPOSAL                                         *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanUniswapV3LPProposal_MakeProposal_Test is PWNSimpleLoanUniswapV3LPProposalTest {

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

contract PWNSimpleLoanUniswapV3LPProposal_EncodeProposalData_Test is PWNSimpleLoanUniswapV3LPProposalTest {

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

contract PWNSimpleLoanUniswapV3LPProposal_DecodeProposalData_Test is PWNSimpleLoanUniswapV3LPProposalTest {

    function test_shouldReturnDecodedProposalData() external {
        (
            PWNSimpleLoanUniswapV3LPProposal.Proposal memory _proposal,
            PWNSimpleLoanUniswapV3LPProposal.ProposalValues memory _proposalValues
        ) = proposalContract.decodeProposalData(abi.encode(proposal, proposalValues));


        assertEq(_proposal.tokenAAllowlist, proposal.tokenAAllowlist);
        assertEq(_proposal.tokenBAllowlist, proposal.tokenBAllowlist);
        assertEq(_proposal.creditAddress, proposal.creditAddress);
        assertEq(_proposal.feedIntermediaryDenominations, proposal.feedIntermediaryDenominations);
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
        assertEq(_proposal.acceptorController, proposal.acceptorController);
        assertEq(_proposal.acceptorControllerData, proposal.acceptorControllerData);
        assertEq(_proposal.proposer, proposal.proposer);
        assertEq(_proposal.isOffer, proposal.isOffer);
        assertEq(_proposal.refinancingLoanId, proposal.refinancingLoanId);
        assertEq(_proposal.nonceSpace, proposal.nonceSpace);
        assertEq(_proposal.nonce, proposal.nonce);
        assertEq(_proposal.loanContract, proposal.loanContract);

        assertEq(_proposalValues.collateralId, proposalValues.collateralId);
        assertEq(_proposalValues.tokenAIndex, proposalValues.tokenAIndex);
        assertEq(_proposalValues.tokenBIndex, proposalValues.tokenBIndex);
        assertEq(_proposalValues.acceptorControllerData, proposalValues.acceptorControllerData);
    }

}


/*----------------------------------------------------------*|
|*  # GET CREDIT AMOUNT                                     *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanUniswapV3LPProposal_GetCreditAmount_Test is PWNSimpleLoanUniswapV3LPProposalTest {

    function setUp() virtual override public {
        super.setUp();

        _mockPosition(100_000, 200_000, 100e6, 0, 0);
        _mockPool(pool, 150_000);
    }


    function test_shouldReturnLPValueInToken0_whenCreditIsToken0() external {
        uint256 credAmount = proposalContract
            .getCreditAmount(token0, collateralId, true, new address[](0), new bool[](0), 10000);

        assertEq(credAmount, token0Value);
    }

    function test_shouldReturnLPValueInToken1_whenCreditIsToken1() external {
        uint256 credAmount = proposalContract
            .getCreditAmount(token1, collateralId, false, new address[](0), new bool[](0), 10000);

        assertEq(credAmount, token1Value);
    }

    function test_shouldConvertDenominationViaChainlink_whenCreditNotToken01() external {
        address credAddr = makeAddr("credAddr");
        address[] memory feedIntermediaryDenominations = new address[](0);
        bool[] memory feedInvertFlags = new bool[](1);
        feedInvertFlags[0] = false;

        _mockFeed(feed);
        _mockLastRoundData(feed, 300e6, 1);
        _mockFeedDecimals(feed, 6);
        _mockAssetDecimals(credAddr, 22);
        _mockAssetDecimals(token0, 6);

        uint256 credAmount = proposalContract
            .getCreditAmount(credAddr, collateralId, true, feedIntermediaryDenominations, feedInvertFlags, 10000);
        assertEq(credAmount, token0Value * 300e16);
    }

    function test_shouldCalculateLoanToValue() external {
        uint256 credAmount = proposalContract
            .getCreditAmount(token1, collateralId, false, new address[](0), new bool[](0), 7000);

        assertEq(credAmount, token1Value * 7 / 10);
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT PROPOSAL                                       *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanUniswapV3LPProposal_AcceptProposal_Test is PWNSimpleLoanUniswapV3LPProposalTest, PWNSimpleLoanProposal_AcceptProposal_Test(3) {

    function setUp() virtual public override(PWNSimpleLoanUniswapV3LPProposalTest, PWNSimpleLoanProposalTest) {
        super.setUp();

        _mockPosition(100_000, 200_000, 100e6, 0, 0);
        _mockPool(pool, 150_000);
    }


    function test_shouldFail_whenZeroMinCreditAmount() external {
        proposal.minCreditAmount = 0;

        bytes32 proposalHash = _proposalHash(proposal);

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoanUniswapV3LPProposal.MinCreditAmountNotSet.selector));
        vm.prank(activeLoanContract);
        proposalContract.acceptProposal({
            acceptor: acceptor,
            refinancingLoanId: 0,
            proposalData: abi.encode(proposal, proposalValues),
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, proposalHash)
        });
    }

    function test_shouldFail_whenCreditAmountLessThanMinCreditAmount() external {
        proposal.minCreditAmount = token0Value + 1;

        bytes32 proposalHash = _proposalHash(proposal);

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNSimpleLoanUniswapV3LPProposal.InsufficientCreditAmount.selector,
                token0Value,
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

    function test_shouldFail_whenLPPairNotAllowlisted() external {
        proposal.tokenAAllowlist[0] = token;
        proposal.tokenBAllowlist[0] = token1;
        bytes32 proposalHash = _proposalHash(proposal);

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoanUniswapV3LPProposal.InvalidLPTokenPair.selector));
        vm.prank(activeLoanContract);
        proposalContract.acceptProposal({
            acceptor: acceptor,
            refinancingLoanId: 0,
            proposalData: abi.encode(proposal, proposalValues),
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, proposalHash)
        });

        proposal.tokenAAllowlist[0] = token0;
        proposal.tokenBAllowlist[0] = token;
        proposalHash = _proposalHash(proposal);

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoanUniswapV3LPProposal.InvalidLPTokenPair.selector));
        vm.prank(activeLoanContract);
        proposalContract.acceptProposal({
            acceptor: acceptor,
            refinancingLoanId: 0,
            proposalData: abi.encode(proposal, proposalValues),
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, proposalHash)
        });

        proposal.tokenAAllowlist[0] = token;
        proposal.tokenBAllowlist[0] = token;
        proposalHash = _proposalHash(proposal);

        vm.expectRevert(abi.encodeWithSelector(PWNSimpleLoanUniswapV3LPProposal.InvalidLPTokenPair.selector));
        vm.prank(activeLoanContract);
        proposalContract.acceptProposal({
            acceptor: acceptor,
            refinancingLoanId: 0,
            proposalData: abi.encode(proposal, proposalValues),
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, proposalHash)
        });
    }

    function testFuzz_shouldUtilizeCredit(bytes32 id, uint256 limit) external {
        proposal.availableCreditLimit = bound(limit, token0Value, type(uint256).max);
        proposal.utilizedCreditId = id;
        bytes32 proposalHash = _proposalHash(proposal);

        vm.mockCall(
            utilizedCredit,
            abi.encodeWithSelector(PWNUtilizedCredit.utilizeCredit.selector),
            abi.encode("")
        );

        vm.expectCall(
            utilizedCredit,
            abi.encodeWithSelector(
                PWNUtilizedCredit.utilizeCredit.selector,
                proposer, proposal.utilizedCreditId, token0Value, proposal.availableCreditLimit
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

    function test_shouldCallLoanContractWithLoanTerms() external {
        proposal.isOffer = true;
        bytes32 proposalHash = _proposalHash(proposal);

        vm.prank(activeLoanContract);
        (bytes32 proposalHash_, PWNSimpleLoan.Terms memory terms) = proposalContract.acceptProposal({
            acceptor: acceptor,
            refinancingLoanId: 0,
            proposalData: abi.encode(proposal, proposalValues),
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, proposalHash)
        });

        assertEq(proposalHash_, proposalHash);
        assertEq(terms.lender, proposal.proposer);
        assertEq(terms.borrower, acceptor);
        assertEq(terms.duration, proposal.durationOrDate);
        assertEq(uint8(terms.collateral.category), uint8(MultiToken.Category.ERC721));
        assertEq(terms.collateral.assetAddress, uniswapNFTPositionManager);
        assertEq(terms.collateral.id, proposalValues.collateralId);
        assertEq(terms.collateral.amount, 0);
        assertEq(uint8(terms.credit.category), uint8(MultiToken.Category.ERC20));
        assertEq(terms.credit.assetAddress, proposal.creditAddress);
        assertEq(terms.credit.id, 0);
        assertEq(terms.credit.amount, token0Value); // with LTV = 100%
        assertEq(terms.fixedInterestAmount, proposal.fixedInterestAmount);
        assertEq(terms.accruingInterestAPR, proposal.accruingInterestAPR);
        assertEq(terms.lenderSpecHash, proposal.proposerSpecHash);
        assertEq(terms.borrowerSpecHash, bytes32(0));

        proposal.isOffer = false;
        proposalHash = _proposalHash(proposal);

        vm.prank(activeLoanContract);
        (proposalHash_, terms) = proposalContract.acceptProposal({
            acceptor: acceptor,
            refinancingLoanId: 0,
            proposalData: abi.encode(proposal, proposalValues),
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, proposalHash)
        });

        assertEq(terms.lender, acceptor);
        assertEq(terms.borrower, proposal.proposer);
        assertEq(terms.lenderSpecHash, bytes32(0));
        assertEq(terms.borrowerSpecHash, proposal.proposerSpecHash);
    }

}


/*----------------------------------------------------------*|
|*  # ERC712 ENCODE PROPOSAL                                *|
|*----------------------------------------------------------*/

contract PWNSimpleLoanUniswapV3LPProposal_Erc712EncodeProposal_Test is PWNSimpleLoanUniswapV3LPProposalTest {

    function test_shouldERC712EncodeProposal() external {
        PWNSimpleLoanUniswapV3LPProposal.ERC712Proposal memory proposalErc712 = PWNSimpleLoanUniswapV3LPProposal.ERC712Proposal(
            keccak256(abi.encodePacked(proposal.tokenAAllowlist)),
            keccak256(abi.encodePacked(proposal.tokenBAllowlist)),
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
            proposal.acceptorController,
            keccak256(proposal.acceptorControllerData),
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
