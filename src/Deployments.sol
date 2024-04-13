// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/StdJson.sol";
import "forge-std/Base.sol";

import { IMultiTokenCategoryRegistry } from "MultiToken/interfaces/IMultiTokenCategoryRegistry.sol";

import { Strings } from "openzeppelin-contracts/contracts/utils/Strings.sol";

import { PWNConfig } from "@pwn/config/PWNConfig.sol";
import { IPWNDeployer } from "@pwn/deployer/IPWNDeployer.sol";
import { PWNHub } from "@pwn/hub/PWNHub.sol";
import { PWNHubTags } from "@pwn/hub/PWNHubTags.sol";
import { PWNSimpleLoan } from "@pwn/loan/terms/simple/loan/PWNSimpleLoan.sol";
import { PWNSimpleLoanDutchAuctionProposal } from "@pwn/loan/terms/simple/proposal/PWNSimpleLoanDutchAuctionProposal.sol";
import { PWNSimpleLoanFungibleProposal } from "@pwn/loan/terms/simple/proposal/PWNSimpleLoanFungibleProposal.sol";
import { PWNSimpleLoanListProposal } from "@pwn/loan/terms/simple/proposal/PWNSimpleLoanListProposal.sol";
import { PWNSimpleLoanSimpleProposal } from "@pwn/loan/terms/simple/proposal/PWNSimpleLoanSimpleProposal.sol";
import { PWNLOAN } from "@pwn/loan/token/PWNLOAN.sol";
import { PWNRevokedNonce } from "@pwn/nonce/PWNRevokedNonce.sol";


abstract contract Deployments is CommonBase {
    using stdJson for string;
    using Strings for uint256;

    uint256[] deployedChains;
    Deployment deployment;

    // Properties need to be in alphabetical order
    struct Deployment {
        address adminTimelock;
        IMultiTokenCategoryRegistry categoryRegistry;
        PWNConfig config;
        PWNConfig configSingleton;
        address dao;
        address daoSafe;
        IPWNDeployer deployer;
        address deployerSafe;
        PWNHub hub;
        PWNLOAN loanToken;
        address protocolSafe;
        address protocolTimelock;
        PWNRevokedNonce revokedNonce;
        PWNSimpleLoan simpleLoan;
        PWNSimpleLoanDutchAuctionProposal simpleLoanDutchAuctionProposal;
        PWNSimpleLoanFungibleProposal simpleLoanFungibleProposal;
        PWNSimpleLoanListProposal simpleLoanListProposal;
        PWNSimpleLoanSimpleProposal simpleLoanSimpleProposal;
    }


    function _loadDeployedAddresses() internal {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/latest.json");
        string memory json = vm.readFile(path);
        bytes memory rawDeployedChains = json.parseRaw(".deployedChains");
        deployedChains = abi.decode(rawDeployedChains, (uint256[]));

        if (_contains(deployedChains, block.chainid)) {
            bytes memory rawDeployment = json.parseRaw(string.concat(".chains.", block.chainid.toString()));
            deployment = abi.decode(rawDeployment, (Deployment));
        } else {
            _protocolNotDeployedOnSelectedChain();
        }
    }

    function _contains(uint256[] storage array, uint256 value) private view returns (bool) {
        for (uint256 i; i < array.length; ++i)
            if (array[i] == value)
                return true;

        return false;
    }

    function _protocolNotDeployedOnSelectedChain() internal virtual {
        // Override
    }

}
