// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "@pwn-test/helper/DeploymentTest.t.sol";


contract DeployedProtocolTest is DeploymentTest {

    bytes32 internal constant PROXY_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    function _test_deployedProtocol(string memory urlOrAlias) internal {
        vm.createSelectFork(urlOrAlias);
        super.setUp();

        // deployer owner is admin
        assertEq(deployer.owner(), admin);

        // config admin is admin & owner is dao & feeCollector is feeCollector
        assertEq(vm.load(address(config), PROXY_ADMIN_SLOT), bytes32(uint256(uint160(admin))));
        assertEq(config.owner(), dao);
        assertEq(config.feeCollector(), feeCollector);

        // hub owner is admin
        assertEq(hub.owner(), admin);

        // simple loan has active loan tag
        assertTrue(hub.hasTag(address(simpleLoan), PWNHubTags.ACTIVE_LOAN));

        // simple loan simple offer has simple loan terms factory & loan offer tags
        assertTrue(hub.hasTag(address(simpleLoanSimpleOffer), PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY));
        assertTrue(hub.hasTag(address(simpleLoanSimpleOffer), PWNHubTags.LOAN_OFFER));

        // simple loan list offer has simple loan terms factory & loan offer tags
        assertTrue(hub.hasTag(address(simpleLoanListOffer), PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY));
        assertTrue(hub.hasTag(address(simpleLoanListOffer), PWNHubTags.LOAN_OFFER));

        // simple loan simple request has simple loan terms factory & loan request tags
        assertTrue(hub.hasTag(address(simpleLoanSimpleRequest), PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY));
        assertTrue(hub.hasTag(address(simpleLoanSimpleRequest), PWNHubTags.LOAN_REQUEST));

    }


    // function test_deployedProtocol_ethereum() external { _test_deployedProtocol("mainnet"); }
    // function test_deployedProtocol_polygon() external { _test_deployedProtocol("polygon"); }
    function test_deployedProtocol_goerli() external { _test_deployedProtocol("goerli"); }
    // function test_deployedProtocol_mumbai() external { _test_deployedProtocol("mumbai"); }

}
