// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { TimelockController } from "openzeppelin/governance/TimelockController.sol";

import {
    DeploymentTest,
    PWNHubTags
} from "test/DeploymentTest.t.sol";


contract DeployedProtocolTest is DeploymentTest {

    bytes32 internal constant PROXY_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    bytes32 internal constant PROXY_IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 internal constant PROPOSER_ROLE = 0xb09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc1;
    bytes32 internal constant EXECUTOR_ROLE = 0xd8aa0f3194971a2a116679f7c2090f6939c8d4e01a2a8d7e41d55e5351469e63;
    bytes32 internal constant CANCELLER_ROLE = 0xfd643c72710c63c0180259aba6b2d05451e3591a24e58b62239378085726f783;

    function _test_deployedProtocol(string memory urlOrAlias) internal {
        vm.createSelectFork(urlOrAlias);
        super.setUp();

        // DEPLOYER
        // - owner is deployer safe
        if (deployment.deployerSafe != address(0)) {
            assertEq(deployment.deployer.owner(), deployment.deployerSafe);
        }

        // TIMELOCK CONTROLLERS
        address timelockOwner = deployment.dao == address(0) ? deployment.daoSafe : deployment.dao;
        TimelockController protocolTimelockController = TimelockController(payable(deployment.protocolTimelock));
        // - protocol timelock has min delay of 4 days
        assertEq(protocolTimelockController.getMinDelay(), 4 days);
        // - dao or dao safe has PROPOSER role in protocol timelock
        assertTrue(protocolTimelockController.hasRole(PROPOSER_ROLE, timelockOwner));
        // - dao or dao safe has CANCELLER role in protocol timelock
        assertTrue(protocolTimelockController.hasRole(CANCELLER_ROLE, timelockOwner));
        // - everybody has EXECUTOR role in protocol timelock
        assertTrue(protocolTimelockController.hasRole(EXECUTOR_ROLE, address(0)));

        TimelockController adminTimelockController = TimelockController(payable(deployment.adminTimelock));
        // - admin timelock has min delay of 4 days
        assertEq(adminTimelockController.getMinDelay(), 4 days);
        // - dao or dao safe has PROPOSER role in product timelock
        assertTrue(adminTimelockController.hasRole(PROPOSER_ROLE, timelockOwner));
        // - dao or dao safe has CANCELLER role in product timelock
        assertTrue(adminTimelockController.hasRole(CANCELLER_ROLE, timelockOwner));
        // - everybody has EXECUTOR role in product timelock
        assertTrue(adminTimelockController.hasRole(EXECUTOR_ROLE, address(0)));

        // CONFIG
        // - admin is admin timelock
        assertEq(vm.load(address(deployment.config), PROXY_ADMIN_SLOT), bytes32(uint256(uint160(deployment.adminTimelock))));
        // - owner is protocol timelock
        assertEq(deployment.config.owner(), deployment.protocolTimelock);
        // - feeCollector is dao safe
        assertEq(deployment.config.feeCollector(), deployment.daoSafe);
        // - is initialized
        assertEq(vm.load(address(deployment.config), bytes32(uint256(1))) << 88 >> 248, bytes32(uint256(1)));
        // - implementation is initialized
        address configImplementation = address(uint160(uint256(vm.load(address(deployment.config), PROXY_IMPLEMENTATION_SLOT))));
        assertEq(vm.load(configImplementation, bytes32(uint256(1))) << 88 >> 248, bytes32(uint256(1)));

        // CATEGORY REGISTRY
        // - owner is protocol timelock
        // assertTrue(deployment.categoryRegistry.owner(), deployment.protocolTimelock);

        // HUB
        // - owner is protocol timelock
        assertEq(deployment.hub.owner(), deployment.protocolTimelock);

        // HUB TAGS
        // - simple loan
        assertTrue(deployment.hub.hasTag(address(deployment.simpleLoan), PWNHubTags.NONCE_MANAGER));
        assertTrue(deployment.hub.hasTag(address(deployment.simpleLoan), PWNHubTags.ACTIVE_LOAN));
        // - simple loan simple proposal
        assertTrue(deployment.hub.hasTag(address(deployment.simpleLoanSimpleProposal), PWNHubTags.NONCE_MANAGER));
        assertTrue(deployment.hub.hasTag(address(deployment.simpleLoanSimpleProposal), PWNHubTags.LOAN_PROPOSAL));
        // - simple loan list proposal
        assertTrue(deployment.hub.hasTag(address(deployment.simpleLoanListProposal), PWNHubTags.NONCE_MANAGER));
        assertTrue(deployment.hub.hasTag(address(deployment.simpleLoanListProposal), PWNHubTags.LOAN_PROPOSAL));
        // - simple loan fungible proposal
        assertTrue(deployment.hub.hasTag(address(deployment.simpleLoanFungibleProposal), PWNHubTags.NONCE_MANAGER));
        assertTrue(deployment.hub.hasTag(address(deployment.simpleLoanFungibleProposal), PWNHubTags.LOAN_PROPOSAL));
        // - simple loan dutch auction proposal
        assertTrue(deployment.hub.hasTag(address(deployment.simpleLoanDutchAuctionProposal), PWNHubTags.NONCE_MANAGER));
        assertTrue(deployment.hub.hasTag(address(deployment.simpleLoanDutchAuctionProposal), PWNHubTags.LOAN_PROPOSAL));
    }


    // todo: function test_deployedProtocol_ethereum() external { _test_deployedProtocol("mainnet"); }

}
