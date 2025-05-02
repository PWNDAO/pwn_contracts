// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import {
    PWNSimpleLoanUniswapV3LPIndividualProposal
} from "pwn/core/proposal/PWNSimpleLoanUniswapV3LPIndividualProposal.sol";


contract PWNSimpleLoanUniswapV3LPIndividualProposalHarness is PWNSimpleLoanUniswapV3LPIndividualProposal {

    constructor(
        address _hub,
        address _revokedNonce,
        address _config,
        address _utilizedCredit,
        address _uniswapV3Factory,
        address _uniswapNFTPositionManager,
        address _chainlinkFeedRegistry,
        address _chainlinkL2SequencerUptimeFeed,
        address _weth
    ) PWNSimpleLoanUniswapV3LPIndividualProposal(
        _hub,
        _revokedNonce,
        _config,
        _utilizedCredit,
        _uniswapV3Factory,
        _uniswapNFTPositionManager,
        _chainlinkFeedRegistry,
        _chainlinkL2SequencerUptimeFeed,
        _weth
    ) {}


    function exposed_erc712EncodeProposal(Proposal memory proposal) external pure returns (bytes memory) {
        return _erc712EncodeProposal(proposal);
    }

}
