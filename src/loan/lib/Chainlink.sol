// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Math } from "openzeppelin/utils/math/Math.sol";

import { IChainlinkAggregatorLike } from "pwn/interfaces/IChainlinkAggregatorLike.sol";
import { IChainlinkFeedRegistryLike } from "pwn/interfaces/IChainlinkFeedRegistryLike.sol";
import { ChainlinkDenominations } from "pwn/loan/lib/ChainlinkDenominations.sol";


library Chainlink {

    /**
     * @notice Maximum Chainlink feed price age.
     */
    uint256 public constant MAX_CHAINLINK_FEED_PRICE_AGE = 1 days;

    /**
     * @notice Grace period time for L2 Sequencer uptime feed.
     */
    uint256 public constant L2_GRACE_PERIOD = 10 minutes;

    /**
     * @notice Throw when Chainlink feed returns negative price.
     */
    error ChainlinkFeedReturnedNegativePrice(address asset, address denominator, int256 price);

    /**
     * @notice Throw when Chainlink feed for asset is not found.
     */
    error ChainlinkFeedNotFound(address asset);

    /**
     * @notice Throw when common denominator for credit and collateral assets is not found.
     */
    error ChainlinkFeedCommonDenominatorNotFound(address creditAsset, address collateralAsset);

    /**
     * @notice Throw when Chainlink feed price is too old.
     */
    error ChainlinkFeedPriceTooOld(address asset, uint256 updatedAt);

    /**
     * @notice Throw when L2 Sequencer uptime feed returns that the sequencer is down.
     */
    error L2SequencerDown();

    /**
     * @notice Throw when L2 Sequencer uptime feed grace period is not over.
     */
    error GracePeriodNotOver(uint256 timeSinceUp, uint256 gracePeriod);


    /**
     * @notice Checks the uptime status of the L2 sequencer.
     * @dev This function reverts if the sequencer is down or if the grace period is not over.
     * @param l2SequencerUptimeFeed The Chainlink aggregator contract that provides the sequencer uptime status.
     */
    function checkSequencerUptime(IChainlinkAggregatorLike l2SequencerUptimeFeed) internal view {
        if (address(l2SequencerUptimeFeed) != address(0)) {
            (, int256 answer, uint256 startedAt,,) = l2SequencerUptimeFeed.latestRoundData();
            if (answer == 1) {
                // sequencer is down
                revert L2SequencerDown();
            }

            uint256 timeSinceUp = block.timestamp - startedAt;
            if (timeSinceUp <= L2_GRACE_PERIOD) {
                // grace period is not over
                revert GracePeriodNotOver({ timeSinceUp: timeSinceUp, gracePeriod: L2_GRACE_PERIOD });
            }
        }
    }

    /**
     * @notice Fetches the prices of the credit and collateral assets with a common denominator.
     * @dev This function ensures that the prices of both assets are converted to the same denominator for comparison.
     * @param feedRegistry The Chainlink feed registry contract that provides the price feeds.
     * @param creditAsset The address of the credit asset.
     * @param collateralAsset The address of the collateral asset.
     * @return The prices of the credit assets with a common denominator.
     * @return The prices of the collateral assets with a common denominator.
     */
    function fetchPricesWithCommonDenominator(
        IChainlinkFeedRegistryLike feedRegistry,
        address creditAsset,
        address collateralAsset
    ) internal view returns (uint256, uint256) {
        // fetch asset prices
        (uint256 creditPrice, uint8 creditPriceDecimals, address creditDenominator)
            = findPrice(feedRegistry, creditAsset);
        (uint256 collateralPrice, uint8 collateralPriceDecimals, address collateralDenominator)
            = findPrice(feedRegistry, collateralAsset);

        // convert prices to the same denominator
        // Note: assume only USD, ETH, or BTC can be denominators
        if (creditDenominator != collateralDenominator) {

            // We can assume that most assets have price feed in USD. If not, we need to find common denominator.
            // Table below shows conversions between assets.
            //  -------------------------
            //  |     | USD | ETH | BTC |  <-- credit
            //  | USD |  X  | ETH | BTC |
            //  | ETH | ETH |  X  | ETH |
            //  | BTC | BTC | ETH |  X  |
            //  -------------------------
            //     ^ collateral
            //
            // For this to work, we need to have this price feeds: ETH/USD, ETH/BTC, BTC/USD.
            // This will cover most of the cases, where assets don't have price feed in USD.

            bool success = true;
            if (creditDenominator == ChainlinkDenominations.USD) {
                (success, creditPrice, creditPriceDecimals) = convertPriceDenominator({
                    feedRegistry: feedRegistry,
                    nominatorPrice: creditPrice,
                    nominatorDecimals: creditPriceDecimals,
                    originalDenominator: creditDenominator,
                    newDenominator: collateralDenominator
                });
            } else {
                (success, collateralPrice, collateralPriceDecimals) = convertPriceDenominator({
                    feedRegistry: feedRegistry,
                    nominatorPrice: collateralPrice,
                    nominatorDecimals: collateralPriceDecimals,
                    originalDenominator: collateralDenominator,
                    newDenominator: collateralDenominator == ChainlinkDenominations.USD
                        ? creditDenominator
                        : ChainlinkDenominations.ETH
                });
            }

            if (!success) {
                revert ChainlinkFeedCommonDenominatorNotFound({
                    creditAsset: creditAsset,
                    collateralAsset: collateralAsset
                });
            }
        }

        // scale prices to the higher decimals
        if (creditPriceDecimals > collateralPriceDecimals) {
            collateralPrice = scalePrice(collateralPrice, collateralPriceDecimals, creditPriceDecimals);
        } else if (creditPriceDecimals < collateralPriceDecimals) {
            creditPrice = scalePrice(creditPrice, creditPriceDecimals, collateralPriceDecimals);
        }

        return (creditPrice, collateralPrice);
    }

    /**
     * @notice Find price for an asset in USD, ETH, or BTC denominator.
     * @param asset Address of an asset.
     * @return price Price of an asset.
     * @return priceDecimals Decimals of the price.
     * @return denominator Address of a denominator asset.
     */
    function findPrice(IChainlinkFeedRegistryLike feedRegistry, address asset)
        internal
        view
        returns (uint256, uint8, address)
    {
        // fetch USD denominated price
        (bool success, uint256 price, uint8 priceDecimals) = fetchPrice(feedRegistry, asset, ChainlinkDenominations.USD);
        if (success) {
            return (price, priceDecimals, ChainlinkDenominations.USD);
        }

        // fetch ETH denominated price
        (success, price, priceDecimals) = fetchPrice(feedRegistry, asset, ChainlinkDenominations.ETH);
        if (success) {
            return (price, priceDecimals, ChainlinkDenominations.ETH);
        }

        // fetch BTC denominated price
        (success, price, priceDecimals) = fetchPrice(feedRegistry, asset, ChainlinkDenominations.BTC);
        if (success) {
            return (price, priceDecimals, ChainlinkDenominations.BTC);
        }

        // revert if asset doesn't have price denominated in USD, ETH, or BTC
        revert ChainlinkFeedNotFound({ asset: asset });
    }

    /**
     * @notice Fetch price from Chainlink feed.
     * @param asset Address of an asset.
     * @param denominator Address of a denominator asset.
     * @return success True if price was fetched successfully.
     * @return price Price of an asset.
     * @return decimals Decimals of a price.
     */
    function fetchPrice(IChainlinkFeedRegistryLike feedRegistry, address asset, address denominator)
        internal
        view
        returns (bool, uint256, uint8)
    {
        try feedRegistry.getFeed(asset, denominator) returns (IChainlinkAggregatorLike aggregator) {
            (, int256 price,, uint256 updatedAt,) = aggregator.latestRoundData();
            if (price < 0) {
                revert ChainlinkFeedReturnedNegativePrice({ asset: asset, denominator: denominator, price: price });
            }
            if (block.timestamp - updatedAt > MAX_CHAINLINK_FEED_PRICE_AGE) {
                revert ChainlinkFeedPriceTooOld({ asset: asset, updatedAt: updatedAt });
            }

            uint8 decimals = aggregator.decimals();
            return (true, uint256(price), decimals);
        } catch {
            return (false, 0, 0);
        }
    }

    /**
     * @notice Convert price denominator.
     * @param nominatorPrice Price of an asset denomination in `originalDenominator`.
     * @param nominatorDecimals Decimals of a price in `originalDenominator`.
     * @param originalDenominator Address of an original denominator asset.
     * @param newDenominator Address of a new denominator asset.
     * @return success True if conversion was successful.
     * @return nominatorPrice Price of an asset denomination in `newDenominator`.
     * @return nominatorDecimals Decimals of a price in `newDenominator`.
     */
    function convertPriceDenominator(
        IChainlinkFeedRegistryLike feedRegistry,
        uint256 nominatorPrice,
        uint8 nominatorDecimals,
        address originalDenominator,
        address newDenominator
    ) internal view returns (bool, uint256, uint8) {
        (bool success, uint256 price, uint8 priceDecimals) = fetchPrice({
            feedRegistry: feedRegistry, asset: newDenominator, denominator: originalDenominator
        });

        if (!success) {
            return (false, nominatorPrice, nominatorDecimals);
        }

        if (priceDecimals < nominatorDecimals) {
            price = scalePrice(price, priceDecimals, nominatorDecimals);
        } else if (priceDecimals > nominatorDecimals) {
            nominatorPrice = scalePrice(nominatorPrice, nominatorDecimals, priceDecimals);
            nominatorDecimals = priceDecimals;
        }
        nominatorPrice = Math.mulDiv(nominatorPrice, 10 ** nominatorDecimals, price);

        return (true, nominatorPrice, nominatorDecimals);
    }

    /**
     * @notice Scale price to new decimals.
     * @param price Price to be scaled.
     * @param priceDecimals Decimals of a price.
     * @param newDecimals New decimals.
     * @return Scaled price.
     */
    function scalePrice(uint256 price, uint8 priceDecimals, uint8 newDecimals) internal pure returns (uint256) {
        if (priceDecimals < newDecimals) {
            return price * 10 ** (newDecimals - priceDecimals);
        } else if (priceDecimals > newDecimals) {
            return price / 10 ** (priceDecimals - newDecimals);
        }
        return price;
    }

}
