// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import {
    Chainlink,
    IChainlinkFeedRegistryLike,
    IChainlinkAggregatorLike,
    ChainlinkDenominations
} from "pwn/loan/lib/Chainlink.sol";


contract ChainlinkHarness {

    function checkSequencerUptime(IChainlinkAggregatorLike l2SequencerUptimeFeed) external view {
        return Chainlink.checkSequencerUptime(l2SequencerUptimeFeed);
    }

    function fetchPricesWithCommonDenominator(
        IChainlinkFeedRegistryLike feedRegistry,
        address creditAsset,
        address collateralAsset
    ) external view returns (uint256, uint256) {
        return Chainlink.fetchPricesWithCommonDenominator(feedRegistry, creditAsset, collateralAsset);
    }

    function findPrice(IChainlinkFeedRegistryLike feedRegistry, address asset)
        external
        view
        returns (uint256, uint8, address)
    {
        return Chainlink.findPrice(feedRegistry, asset);
    }

    function fetchPrice(IChainlinkFeedRegistryLike feedRegistry, address asset, address denominator)
        external
        view
        returns (bool, uint256, uint8)
    {
        return Chainlink.fetchPrice(feedRegistry, asset, denominator);
    }

    function convertPriceDenominator(
        IChainlinkFeedRegistryLike feedRegistry,
        uint256 nominatorPrice,
        uint8 nominatorDecimals,
        address originalDenominator,
        address newDenominator
    ) external view returns (bool, uint256, uint8) {
        return Chainlink.convertPriceDenominator(
            feedRegistry, nominatorPrice, nominatorDecimals, originalDenominator, newDenominator
        );
    }

    function scalePrice(uint256 price, uint8 priceDecimals, uint8 newDecimals) external pure returns (uint256) {
        return Chainlink.scalePrice(price, priceDecimals, newDecimals);
    }

}
