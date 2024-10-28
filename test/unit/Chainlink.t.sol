// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import {
    Chainlink,
    IChainlinkFeedRegistryLike,
    IChainlinkAggregatorLike,
    ChainlinkDenominations,
    Math
} from "pwn/loan/lib/Chainlink.sol";

import { ChainlinkHarness } from "test/harness/ChainlinkHarness.sol";


abstract contract ChainlinkTest is Test {

    ChainlinkHarness chainlink;

    IChainlinkFeedRegistryLike feedRegistry = IChainlinkFeedRegistryLike(makeAddr("feedRegistry"));
    address aggregator = makeAddr("aggregator");
    IChainlinkAggregatorLike l2SequencerUptimeFeed = IChainlinkAggregatorLike(makeAddr("l2SequencerUptimeFeed"));
    address asset = makeAddr("asset");

    function setUp() public virtual {
        chainlink = new ChainlinkHarness();

        _mockFeed(aggregator);
        _mockLastRoundData(aggregator, 1e18, 1);
        _mockFeedDecimals(aggregator, 18);
        _mockSequencerUptimeFeed(true, block.timestamp - 1);
    }


    function _mockFeed(address _aggregator) internal {
        vm.mockCall(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector),
            abi.encode(_aggregator)
        );
    }

    function _mockFeed(address _aggregator, address base, address quote) internal {
        vm.mockCall(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, base, quote),
            abi.encode(_aggregator)
        );
    }

    function _mockLastRoundData(address _aggregator, int256 answer, uint256 updatedAt) internal {
        vm.mockCall(
            _aggregator,
            abi.encodeWithSelector(IChainlinkAggregatorLike.latestRoundData.selector),
            abi.encode(0, answer, 0, updatedAt, 0)
        );
    }

    function _mockFeedDecimals(address _aggregator, uint8 decimals) internal {
        vm.mockCall(
            _aggregator,
            abi.encodeWithSelector(IChainlinkAggregatorLike.decimals.selector),
            abi.encode(decimals)
        );
    }

    function _mockSequencerUptimeFeed(bool isUp, uint256 startedAt) internal {
        vm.mockCall(
            address(l2SequencerUptimeFeed),
            abi.encodeWithSelector(IChainlinkAggregatorLike.latestRoundData.selector),
            abi.encode(0, isUp ? 0 : 1, startedAt, 0, 0)
        );
    }

    function _mockAssetDecimals(address _asset, uint8 _decimals) internal {
        vm.mockCall(_asset, abi.encodeWithSignature("decimals()"), abi.encode(_decimals));
    }

}


/*----------------------------------------------------------*|
|*  # CHECK SEQUENCER UPTIME                                *|
|*----------------------------------------------------------*/

contract Chainlink_CheckSequencerUptime_Test is ChainlinkTest {

    function setUp() public virtual override {
        super.setUp();

        vm.warp(Chainlink.L2_GRACE_PERIOD + 100);
    }


    function test_shouldSkip_whenFeedIsZero() external {
        vm.expectCall(
            address(0),
            abi.encodeWithSelector(IChainlinkAggregatorLike.latestRoundData.selector),
            0
        );

        chainlink.checkSequencerUptime(IChainlinkAggregatorLike(address(0)));
    }

    function test_shouldFetchLatestRoundData() external {
        _mockSequencerUptimeFeed(true, 0);

        vm.expectCall(
            address(l2SequencerUptimeFeed),
            abi.encodeWithSelector(IChainlinkAggregatorLike.latestRoundData.selector)
        );

        chainlink.checkSequencerUptime(l2SequencerUptimeFeed);
    }

    function test_shouldFail_whenSequencerDown() external {
        _mockSequencerUptimeFeed(false, 0);

        vm.expectRevert(abi.encodeWithSelector(Chainlink.L2SequencerDown.selector));
        chainlink.checkSequencerUptime(l2SequencerUptimeFeed);
    }

    function testFuzz_shouldFail_whenSequencerInGracePeriod(uint256 gracePeriod) external {
        gracePeriod = bound(gracePeriod, 0, Chainlink.L2_GRACE_PERIOD);
        _mockSequencerUptimeFeed(true, block.timestamp - gracePeriod);

        vm.expectRevert(
            abi.encodeWithSelector(Chainlink.GracePeriodNotOver.selector, gracePeriod, Chainlink.L2_GRACE_PERIOD)
        );
        chainlink.checkSequencerUptime(l2SequencerUptimeFeed);
    }

}


