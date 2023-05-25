// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "openzeppelin-contracts/contracts/governance/TimelockController.sol";

import "@pwn-test/helper/DeploymentTest.t.sol";


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
        // - owner is protocol safe
        assertEq(deployer.owner(), protocolSafe);

        // TIMELOCK CONTROLLERS
        if (block.chainid == 1 || block.chainid == 137) {
            TimelockController protocolTimelockController = TimelockController(payable(protocolTimelock));
            // - protocol timelock has min delay of 14 days
            assertEq(protocolTimelockController.getMinDelay(), 1_209_600);
            // - protocol safe has PROPOSER role in protocol timelock
            assertTrue(protocolTimelockController.hasRole(PROPOSER_ROLE, protocolSafe));
            // - protocol safe has CANCELLER role in protocol timelock
            assertTrue(protocolTimelockController.hasRole(CANCELLER_ROLE, protocolSafe));
            // - everybody has EXECUTOR role in protocol timelock
            assertTrue(protocolTimelockController.hasRole(EXECUTOR_ROLE, address(0)));

            TimelockController productTimelockController = TimelockController(payable(productTimelock));
            // - product timelock has min delay of 7 days
            assertEq(productTimelockController.getMinDelay(), 604_800);
            // - dao safe has PROPOSER role in product timelock
            assertTrue(productTimelockController.hasRole(PROPOSER_ROLE, daoSafe));
            // - dao safe has CANCELLER role in product timelock
            assertTrue(productTimelockController.hasRole(CANCELLER_ROLE, daoSafe));
            // - everybody has EXECUTOR role in product timelock
            assertTrue(productTimelockController.hasRole(EXECUTOR_ROLE, address(0)));
        }

        // CONFIG
        if (block.chainid == 1 || block.chainid == 137) {
            // - admin is protocol timelock
            assertEq(vm.load(address(config), PROXY_ADMIN_SLOT), bytes32(uint256(uint160(protocolTimelock))));
            // - owner is product timelock
            assertEq(config.owner(), productTimelock);
        } else {
            // - admin is protocol safe
            assertEq(vm.load(address(config), PROXY_ADMIN_SLOT), bytes32(uint256(uint160(protocolSafe))));
            // - owner is dao safe
            assertEq(config.owner(), daoSafe);
        }
        // - feeCollector is feeCollector
        assertEq(config.feeCollector(), feeCollector);
        // - is initialized
        assertEq(vm.load(address(config), bytes32(uint256(1))) << 88 >> 248, bytes32(uint256(1)));
        // - implementation is initialized
        address configImplementation = address(uint160(uint256(vm.load(address(config), PROXY_IMPLEMENTATION_SLOT))));
        assertEq(vm.load(configImplementation, bytes32(uint256(1))) << 88 >> 248, bytes32(uint256(1)));

        // HUB
        if (block.chainid == 1 || block.chainid == 137) {
            // - owner is protocol timelock
            assertEq(hub.owner(), protocolTimelock);
        } else {
            // - owner is protocol safe
            assertEq(hub.owner(), protocolSafe);
        }

        // HUB TAGS
        // - simple loan has active loan tag
        assertTrue(hub.hasTag(address(simpleLoan), PWNHubTags.ACTIVE_LOAN));
        // - simple loan simple offer has simple loan terms factory & loan offer tags
        assertTrue(hub.hasTag(address(simpleLoanSimpleOffer), PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY));
        assertTrue(hub.hasTag(address(simpleLoanSimpleOffer), PWNHubTags.LOAN_OFFER));
        // - simple loan list offer has simple loan terms factory & loan offer tags
        assertTrue(hub.hasTag(address(simpleLoanListOffer), PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY));
        assertTrue(hub.hasTag(address(simpleLoanListOffer), PWNHubTags.LOAN_OFFER));
        // - simple loan simple request has simple loan terms factory & loan request tags
        assertTrue(hub.hasTag(address(simpleLoanSimpleRequest), PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY));
        assertTrue(hub.hasTag(address(simpleLoanSimpleRequest), PWNHubTags.LOAN_REQUEST));

    }


    function test_deployedProtocol_ethereum() external { _test_deployedProtocol("mainnet"); }
    function test_deployedProtocol_polygon() external { _test_deployedProtocol("polygon"); }
    function test_deployedProtocol_goerli() external { _test_deployedProtocol("goerli"); }
    function test_deployedProtocol_mumbai() external { _test_deployedProtocol("mumbai"); }

}
