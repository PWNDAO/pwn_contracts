// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "@pwn-test/helper/DeploymentTest.t.sol";


/*

Run tests with this command:

FOUNDRY_PROFILE=deployed forge t -f [mainnet, polygon, goerli, mumbai, local]

*/
abstract contract DeployedProtocolTest is DeploymentTest {
    bytes32 internal constant PROXY_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
}


contract DeployedProtocol_Addresses_Test is DeployedProtocolTest {

    function test_checkAddresses_Deployer() external {
        assertEq(deployer.owner(), admin);
    }

    function test_checkAddresses_Config() external {
        assertEq(vm.load(address(config), PROXY_ADMIN_SLOT), bytes32(uint256(uint160(admin))));
        assertEq(config.owner(), dao);
        assertEq(config.feeCollector(), feeCollector);
    }

    function test_checkAddresses_Hub() external {
        assertEq(hub.owner(), admin);
    }

}


contract DeployedProtocol_Tags_Test is DeployedProtocolTest {

    function test_checkTags_SimpleLoan() external {
        assertTrue(hub.hasTag(address(simpleLoan), PWNHubTags.ACTIVE_LOAN));
    }

    function test_checkTags_SimpleOffer() external {
        assertTrue(hub.hasTag(address(simpleLoanSimpleOffer), PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY));
        assertTrue(hub.hasTag(address(simpleLoanSimpleOffer), PWNHubTags.LOAN_OFFER));
    }

    function test_checkTags_ListOffer() external {
        assertTrue(hub.hasTag(address(simpleLoanListOffer), PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY));
        assertTrue(hub.hasTag(address(simpleLoanListOffer), PWNHubTags.LOAN_OFFER));
    }

    function test_checkTags_SimpleRequest() external {
        assertTrue(hub.hasTag(address(simpleLoanSimpleRequest), PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY));
        assertTrue(hub.hasTag(address(simpleLoanSimpleRequest), PWNHubTags.LOAN_REQUEST));
    }

}
