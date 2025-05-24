// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { CommonBase } from "forge-std/Base.sol";

import { MultiTokenCategoryRegistry } from "MultiToken/MultiTokenCategoryRegistry.sol";

import { PWNConfig } from "pwn/config/PWNConfig.sol";
import { PWNHub } from "pwn/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/hub/PWNHubTags.sol";
import { IPWNDeployer } from "pwn/interfaces/IPWNDeployer.sol";
import { PWNLoan } from "pwn/loan/PWNLoan.sol";
import { PWNMortgageProposal } from "pwn/proposal/PWNMortgageProposal.sol";
import { PWNLOAN } from "pwn/token/PWNLOAN.sol";
import { PWNRevokedNonce } from "pwn/proposal/auxiliary/PWNRevokedNonce.sol";
import { PWNUtilizedCredit } from "pwn/proposal/auxiliary/PWNUtilizedCredit.sol";


abstract contract Deployments is CommonBase {

    Deployment __d;
    External __e;

    /// @dev Properties need to be in alphabetical order.
    struct Deployment {
        MultiTokenCategoryRegistry categoryRegistry;
        PWNConfig config;
        PWNConfig configSingleton;
        PWNHub hub;
        PWNLoan loan;
        PWNLOAN loanToken;
        PWNMortgageProposal mortgageProposal;
        PWNRevokedNonce revokedNonce;
        PWNUtilizedCredit utilizedCredit;
    }

    /// @dev Properties need to be in alphabetical order.
    struct External {
        address adminTimelock;
        address dao;
        address daoSafe;
        IPWNDeployer deployer;
        address deployerSafe;
        address protocolTimelock;
    }


    function _loadDeployedAddresses() internal {
        _protocolNotDeployedOnSelectedChain();
    }

    function _protocolNotDeployedOnSelectedChain() internal virtual {
        // Override
    }

}
