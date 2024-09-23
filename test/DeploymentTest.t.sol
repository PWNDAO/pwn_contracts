// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import { TransparentUpgradeableProxy } from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

import {
    Deployments,
    PWNConfig,
    IPWNDeployer,
    PWNHub,
    PWNHubTags,
    PWNSimpleLoan,
    PWNSimpleLoanDutchAuctionProposal,
    PWNSimpleLoanElasticChainlinkProposal,
    PWNSimpleLoanElasticProposal,
    PWNSimpleLoanListProposal,
    PWNSimpleLoanSimpleProposal,
    PWNLOAN,
    PWNRevokedNonce,
    PWNUtilizedCredit,
    MultiTokenCategoryRegistry
} from "pwn/Deployments.sol";


abstract contract DeploymentTest is Deployments, Test {

    function setUp() public virtual {
        _loadDeployedAddresses();
    }

    function _protocolNotDeployedOnSelectedChain() internal override {
        deployment.protocolTimelock = makeAddr("protocolTimelock");
        deployment.adminTimelock = makeAddr("adminTimelock");
        deployment.daoSafe = makeAddr("daoSafe");

        // Deploy category registry
        vm.prank(deployment.protocolTimelock);
        deployment.categoryRegistry = new MultiTokenCategoryRegistry();

        // Deploy protocol
        deployment.configSingleton = new PWNConfig();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(deployment.configSingleton),
            deployment.adminTimelock,
            abi.encodeWithSignature("initialize(address,uint16,address)", deployment.protocolTimelock, 0, deployment.daoSafe)
        );
        deployment.config = PWNConfig(address(proxy));

        vm.prank(deployment.protocolTimelock);
        deployment.hub = new PWNHub();

        deployment.revokedNonce = new PWNRevokedNonce(address(deployment.hub), PWNHubTags.NONCE_MANAGER);
        deployment.utilizedCredit = new PWNUtilizedCredit(address(deployment.hub), PWNHubTags.LOAN_PROPOSAL);

        deployment.loanToken = new PWNLOAN(address(deployment.hub));
        deployment.simpleLoan = new PWNSimpleLoan(
            address(deployment.hub),
            address(deployment.loanToken),
            address(deployment.config),
            address(deployment.revokedNonce),
            address(deployment.categoryRegistry)
        );

        deployment.simpleLoanSimpleProposal = new PWNSimpleLoanSimpleProposal(
            address(deployment.hub),
            address(deployment.revokedNonce),
            address(deployment.config),
            address(deployment.utilizedCredit)
        );
        deployment.simpleLoanListProposal = new PWNSimpleLoanListProposal(
            address(deployment.hub),
            address(deployment.revokedNonce),
            address(deployment.config),
            address(deployment.utilizedCredit)
        );
        deployment.simpleLoanElasticChainlinkProposal = new PWNSimpleLoanElasticChainlinkProposal(
            address(deployment.hub),
            address(deployment.revokedNonce),
            address(deployment.config),
            address(deployment.utilizedCredit),
            address(0), // todo: feed registry
            address(0) // todo: weth
        );
        deployment.simpleLoanElasticProposal = new PWNSimpleLoanElasticProposal(
            address(deployment.hub),
            address(deployment.revokedNonce),
            address(deployment.config),
            address(deployment.utilizedCredit)
        );
        deployment.simpleLoanDutchAuctionProposal = new PWNSimpleLoanDutchAuctionProposal(
            address(deployment.hub),
            address(deployment.revokedNonce),
            address(deployment.config),
            address(deployment.utilizedCredit)
        );

        // Set hub tags
        address[] memory addrs = new address[](12);
        addrs[0] = address(deployment.simpleLoan);
        addrs[1] = address(deployment.simpleLoan);

        addrs[2] = address(deployment.simpleLoanSimpleProposal);
        addrs[3] = address(deployment.simpleLoanSimpleProposal);

        addrs[4] = address(deployment.simpleLoanListProposal);
        addrs[5] = address(deployment.simpleLoanListProposal);

        addrs[6] = address(deployment.simpleLoanElasticChainlinkProposal);
        addrs[7] = address(deployment.simpleLoanElasticChainlinkProposal);

        addrs[8] = address(deployment.simpleLoanElasticProposal);
        addrs[9] = address(deployment.simpleLoanElasticProposal);

        addrs[10] = address(deployment.simpleLoanDutchAuctionProposal);
        addrs[11] = address(deployment.simpleLoanDutchAuctionProposal);

        bytes32[] memory tags = new bytes32[](12);
        tags[0] = PWNHubTags.ACTIVE_LOAN;
        tags[1] = PWNHubTags.NONCE_MANAGER;

        tags[2] = PWNHubTags.LOAN_PROPOSAL;
        tags[3] = PWNHubTags.NONCE_MANAGER;

        tags[4] = PWNHubTags.LOAN_PROPOSAL;
        tags[5] = PWNHubTags.NONCE_MANAGER;

        tags[6] = PWNHubTags.LOAN_PROPOSAL;
        tags[7] = PWNHubTags.NONCE_MANAGER;

        tags[8] = PWNHubTags.LOAN_PROPOSAL;
        tags[9] = PWNHubTags.NONCE_MANAGER;

        tags[10] = PWNHubTags.LOAN_PROPOSAL;
        tags[11] = PWNHubTags.NONCE_MANAGER;

        vm.prank(deployment.protocolTimelock);
        deployment.hub.setTags(addrs, tags, true);
    }

}