/*----------------------------------------------------------*|
|*  # FETCH PRICE WITH COMMON DENOMINATOR                   *|
|*----------------------------------------------------------*/

contract Chainlink_FetchPricesWithCommonDenominator_Test is ChainlinkTest {

    address credAddr = makeAddr("credAddr");
    address collAddr = makeAddr("collAddr");


    function test_shouldFetchCreditAndCollateralPrices() external {
        vm.expectCall(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, credAddr, ChainlinkDenominations.USD)
        );
        vm.expectCall(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, collAddr, ChainlinkDenominations.USD)
        );

        chainlink.fetchPricesWithCommonDenominator(feedRegistry, credAddr, collAddr);
    }

    function test_shouldFetchETHPriceInUSD_whenCreditPriceInUSD_whenCollateralPriceNotInUSD() external {
        vm.mockCallRevert(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, credAddr, ChainlinkDenominations.ETH),
            "whatnot"
        );
        vm.mockCallRevert(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, collAddr, ChainlinkDenominations.USD),
            "whatnot"
        );

        vm.expectCall(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, ChainlinkDenominations.ETH, ChainlinkDenominations.USD)
        );

        chainlink.fetchPricesWithCommonDenominator(feedRegistry, credAddr, collAddr);
    }

    function test_shouldFetchETHPriceInUSD_whenCreditPriceNotInUSD_whenCollateralPriceInUSD() external {
        vm.mockCallRevert(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, credAddr, ChainlinkDenominations.USD),
            "whatnot"
        );
        vm.mockCallRevert(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, collAddr, ChainlinkDenominations.ETH),
            "whatnot"
        );

        vm.expectCall(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, ChainlinkDenominations.ETH, ChainlinkDenominations.USD)
        );

        chainlink.fetchPricesWithCommonDenominator(feedRegistry, credAddr, collAddr);
    }

    function test_shouldNotFetchETHPriceInUSD_whenCreditPriceInUSD_whenCollateralPriceInUSD() external {
        vm.mockCallRevert(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, credAddr, ChainlinkDenominations.ETH),
            "whatnot"
        );
        vm.mockCallRevert(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, collAddr, ChainlinkDenominations.ETH),
            "whatnot"
        );

        vm.expectCall(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, ChainlinkDenominations.ETH, ChainlinkDenominations.USD),
            0
        );

        chainlink.fetchPricesWithCommonDenominator(feedRegistry, credAddr, collAddr);
    }

    function test_shouldNotFetchETHPriceInUSD_whenCreditPriceInETH_whenCollateralPriceInETH() external {
        vm.mockCallRevert(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, credAddr, ChainlinkDenominations.USD),
            "whatnot"
        );
        vm.mockCallRevert(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, collAddr, ChainlinkDenominations.USD),
            "whatnot"
        );

        vm.expectCall(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, ChainlinkDenominations.ETH, ChainlinkDenominations.USD),
            0
        );

        chainlink.fetchPricesWithCommonDenominator(feedRegistry, credAddr, collAddr);
    }

    function test_shouldFail_whenNoCommonDenominator() external {
        vm.mockCallRevert(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, credAddr, ChainlinkDenominations.ETH),
            "whatnot"
        );
        vm.mockCallRevert(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, collAddr, ChainlinkDenominations.USD),
            "whatnot"
        );
        vm.mockCallRevert(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, ChainlinkDenominations.ETH, ChainlinkDenominations.USD),
            "whatnot"
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Chainlink.ChainlinkFeedCommonDenominatorNotFound.selector, credAddr, collAddr
            )
        );
        chainlink.fetchPricesWithCommonDenominator(feedRegistry, credAddr, collAddr);
    }

    function test_shouldScaleCreditDecimalsUp_whenCollateralHasBiggerDecimals() external {
        address credAggregator = makeAddr("credAggregator");
        _mockFeed(credAggregator, credAddr, ChainlinkDenominations.USD);
        _mockLastRoundData(credAggregator, 1e6, block.timestamp);
        _mockFeedDecimals(credAggregator, 6);

        address collAggregator = makeAddr("collAggregator");
        _mockFeed(collAggregator, collAddr, ChainlinkDenominations.USD);
        _mockLastRoundData(collAggregator, 1e18, block.timestamp);
        _mockFeedDecimals(collAggregator, 18);

        (uint256 credPrice, uint256 collPrice)
            = chainlink.fetchPricesWithCommonDenominator(feedRegistry, credAddr, collAddr);

        assertEq(credPrice, 1e18);
        assertEq(collPrice, 1e18);
    }

    function test_shouldScaleCollateralDecimalsUp_whenCreditHasBiggerDecimals() external {
        address credAggregator = makeAddr("credAggregator");
        _mockFeed(credAggregator, credAddr, ChainlinkDenominations.USD);
        _mockLastRoundData(credAggregator, 1e18, block.timestamp);
        _mockFeedDecimals(credAggregator, 18);

        address collAggregator = makeAddr("collAggregator");
        _mockFeed(collAggregator, collAddr, ChainlinkDenominations.USD);
        _mockLastRoundData(collAggregator, 1e6, block.timestamp);
        _mockFeedDecimals(collAggregator, 6);

        (uint256 credPrice, uint256 collPrice)
            = chainlink.fetchPricesWithCommonDenominator(feedRegistry, credAddr, collAddr);

        assertEq(credPrice, 1e18);
        assertEq(collPrice, 1e18);
    }

}


