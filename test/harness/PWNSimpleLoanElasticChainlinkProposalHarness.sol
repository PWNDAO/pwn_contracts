// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { PWNSimpleLoanElasticChainlinkProposal } from "pwn/loan/terms/simple/proposal/PWNSimpleLoanElasticChainlinkProposal.sol";


contract PWNSimpleLoanElasticChainlinkProposalHarness is PWNSimpleLoanElasticChainlinkProposal {

    constructor(
        address _hub,
        address _revokedNonce,
        address _config,
        address _utilizedCredit,
        address _chainlinkFeedRegistry,
        address _l2sequencerUptimeFeed,
        address _weth
    ) PWNSimpleLoanElasticChainlinkProposal(
        _hub, _revokedNonce, _config, _utilizedCredit, _chainlinkFeedRegistry, _l2sequencerUptimeFeed, _weth
    ) {}


    function exposed_findPrice(address asset) external view returns (uint256, uint8, address) {
        return _findPrice(asset);
    }

    function exposed_fetchPrice(address asset, address denominator) external view returns (bool, uint256, uint8) {
        return _fetchPrice(asset, denominator);
    }

    function exposed_convertPriceDenominator(uint256 nominatorPrice, uint8 nominatorDecimals, address originalDenominator, address newDenominator) external view returns (bool, uint256, uint8) {
        return _convertPriceDenominator(nominatorPrice, nominatorDecimals, originalDenominator, newDenominator);
    }

    function exposed_scalePrice(uint256 price, uint8 priceDecimals, uint8 newDecimals) external pure returns (uint256) {
        return _scalePrice(price, priceDecimals, newDecimals);
    }

}
