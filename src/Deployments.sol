// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { stdJson } from "forge-std/StdJson.sol";
import { CommonBase } from "forge-std/Base.sol";

import { MultiTokenCategoryRegistry } from "MultiToken/MultiTokenCategoryRegistry.sol";

import { Strings } from "openzeppelin/utils/Strings.sol";

import { PWNConfig } from "pwn/config/PWNConfig.sol";
import { PWNHub } from "pwn/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/hub/PWNHubTags.sol";
import { IChainlinkFeedRegistryLike } from "pwn/interfaces/IChainlinkFeedRegistryLike.sol";
import { IPWNDeployer } from "pwn/interfaces/IPWNDeployer.sol";
import { PWNSimpleLoan } from "pwn/loan/terms/simple/loan/PWNSimpleLoan.sol";
import { PWNSimpleLoanDutchAuctionProposal } from "pwn/loan/terms/simple/proposal/PWNSimpleLoanDutchAuctionProposal.sol";
import { PWNSimpleLoanElasticChainlinkProposal } from "pwn/loan/terms/simple/proposal/PWNSimpleLoanElasticChainlinkProposal.sol";
import { PWNSimpleLoanElasticProposal } from "pwn/loan/terms/simple/proposal/PWNSimpleLoanElasticProposal.sol";
import { PWNSimpleLoanListProposal } from "pwn/loan/terms/simple/proposal/PWNSimpleLoanListProposal.sol";
import { PWNSimpleLoanSimpleProposal } from "pwn/loan/terms/simple/proposal/PWNSimpleLoanSimpleProposal.sol";
import { PWNSimpleLoanUniswapV3LPIndividualProposal } from "pwn/loan/terms/simple/proposal/PWNSimpleLoanUniswapV3LPIndividualProposal.sol";
import { PWNSimpleLoanUniswapV3LPSetProposal } from "pwn/loan/terms/simple/proposal/PWNSimpleLoanUniswapV3LPSetProposal.sol";
import { PWNLOAN } from "pwn/loan/token/PWNLOAN.sol";
import { PWNRevokedNonce } from "pwn/nonce/PWNRevokedNonce.sol";
import { PWNUtilizedCredit } from "pwn/utilized-credit/PWNUtilizedCredit.sol";


abstract contract Deployments is CommonBase {
    using stdJson for string;
    using Strings for uint256;

    string public deploymentsSubpath;

    uint256[] deployedChains;
    Deployment deployment;
    External externalAddrs;

    // Properties need to be in alphabetical order
    struct Deployment {
        address adminTimelock;
        MultiTokenCategoryRegistry categoryRegistry;
        IChainlinkFeedRegistryLike chainlinkFeedRegistry;
        PWNConfig config;
        PWNConfig configSingleton;
        address daoSafe;
        IPWNDeployer deployer;
        address deployerSafe;
        PWNHub hub;
        PWNLOAN loanToken;
        address protocolTimelock;
        PWNRevokedNonce revokedNonce;
        PWNSimpleLoan simpleLoan;
        PWNSimpleLoanDutchAuctionProposal simpleLoanDutchAuctionProposal;
        PWNSimpleLoanElasticChainlinkProposal simpleLoanElasticChainlinkProposal;
        PWNSimpleLoanElasticProposal simpleLoanElasticProposal;
        PWNSimpleLoanListProposal simpleLoanListProposal;
        PWNSimpleLoanSimpleProposal simpleLoanSimpleProposal;
        PWNSimpleLoanUniswapV3LPIndividualProposal simpleLoanUniswapV3LPIndividualProposal;
        PWNSimpleLoanUniswapV3LPSetProposal simpleLoanUniswapV3LPSetProposal;
        PWNUtilizedCredit utilizedCredit;
    }

    struct External {
        address chainlinkL2SequencerUptimeFeed;
        address dao;
        address uniswapV3Factory;
        address uniswapV3NFTPositionManager;
        address weth;
    }


    function _loadDeployedAddresses() internal {
        string memory root = vm.projectRoot();

        string memory externalJson = vm.readFile(string.concat(root, deploymentsSubpath, "/deployments/external/external.json"));
        bytes memory rawExternal = externalJson.parseRaw(string.concat(".chains.", block.chainid.toString()));
        externalAddrs = abi.decode(rawExternal, (External));

        string memory deploymentsJson = vm.readFile(string.concat(root, deploymentsSubpath, "/deployments/v1.4.json"));
        bytes memory rawDeployedChains = deploymentsJson.parseRaw(".deployedChains");
        deployedChains = abi.decode(rawDeployedChains, (uint256[]));

        if (_contains(deployedChains, block.chainid)) {
            bytes memory rawDeployment = deploymentsJson.parseRaw(string.concat(".chains.", block.chainid.toString()));
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
