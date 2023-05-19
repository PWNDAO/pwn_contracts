// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
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


abstract contract DeploymentTest is Test {
    using stdJson for string;
    using Strings for uint256;

    uint256[] deployedChains;
    Deployment deployment;

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
        PWNSimpleLoanListOffer simpleLoanListOffer;
        PWNSimpleLoanSimpleOffer simpleLoanSimpleOffer;
        PWNSimpleLoanSimpleRequest simpleLoanSimpleRequest;
    }

    address admin;
    address dao;
    address feeCollector;

    PWNDeployer deployer;
    PWNHub hub;
    PWNConfig config;
    PWNLOAN loanToken;
    PWNSimpleLoan simpleLoan;
    PWNRevokedNonce revokedOfferNonce;
    PWNRevokedNonce revokedRequestNonce;
    PWNSimpleLoanSimpleOffer simpleLoanSimpleOffer;
    PWNSimpleLoanListOffer simpleLoanListOffer;
    PWNSimpleLoanSimpleRequest simpleLoanSimpleRequest;


    function setUp() public virtual {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments.json");
        string memory json = vm.readFile(path);
        bytes memory rawDeployedChains = json.parseRaw(".deployedChains");
        deployedChains = abi.decode(rawDeployedChains, (uint256[]));

        if (_contains(deployedChains, block.chainid)) {
            bytes memory rawDeployment = json.parseRaw(string.concat(".chains.", block.chainid.toString()));
            deployment = abi.decode(rawDeployment, (Deployment));

            admin = deployment.admin;
            dao = deployment.dao;
            feeCollector = deployment.feeCollector;
            deployer = deployment.deployer;
            hub = deployment.hub;
            config = deployment.config;
            loanToken = deployment.loanToken;
            simpleLoan = deployment.simpleLoan;
            revokedOfferNonce = deployment.revokedOfferNonce;
            revokedRequestNonce = deployment.revokedRequestNonce;
            simpleLoanSimpleOffer = deployment.simpleLoanSimpleOffer;
            simpleLoanListOffer = deployment.simpleLoanListOffer;
            simpleLoanSimpleRequest = deployment.simpleLoanSimpleRequest;
        } else {
            _deployProtocol();
        }
    }

    function _contains(uint256[] storage array, uint256 value) private view returns (bool) {
        for (uint256 i; i < array.length; ++i)
            if (array[i] == value)
                return true;

        return false;
    }

    function _deployProtocol() internal {
        admin = makeAddr("admin");
        dao = makeAddr("dao");
        feeCollector = makeAddr("feeCollector");

        // Deploy protocol
        PWNConfig configSingleton = new PWNConfig();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(configSingleton),
            admin,
            abi.encodeWithSignature("initialize(address,uint16,address)", address(this), 0, feeCollector)
        );
        config = PWNConfig(address(proxy));

        vm.prank(admin);
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

        vm.prank(admin);
        hub.setTags(addrs, tags, true);
    }

}