/*----------------------------------------------------------*|
|*  # FIND PRICE                                            *|
|*----------------------------------------------------------*/

contract Chainlink_FindPrice_Test is ChainlinkTest {

    function testFuzz_shouldFetchUSDPrice_whenAvailable(uint256 _price, uint8 _decimals) external {
        _price = bound(_price, 0, uint256(type(int256).max));

        _mockLastRoundData(aggregator, int256(_price), 1);
        _mockFeedDecimals(aggregator, _decimals);

        vm.expectCall(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, asset, ChainlinkDenominations.USD),
            1
        );
        vm.expectCall(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, asset, ChainlinkDenominations.ETH),
            0
        );
        vm.expectCall(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, asset, ChainlinkDenominations.BTC),
            0
        );

        (uint256 price, uint8 decimals, address denominator) = Chainlink.findPrice(feedRegistry, asset);
        assertEq(price, _price);
        assertEq(decimals, _decimals);
        assertEq(denominator, ChainlinkDenominations.USD);
    }

    function testFuzz_shouldFetchETHPrice_whenUSDNotAvailable(uint256 _price, uint8 _decimals) external {
        _price = bound(_price, 0, uint256(type(int256).max));

        _mockLastRoundData(aggregator, int256(_price), 1);
        _mockFeedDecimals(aggregator, _decimals);
        vm.mockCallRevert(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, asset, ChainlinkDenominations.USD),
            "whatnot"
        );

        vm.expectCall(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, asset, ChainlinkDenominations.USD),
            1
        );
        vm.expectCall(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, asset, ChainlinkDenominations.ETH),
            1
        );
        vm.expectCall(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, asset, ChainlinkDenominations.BTC),
            0
        );

        (uint256 price, uint8 decimals, address denominator) = chainlink.findPrice(feedRegistry, asset);
        assertEq(price, _price);
        assertEq(decimals, _decimals);
        assertEq(denominator, ChainlinkDenominations.ETH);
    }

    function testFuzz_shouldFetchBTCPrice_whenUSDNotAvailable_whenETHNotAvailable(uint256 _price, uint8 _decimals) external {
        _price = bound(_price, 0, uint256(type(int256).max));

        _mockLastRoundData(aggregator, int256(_price), 1);
        _mockFeedDecimals(aggregator, _decimals);
        vm.mockCallRevert(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, asset, ChainlinkDenominations.USD),
            "whatnot"
        );
        vm.mockCallRevert(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, asset, ChainlinkDenominations.ETH),
            "whatnot"
        );

        vm.expectCall(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, asset, ChainlinkDenominations.USD),
            1
        );
        vm.expectCall(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, asset, ChainlinkDenominations.ETH),
            1
        );
        vm.expectCall(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, asset, ChainlinkDenominations.BTC),
            1
        );

        (uint256 price, uint8 decimals, address denominator) = Chainlink.findPrice(feedRegistry, asset);
        assertEq(price, _price);
        assertEq(decimals, _decimals);
        assertEq(denominator, ChainlinkDenominations.BTC);
    }

    function test_shouldFail_whenUSDNotAvailable_whenETHNotAvailable_whenBTCNotAvailable() external {
        vm.mockCallRevert(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, asset, ChainlinkDenominations.USD),
            "whatnot"
        );
        vm.mockCallRevert(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, asset, ChainlinkDenominations.ETH),
            "whatnot"
        );
        vm.mockCallRevert(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, asset, ChainlinkDenominations.BTC),
            "whatnot"
        );

        vm.expectRevert(abi.encodeWithSelector(Chainlink.ChainlinkFeedNotFound.selector, asset));
        chainlink.findPrice(feedRegistry, asset);
    }

}


