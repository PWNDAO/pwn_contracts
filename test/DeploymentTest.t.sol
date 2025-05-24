// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import { TransparentUpgradeableProxy } from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import { Create2 } from "openzeppelin/utils/Create2.sol";

import {
    Deployments,
    PWNConfig,
    IPWNDeployer,
    PWNHub,
    PWNHubTags,
    PWNLoan,
    PWNMortgageProposal,
    PWNLOAN,
    PWNRevokedNonce,
    PWNUtilizedCredit,
    MultiTokenCategoryRegistry
} from "pwn/Deployments.sol";


abstract contract DeploymentTest is Deployments, Test {

    uint256 lenderPK = uint256(777);
    address lender = vm.addr(lenderPK);
    uint256 borrowerPK = uint256(888);
    address borrower = vm.addr(borrowerPK);

    function setUp() public virtual {
        _loadDeployedAddresses();

        vm.label(lender, "lender");
        vm.label(borrower, "borrower");
    }

    function _sign(uint256 pk, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }


    function _protocolNotDeployedOnSelectedChain() internal override {
        __e.protocolTimelock = makeAddr("protocolTimelock");
        __e.adminTimelock = makeAddr("adminTimelock");
        __e.daoSafe = makeAddr("daoSafe");

        // Deploy category registry
        vm.prank(__e.protocolTimelock);
        __d.categoryRegistry = new MultiTokenCategoryRegistry();

        // Deploy protocol
        __d.configSingleton = new PWNConfig();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(__d.configSingleton),
            __e.adminTimelock,
            abi.encodeWithSignature("initialize(address,uint16,address)", __e.protocolTimelock, 0, __e.daoSafe)
        );
        __d.config = PWNConfig(address(proxy));

        vm.prank(__e.protocolTimelock);
        __d.hub = new PWNHub();

        __d.revokedNonce = new PWNRevokedNonce(address(__d.hub), PWNHubTags.NONCE_MANAGER);
        __d.utilizedCredit = new PWNUtilizedCredit(address(__d.hub), PWNHubTags.LOAN_PROPOSAL);

        __d.loanToken = new PWNLOAN(address(__d.hub));

        __d.loan = new PWNLoan(
            address(__d.hub),
            address(__d.loanToken),
            address(__d.config),
            address(__d.categoryRegistry)
        );

        // workshop todo: deploy modules, and hooks

        __d.mortgageProposal = new PWNMortgageProposal(
            address(__d.hub),
            address(__d.revokedNonce),
            address(__d.config),
            address(__d.utilizedCredit)
            // workshop todo: pass modules
        );

        // Set hub tags
        address[] memory addrs = new address[](4);
        addrs[0] = address(__d.loan);
        addrs[1] = address(__d.loan);

        addrs[2] = address(__d.mortgageProposal);
        addrs[3] = address(__d.mortgageProposal);

        // workshop todo: include addressese of modules, and hooks

        bytes32[] memory tags = new bytes32[](4);
        tags[0] = PWNHubTags.ACTIVE_LOAN;
        tags[1] = PWNHubTags.NONCE_MANAGER;

        tags[2] = PWNHubTags.LOAN_PROPOSAL;
        tags[3] = PWNHubTags.NONCE_MANAGER;

        // workshop todo: set tags for modules, and hooks

        vm.prank(__e.protocolTimelock);
        __d.hub.setTags(addrs, tags, true);
    }

}
