// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { IChainlinkAggregatorLike } from "pwn/interfaces/IChainlinkAggregatorLike.sol";


/**
 * @title IChainlinkFeedRegistryLike
 * @notice Chainlink Feed Registry Interface.
 */
interface IChainlinkFeedRegistryLike {

    /**
     * @notice Get the Chainlink aggregator for a given base and quote asset.
     * @param base Base asset address.
     * @param quote Quote asset address.
     * @return aggregator Chainlink aggregator for the given base and quote asset.
     */
    function getFeed(address base, address quote) external view returns (IChainlinkAggregatorLike aggregator);

}
