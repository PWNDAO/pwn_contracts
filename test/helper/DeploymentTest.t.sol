// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import { MultiTokenCategoryRegistry, IMultiTokenCategoryRegistry } from "MultiToken/MultiTokenCategoryRegistry.sol";

import { TransparentUpgradeableProxy }
    from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "@pwn/Deployments.sol";


abstract contract DeploymentTest is Deployments, Test {

    function setUp() public virtual {
        _loadDeployedAddresses();
    }

    function _protocolNotDeployedOnSelectedChain() internal override {
        protocolSafe = makeAddr("protocolSafe");
        daoSafe = makeAddr("daoSafe");
        feeCollector = makeAddr("feeCollector");

        // Deploy category registry
        vm.prank(protocolSafe);
        categoryRegistry = IMultiTokenCategoryRegistry(new MultiTokenCategoryRegistry());

        // Deploy protocol
        configSingleton = new PWNConfig();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(configSingleton),
            protocolSafe,
            abi.encodeWithSignature("initialize(address,uint16,address)", address(this), 0, feeCollector)
        );
        config = PWNConfig(address(proxy));

        vm.prank(protocolSafe);
        hub = new PWNHub();

        revokedNonce = new PWNRevokedNonce(address(hub), PWNHubTags.NONCE_MANAGER);

        loanToken = new PWNLOAN(address(hub));
        simpleLoan = new PWNSimpleLoan(
            address(hub), address(loanToken), address(config), address(revokedNonce), address(categoryRegistry)
        );

        simpleLoanListOffer = new PWNSimpleLoanListOffer(address(hub), address(revokedNonce), address(stateFingerprintComputerRegistry));

        // Set hub tags
        address[] memory addrs = new address[](4);
        addrs[0] = address(simpleLoan);
        addrs[1] = address(simpleLoan);
        addrs[2] = address(simpleLoanListOffer);
        addrs[3] = address(simpleLoanListOffer);

        bytes32[] memory tags = new bytes32[](4);
        tags[0] = PWNHubTags.ACTIVE_LOAN;
        tags[1] = PWNHubTags.NONCE_MANAGER;
        tags[2] = PWNHubTags.LOAN_PROPOSAL;
        tags[3] = PWNHubTags.NONCE_MANAGER;

        vm.prank(protocolSafe);
        hub.setTags(addrs, tags, true);
    }

}
