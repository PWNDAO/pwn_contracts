// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import {
    PWNElasticProposal
} from "pwn/proposal/PWNElasticProposal.sol";


contract PWNElasticProposalHarness is PWNElasticProposal {

    constructor(
        address _hub,
        address _revokedNonce,
        address _config,
        address _utilizedCredit,
        address _interestModule,
        address _defaultModule
    ) PWNElasticProposal(_hub, _revokedNonce, _config, _utilizedCredit, _interestModule, _defaultModule) {}


    function exposed_erc712EncodeProposal(Proposal memory proposal) external pure returns (bytes memory) {
        return _erc712EncodeProposal(proposal);
    }

}
