// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";


interface IPWNProposalAcceptanceHook {

    /** @dev Must return keccak of "PWNProposalAcceptanceHook.onProposalAcceptance"*/
    function onProposalAcceptance(
        address proposer,
        bytes calldata proposerData,
        address acceptor,
        bytes calldata acceptorData,
        MultiToken.Asset calldata collateral,
        address creditAddress,
        uint256 principal
    ) external returns (bytes32);

}
