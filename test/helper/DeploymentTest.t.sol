// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "@pwn/Deployments.sol";


abstract contract DeploymentTest is Deployments, Test {

    function setUp() public virtual {
        _loadDeployedAddresses();
    }

    function _protocolNotDeployedOnSelectedChain() internal override {
        protocolSafe = makeAddr("protocolSafe");
        daoSafe = makeAddr("daoSafe");
        feeCollector = makeAddr("feeCollector");

        // Deploy protocol
        PWNConfig configSingleton = new PWNConfig();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(configSingleton),
            protocolSafe,
            abi.encodeWithSignature("initialize(address,uint16,address)", address(this), 0, feeCollector)
        );
        config = PWNConfig(address(proxy));

        vm.prank(protocolSafe);
        hub = new PWNHub();

        loanToken = new PWNLOAN(address(hub));
        simpleLoan = new PWNSimpleLoan(address(hub), address(loanToken), address(config));

        revokedOfferNonce = new PWNRevokedNonce(address(hub), PWNHubTags.LOAN_OFFER);
        simpleLoanSimpleOffer = new PWNSimpleLoanSimpleOffer(address(hub), address(revokedOfferNonce));
        simpleLoanListOffer = new PWNSimpleLoanListOffer(address(hub), address(revokedOfferNonce));

        revokedRequestNonce = new PWNRevokedNonce(address(hub), PWNHubTags.LOAN_REQUEST);
        simpleLoanSimpleRequest = new PWNSimpleLoanSimpleRequest(address(hub), address(revokedRequestNonce));

        // Set hub tags
        address[] memory addrs = new address[](7);
        addrs[0] = address(simpleLoan);
        addrs[1] = address(simpleLoanSimpleOffer);
        addrs[2] = address(simpleLoanSimpleOffer);
        addrs[3] = address(simpleLoanListOffer);
        addrs[4] = address(simpleLoanListOffer);
        addrs[5] = address(simpleLoanSimpleRequest);
        addrs[6] = address(simpleLoanSimpleRequest);

        bytes32[] memory tags = new bytes32[](7);
        tags[0] = PWNHubTags.ACTIVE_LOAN;
        tags[1] = PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY;
        tags[2] = PWNHubTags.LOAN_OFFER;
        tags[3] = PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY;
        tags[4] = PWNHubTags.LOAN_OFFER;
        tags[5] = PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY;
        tags[6] = PWNHubTags.LOAN_REQUEST;

        vm.prank(protocolSafe);
        hub.setTags(addrs, tags, true);
    }

}
