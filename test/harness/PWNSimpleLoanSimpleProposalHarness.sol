// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import {
    PWNSimpleLoanSimpleProposal
} from "pwn/core/proposal/PWNSimpleLoanSimpleProposal.sol";


contract PWNSimpleLoanSimpleProposalHarness is PWNSimpleLoanSimpleProposal {

    constructor(
        address _hub,
        address _revokedNonce,
        address _config,
        address _utilizedCredit
    ) PWNSimpleLoanSimpleProposal(_hub, _revokedNonce, _config, _utilizedCredit) {}


    function exposed_erc712EncodeProposal(Proposal memory proposal) external pure returns (bytes memory) {
        return _erc712EncodeProposal(proposal);
    }

}
