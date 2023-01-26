// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "openzeppelin-contracts/contracts/utils/Strings.sol";

import "@pwn/config/PWNConfig.sol";
import "@pwn/deployer/PWNDeployer.sol";
import "@pwn/hub/PWNHub.sol";
import "@pwn/hub/PWNHubTags.sol";
import "@pwn/loan/terms/simple/loan/PWNSimpleLoan.sol";
import "@pwn/loan/terms/simple/factory/offer/PWNSimpleLoanListOffer.sol";
import "@pwn/loan/terms/simple/factory/offer/PWNSimpleLoanSimpleOffer.sol";
import "@pwn/loan/terms/simple/factory/request/PWNSimpleLoanSimpleRequest.sol";
import "@pwn/loan/token/PWNLOAN.sol";
import "@pwn/nonce/PWNRevokedNonce.sol";


/*

Run tests with this command:

FOUNDRY_PROFILE=deployed forge test --fork-url [mainnet, polygon, goerli, mumbai, local]

*/
abstract contract DeployedProtocolTest is Test {
    using stdJson for string;
    using Strings for uint256;

    bytes32 internal constant PROXY_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    // Properties need to be in alphabetical order
    struct Deployment {
        address admin;
        PWNConfig config;
        address dao;
        PWNDeployer deployer;
        address feeCollector;
        PWNHub hub;
        PWNLOAN loanToken;
        PWNRevokedNonce revokedOfferNonce;
        PWNRevokedNonce revokedRequestNonce;
        PWNSimpleLoan simpleLoan;
        PWNSimpleLoanSimpleOffer simpleLoanSimpleOffer;
        PWNSimpleLoanListOffer simpleLoanListOffer;
        PWNSimpleLoanSimpleRequest simpleLoanSimpleRequest;
    }

    Deployment deployment;

    constructor() {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments.json");
        string memory json = vm.readFile(path);
        bytes memory rawDeployment = json.parseRaw(string.concat(".", block.chainid.toString()));
        deployment = abi.decode(rawDeployment, (Deployment));
    }

}


contract DeployedProtocol_Addresses_Test is DeployedProtocolTest {

    function test_checkAddresses_Deployer() external {
        assertEq(deployment.deployer.owner(), deployment.admin);
    }

    function test_checkAddresses_Config() external {
        assertEq(vm.load(address(deployment.config), PROXY_ADMIN_SLOT), bytes32(uint256(uint160(deployment.admin))));
        assertEq(deployment.config.owner(), deployment.dao);
        assertEq(deployment.config.feeCollector(), deployment.feeCollector);
    }

    function test_checkAddresses_Hub() external {
        assertEq(deployment.hub.owner(), deployment.admin);
    }

}


contract DeployedProtocol_Tags_Test is DeployedProtocolTest {

    function test_checkTags_SimpleLoan() external {
        assertTrue(deployment.hub.hasTag(address(deployment.simpleLoan), PWNHubTags.ACTIVE_LOAN));
    }

    function test_checkTags_SimpleOffer() external {
        assertTrue(deployment.hub.hasTag(address(deployment.simpleLoanSimpleOffer), PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY));
        assertTrue(deployment.hub.hasTag(address(deployment.simpleLoanSimpleOffer), PWNHubTags.LOAN_OFFER));
    }

    function test_checkTags_ListOffer() external {
        assertTrue(deployment.hub.hasTag(address(deployment.simpleLoanListOffer), PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY));
        assertTrue(deployment.hub.hasTag(address(deployment.simpleLoanListOffer), PWNHubTags.LOAN_OFFER));
    }

    function test_checkTags_SimpleRequest() external {
        assertTrue(deployment.hub.hasTag(address(deployment.simpleLoanSimpleRequest), PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY));
        assertTrue(deployment.hub.hasTag(address(deployment.simpleLoanSimpleRequest), PWNHubTags.LOAN_REQUEST));
    }

}
