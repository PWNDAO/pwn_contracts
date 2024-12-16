// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import {
    PWNSimpleLoanElasticChainlinkProposal
} from "pwn/loan/terms/simple/proposal/PWNSimpleLoanElasticChainlinkProposal.sol";


contract PWNSimpleLoanElasticChainlinkProposalHarness is PWNSimpleLoanElasticChainlinkProposal {

    constructor(
        address _hub,
        address _revokedNonce,
        address _config,
        address _utilizedCredit,
        address _chainlinkFeedRegistry,
        address _l2SequencerUptimeFeed,
        address _weth
    ) PWNSimpleLoanElasticChainlinkProposal(
        _hub,
        _revokedNonce,
        _config,
        _utilizedCredit,
        _chainlinkFeedRegistry,
        _l2SequencerUptimeFeed,
        _weth
    ) {}


    function exposed_erc712EncodeProposal(Proposal memory proposal) external pure returns (bytes memory) {
        return _erc712EncodeProposal(proposal);
    }

}
