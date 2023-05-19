// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "@pwn-test/helper/DeploymentTest.t.sol";


contract DeployedProtocolTest is DeploymentTest {

    bytes32 internal constant PROXY_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    bytes32 internal constant PROXY_IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function _test_deployedProtocol(string memory urlOrAlias) internal {
        vm.createSelectFork(urlOrAlias);
        super.setUp();

        // DEPLOYER
        // - owner is admin
        assertEq(deployer.owner(), admin);

        // CONFIG
        // - admin is admin
        assertEq(vm.load(address(config), PROXY_ADMIN_SLOT), bytes32(uint256(uint160(admin))));
        // - owner is dao
        assertEq(config.owner(), dao);
        // - feeCollector is feeCollector
        assertEq(config.feeCollector(), feeCollector);
        // - is initialized
        assertEq(vm.load(address(config), bytes32(uint256(1))) << 88 >> 248, bytes32(uint256(1)));
        // - implementation is initialized
        address configImplementation = address(uint160(uint256(vm.load(address(config), PROXY_IMPLEMENTATION_SLOT))));
        assertEq(vm.load(configImplementation, bytes32(uint256(1))) << 88 >> 248, bytes32(uint256(1)));

        // HUB
        // - owner is admin
        assertEq(hub.owner(), admin);

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
