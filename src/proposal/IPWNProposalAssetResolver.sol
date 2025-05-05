// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";


interface IPWNProposalAssetResolver {

    function resolveAssets(
        bytes calldata proposerData,
        bytes calldata acceptorData
    ) external view returns (MultiToken.Asset memory collatera, address credit, uint256 amount);

}