/*----------------------------------------------------------*|
|*  # FETCH PRICE                                           *|
|*----------------------------------------------------------*/

contract Chainlink_FetchPrice_Test is ChainlinkTest {

    address denominator = makeAddr("denominator");

    function testFuzz_shouldGetFeedFromRegistry(address _asset, address _denominator) external {
        vm.expectCall(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, _asset, _denominator)
        );

        chainlink.fetchPrice(feedRegistry, _asset, _denominator);
    }

    function test_shouldReturnFalse_whenAggregatorNotRegistered() external {
        vm.mockCallRevert(
            address(feedRegistry),
            abi.encodeWithSelector(IChainlinkFeedRegistryLike.getFeed.selector, asset, denominator),
            "whatnot"
        );

        (bool success, uint256 price, uint8 decimals) = chainlink.fetchPrice(feedRegistry, asset, denominator);
        assertFalse(success);
        assertEq(price, 0);
        assertEq(decimals, 0);
    }

    function test_shouldFail_whenNegativePrice() external {
        _mockLastRoundData(aggregator, -1, 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                Chainlink.ChainlinkFeedReturnedNegativePrice.selector, asset, denominator, -1
            )
        );
        chainlink.fetchPrice(feedRegistry, asset, denominator);
    }

    function test_shouldFail_whenPriceTooOld() external {
        _mockLastRoundData(aggregator, 1, 1);

        vm.warp(Chainlink.MAX_CHAINLINK_FEED_PRICE_AGE + 2);

        vm.expectRevert(
            abi.encodeWithSelector(
                Chainlink.ChainlinkFeedPriceTooOld.selector, asset, 1
            )
        );
        chainlink.fetchPrice(feedRegistry, asset, denominator);
    }

    function testFuzz_shouldReturnPriceAndDecimals(uint256 _price, uint8 _decimals) external {
        _price = bound(_price, 0, uint256(type(int256).max));

        _mockFeedDecimals(aggregator, _decimals);
        _mockLastRoundData(aggregator, int256(_price), 1);

        (bool success, uint256 price, uint8 decimals) = chainlink.fetchPrice(feedRegistry, asset, denominator);

        assertTrue(success);
        assertEq(price, _price);
        assertEq(decimals, _decimals);
    }

}


