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
    Deployment __d;
    External __e;
    CreationCode __cc;

    /// @dev Properties need to be in alphabetical order.
    struct Deployment {
        MultiTokenCategoryRegistry categoryRegistry;
        IChainlinkFeedRegistryLike chainlinkFeedRegistry;
        PWNConfig config;
        PWNConfig configSingleton;
        PWNHub hub;
        PWNLOAN loanToken;
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
        bytes simpleLoanDutchAuctionProposal_v1_1;
        bytes simpleLoanElasticChainlinkProposal_v1_0;
        bytes simpleLoanElasticProposal_v1_1;
        bytes simpleLoanListProposal_v1_3;
        bytes simpleLoanSimpleProposal_v1_3;
        bytes simpleLoan_v1_3;
        bytes utilizedCredit;
    }


    function _loadDeployedAddresses() internal {
        string memory root = vm.projectRoot();

        string memory creationJson = vm.readFile(string.concat(root, deploymentsSubpath, "/deployments/creation/creationCode.json"));
        bytes memory rawCreation = creationJson.parseRaw(".");
        __cc = abi.decode(rawCreation, (CreationCode));

        string memory externalJson = vm.readFile(string.concat(root, deploymentsSubpath, "/deployments/external/external.json"));
        bytes memory rawExternal = externalJson.parseRaw(string.concat(".", block.chainid.toString()));
        __e = abi.decode(rawExternal, (External));

        string memory deploymentsJson = vm.readFile(string.concat(root, deploymentsSubpath, "/deployments/protocol/v1.4.json"));
        bytes memory rawDeployment = deploymentsJson.parseRaw(string.concat(".", block.chainid.toString()));

        if (rawDeployment.length > 0) {
            __d = abi.decode(rawDeployment, (Deployment));
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
