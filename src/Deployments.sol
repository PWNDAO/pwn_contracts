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
import { PWNLoan } from "pwn/loan/PWNLoan.sol";
import { PWNDurationDefaultModule } from "pwn/loan/module/default/PWNDurationDefaultModule.sol";
import { PWNStableInterestModule } from "pwn/loan/module/interest/PWNStableInterestModule.sol";
import { PWNSimpleProposal } from "pwn/proposal/PWNSimpleProposal.sol";
import { PWNListProposal } from "pwn/proposal/PWNListProposal.sol";
import { PWNElasticChainlinkProposal } from "pwn/proposal/PWNElasticChainlinkProposal.sol";
import { PWNElasticProposal } from "pwn/proposal/PWNElasticProposal.sol";
import { PWNDutchAuctionProposal } from "pwn/proposal/PWNDutchAuctionProposal.sol";
import { PWNUniswapV3LPIndividualProposal } from "pwn/proposal/PWNUniswapV3LPIndividualProposal.sol";
import { PWNUniswapV3LPSetProposal } from "pwn/proposal/PWNUniswapV3LPSetProposal.sol";
import { PWNLOAN } from "pwn/token/PWNLOAN.sol";
import { PWNRevokedNonce } from "pwn/proposal/auxiliary/PWNRevokedNonce.sol";
import { PWNUtilizedCredit } from "pwn/proposal/auxiliary/PWNUtilizedCredit.sol";


abstract contract Deployments is CommonBase {
    using stdJson for string;
    using Strings for uint256;

    string public deploymentsSubpath;

    bool wasPredeployedOnFork;
    Deployment __d;
    External __e;
    CreationCode __cc;

    /// @dev Properties need to be in alphabetical order.
    struct Deployment {
        MultiTokenCategoryRegistry categoryRegistry;
        IChainlinkFeedRegistryLike chainlinkFeedRegistry;
        PWNConfig config;
        PWNConfig configSingleton;
        PWNDurationDefaultModule durationDefaultModule;
        PWNDutchAuctionProposal dutchAuctionProposal;
        PWNElasticChainlinkProposal elasticChainlinkProposal;
        PWNElasticProposal elasticProposal;
        PWNHub hub;
        PWNListProposal listProposal;
        PWNLoan loan;
        PWNLOAN loanToken;
        PWNRevokedNonce revokedNonce;
        PWNSimpleProposal simpleProposal;
        PWNStableInterestModule stableInterestModule;
        PWNUniswapV3LPIndividualProposal uniswapV3LPIndividualProposal;
        PWNUniswapV3LPSetProposal uniswapV3LPSetProposal;
        PWNUtilizedCredit utilizedCredit;
    }

    /// @dev Properties need to be in alphabetical order.
    struct External {
        address adminTimelock;
        address chainlinkL2SequencerUptimeFeed;
        address dao;
        address daoSafe;
        IPWNDeployer deployer;
        address deployerSafe;
        bool isL2;
        address protocolTimelock;
        address uniswapV3Factory;
        address uniswapV3NFTPositionManager;
        address weth;
    }

    /// @dev Properties need to be in alphabetical order.
    struct CreationCode {
        bytes categoryRegistry;
        bytes chainlinkFeedRegistry;
        bytes config;
        bytes configSingleton_v1_2;
        bytes hub;
        bytes loanToken;
        bytes revokedNonce;
        bytes utilizedCredit;
        // todo: add loan & proposals
    }


    function _loadDeployedAddresses() internal {
        string memory root = vm.projectRoot();

        string memory creationJson = vm.readFile(string.concat(root, deploymentsSubpath, "/deployments/creation/creationCode.json"));
        bytes memory rawCreation = creationJson.parseRaw(".");
        __cc = abi.decode(rawCreation, (CreationCode));

        string memory externalJson = vm.readFile(string.concat(root, deploymentsSubpath, "/deployments/external/external.json"));
        bytes memory rawExternal = externalJson.parseRaw(string.concat(".", block.chainid.toString()));
        __e = abi.decode(rawExternal, (External));

        string memory deploymentsJson = vm.readFile(string.concat(root, deploymentsSubpath, "/deployments/protocol/v1.5.json"));
        bytes memory rawDeployment = deploymentsJson.parseRaw(string.concat(".", block.chainid.toString()));

        if (rawDeployment.length > 0) {
            wasPredeployedOnFork = true;
            __d = abi.decode(rawDeployment, (Deployment));
        } else {
            wasPredeployedOnFork = false;
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
