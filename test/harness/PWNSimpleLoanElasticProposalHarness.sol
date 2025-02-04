// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import {
    PWNSimpleLoanElasticProposal
} from "pwn/loan/terms/simple/proposal/PWNSimpleLoanElasticProposal.sol";


contract PWNSimpleLoanElasticProposalHarness is PWNSimpleLoanElasticProposal {

    constructor(
        address _hub,
        address _revokedNonce,
        address _config,
        address _utilizedCredit
    ) PWNSimpleLoanElasticProposal(_hub, _revokedNonce, _config, _utilizedCredit) {}


    function exposed_erc712EncodeProposal(Proposal memory proposal) external pure returns (bytes memory) {
        return _erc712EncodeProposal(proposal);
    }

}