/*----------------------------------------------------------*|
|*  # CONVERT PRICE DENOMINATOR                             *|
|*----------------------------------------------------------*/

contract Chainlink_ConvertPriceDenominator_Test is ChainlinkTest {

    address oDenominator = makeAddr("originalDenominator");
    address nDenominator = makeAddr("newDenominator");

    function test_shouldFetchConverterPriceFeed() external {
        vm.expectCall(
            address(feedRegistry),
            abi.encodeWithSelector(
                IChainlinkFeedRegistryLike.getFeed.selector, nDenominator, oDenominator
            )
        );

        chainlink.convertPriceDenominator(feedRegistry, 1e18, 18, oDenominator, nDenominator);
    }

    function testFuzz_shouldReturnSameValues_whenFailedToFetchPrice(uint256 nPrice, uint8 nDecimals) external {
        vm.mockCallRevert(
            address(feedRegistry),
            abi.encodeWithSelector(
                IChainlinkFeedRegistryLike.getFeed.selector, nDenominator, oDenominator
            ),
            "whatnot"
        );

        (bool success, uint256 price, uint8 decimals)
            = chainlink.convertPriceDenominator(feedRegistry, nPrice, nDecimals, oDenominator, nDenominator);

        assertFalse(success);
        assertEq(price, nPrice);
        assertEq(decimals, nDecimals);
    }

    function testFuzz_shouldScaleToBiggerDecimals(uint8 nDecimals, uint8 feedDecimals) external {
        feedDecimals = uint8(bound(feedDecimals, 0, 70));
        nDecimals = uint8(bound(nDecimals, 0, 70));
        uint8 resultDecimals = uint8(Math.max(nDecimals, feedDecimals));

        _mockLastRoundData(aggregator, int256(10 ** feedDecimals), 1);
        _mockFeedDecimals(aggregator, feedDecimals);

        (, uint256 price, uint8 decimals)
            = chainlink.convertPriceDenominator(feedRegistry, 10 ** nDecimals, nDecimals, oDenominator, nDenominator);

        assertEq(price, 10 ** resultDecimals);
        assertEq(decimals, resultDecimals);
    }

    function test_shouldConvertPrice() external {
        _mockFeedDecimals(aggregator, 8);

        _mockLastRoundData(aggregator, 3000e8, 1);
        (, uint256 price, uint8 decimals) = chainlink.convertPriceDenominator(feedRegistry, 6000e8, 8, oDenominator, nDenominator);
        assertEq(price, 2e8);

        _mockLastRoundData(aggregator, 500e8, 1);
        (, price, decimals) = chainlink.convertPriceDenominator(feedRegistry, 100e8, 8, oDenominator, nDenominator);
        assertEq(price, 0.2e8);

        _mockLastRoundData(aggregator, 5000e8, 1);
        (, price, decimals) = chainlink.convertPriceDenominator(feedRegistry, 1e8, 8, oDenominator, nDenominator);
        assertEq(price, 0.0002e8);
    }

    function test_shouldReturnSuccess() external {
        (bool success,,) = chainlink.convertPriceDenominator(feedRegistry, 1e18, 18, oDenominator, nDenominator);
        assertTrue(success);
    }

}


/*----------------------------------------------------------*|
|*  # SCALE PRICE                                           *|
|*----------------------------------------------------------*/

contract Chainlink_ScalePrice_Test is ChainlinkTest {

    function test_shouldUpdateValueDecimals() external {
        assertEq(chainlink.scalePrice(1e18, 18, 19), 1e19);
        assertEq(chainlink.scalePrice(5e18, 18, 17), 5e17);
        assertEq(chainlink.scalePrice(3319200, 3, 1), 33192);
        assertEq(chainlink.scalePrice(0, 1, 10), 0);
    }

}
