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
import { PWNSimpleLoanListOffer } from "@pwn/loan/terms/simple/proposal/offer/PWNSimpleLoanListOffer.sol";
import { PWNSimpleLoanSimpleProposal } from "@pwn/loan/terms/simple/proposal/PWNSimpleLoanSimpleProposal.sol";
import { PWNLOAN } from "@pwn/loan/token/PWNLOAN.sol";
import { PWNRevokedNonce } from "@pwn/nonce/PWNRevokedNonce.sol";
import { StateFingerprintComputerRegistry } from "@pwn/state-fingerprint/StateFingerprintComputerRegistry.sol";


abstract contract Deployments is CommonBase {
    using stdJson for string;
    using Strings for uint256;

    uint256[] deployedChains;
    Deployment deployment;

    // Properties need to be in alphabetical order
    struct Deployment {
        IMultiTokenCategoryRegistry categoryRegistry;
        PWNConfig config;
        PWNConfig configSingleton;
        address dao;
        address daoSafe;
        IPWNDeployer deployer;
        address deployerSafe;
        address feeCollector;
        PWNHub hub;
        PWNLOAN loanToken;
        address productTimelock;
        address protocolSafe;
        address protocolTimelock;
        PWNRevokedNonce revokedNonce;
        PWNSimpleLoan simpleLoan;
        PWNSimpleLoanListOffer simpleLoanListOffer;
        StateFingerprintComputerRegistry stateFingerprintComputerRegistry;
    }

    address dao;

    address productTimelock;
    address protocolTimelock;

    address deployerSafe;
    address protocolSafe;
    address daoSafe;
    address feeCollector;

    IMultiTokenCategoryRegistry categoryRegistry;
    StateFingerprintComputerRegistry stateFingerprintComputerRegistry;

    IPWNDeployer deployer;
    PWNHub hub;
    PWNConfig configSingleton;
    PWNConfig config;
    PWNLOAN loanToken;
    PWNSimpleLoan simpleLoan;
    PWNRevokedNonce revokedNonce;
    PWNSimpleLoanListOffer simpleLoanListOffer;


    function _loadDeployedAddresses() internal {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments.json");
        string memory json = vm.readFile(path);
        bytes memory rawDeployedChains = json.parseRaw(".deployedChains");
        deployedChains = abi.decode(rawDeployedChains, (uint256[]));

        if (_contains(deployedChains, block.chainid)) {
            bytes memory rawDeployment = json.parseRaw(string.concat(".chains.", block.chainid.toString()));
            deployment = abi.decode(rawDeployment, (Deployment));

            dao = deployment.dao;
            productTimelock = deployment.productTimelock;
            protocolTimelock = deployment.protocolTimelock;
            deployerSafe = deployment.deployerSafe;
            protocolSafe = deployment.protocolSafe;
            daoSafe = deployment.daoSafe;
            feeCollector = deployment.feeCollector;
            deployer = deployment.deployer;
            hub = deployment.hub;
            configSingleton = deployment.configSingleton;
            config = deployment.config;
            loanToken = deployment.loanToken;
            simpleLoan = deployment.simpleLoan;
            revokedNonce = deployment.revokedNonce;
            simpleLoanListOffer = deployment.simpleLoanListOffer;
            stateFingerprintComputerRegistry = deployment.stateFingerprintComputerRegistry;
            categoryRegistry = deployment.categoryRegistry;
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
