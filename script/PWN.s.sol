// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Script, console2 } from "forge-std/Script.sol";

import { ITransparentUpgradeableProxy } from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

import { GnosisSafeLike, GnosisSafeUtils } from "./lib/GnosisSafeUtils.sol";
import { TimelockController, TimelockUtils } from "./lib/TimelockUtils.sol";

import {
    Deployments,
    PWNConfig,
    IPWNDeployer,
    PWNHub,
    PWNHubTags,
    PWNSimpleLoan,
    PWNSimpleLoanDutchAuctionProposal,
    PWNSimpleLoanElasticProposal,
    PWNSimpleLoanElasticChainlinkProposal,
    PWNSimpleLoanListProposal,
    PWNSimpleLoanSimpleProposal,
    PWNLOAN,
    PWNRevokedNonce,
    PWNUtilizedCredit,
    MultiTokenCategoryRegistry,
    IChainlinkFeedRegistryLike
} from "pwn/Deployments.sol";


library PWNContractDeployerSalt {

    // Singletons
    bytes32 internal constant CONFIG = keccak256("PWNConfig");
    bytes32 internal constant CONFIG_PROXY = keccak256("PWNConfigProxy");
    bytes32 internal constant HUB = keccak256("PWNHub");
    bytes32 internal constant LOAN = keccak256("PWNLOAN");
    bytes32 internal constant REVOKED_NONCE = keccak256("PWNRevokedNonce");
    bytes32 internal constant UTILIZED_CREDIT = keccak256("PWNUtilizedCredit");
    bytes32 internal constant CHAINLINK_FEED_REGISTRY = keccak256("PWNChainlinkFeedRegistry");

    // Loan types
    bytes32 internal constant SIMPLE_LOAN = keccak256("PWNSimpleLoan");

    // Proposal types
    bytes32 internal constant SIMPLE_LOAN_SIMPLE_PROPOSAL = keccak256("PWNSimpleLoanSimpleProposal");
    bytes32 internal constant SIMPLE_LOAN_LIST_PROPOSAL = keccak256("PWNSimpleLoanListProposal");
    bytes32 internal constant SIMPLE_LOAN_ELASTIC_PROPOSAL = keccak256("PWNSimpleLoanElasticProposal");
    bytes32 internal constant SIMPLE_LOAN_ELASTIC_CHAINLINK_PROPOSAL = keccak256("PWNSimpleLoanElasticChainlinkProposal");
    bytes32 internal constant SIMPLE_LOAN_DUTCH_AUCTION_PROPOSAL = keccak256("PWNSimpleLoanDutchAuctionProposal");

}


contract Deploy is Deployments, Script {
    using GnosisSafeUtils for GnosisSafeLike;

    function _protocolNotDeployedOnSelectedChain() internal pure override {
        revert("PWN: selected chain is not set in deployments/latest.json");
    }

    function _deployAndTransferOwnership(
        bytes32 salt,
        address owner,
        bytes memory bytecode
    ) internal returns (address) {
        bool success = GnosisSafeLike(__e.deployerSafe).execTransaction({
            to: address(__e.deployer),
            data: abi.encodeWithSelector(
                IPWNDeployer.deployAndTransferOwnership.selector, salt, owner, bytecode
            )
        });
        require(success, "Deploy failed");
        return __e.deployer.computeAddress(salt, keccak256(bytecode));
    }

    function _deploy(
        bytes32 salt,
        bytes memory bytecode
    ) internal returns (address) {
        bool success = GnosisSafeLike(__e.deployerSafe).execTransaction({
            to: address(__e.deployer),
            data: abi.encodeWithSelector(
                IPWNDeployer.deploy.selector, salt, bytecode
            )
        });
        require(success, "Deploy failed");
        return __e.deployer.computeAddress(salt, keccak256(bytecode));
    }

/*
forge script script/PWN.s.sol:Deploy \
--sig "redeploySimpleLoanMultichain()" \
--private-key $PRIVATE_KEY \
--multi --verify --broadcast
*/
    /// addresses set in the `deployments/latest.json`.
    function redeploySimpleLoanMultichain() external {
        string[] memory chains = new string[](8);
        chains[0] = "polygon";
        chains[1] = "arbitrum";
        chains[2] = "base";
        chains[3] = "optimism";
        chains[4] = "bsc";
        chains[5] = "cronos";
        chains[6] = "gnosis";
        chains[7] = "world";
        // linea - gas estimate is always super low and tx is pending for days -> execute separately

        for (uint256 i; i < chains.length; ++i) {
            redeploySimpleLoan(chains[i]);
        }

    }

/*
forge script script/PWN.s.sol:Deploy \
--sig "redeploySimpleLoan(string)" "sepolia" \
--private-key $PRIVATE_KEY \
--with-gas-price $(cast --to-wei 0.3 gwei) \
--verify --broadcast
*/
    function redeploySimpleLoan(string memory chain) public {
        vm.createSelectFork(chain);
        _loadDeployedAddresses();

        vm.startBroadcast();

        __d.simpleLoan = PWNSimpleLoan(_deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN,
            bytecode: abi.encodePacked(
                type(PWNSimpleLoan).creationCode,
                abi.encode(
                    address(__d.hub),
                    address(__d.loanToken),
                    address(__d.config),
                    address(__d.revokedNonce),
                    address(__d.categoryRegistry)
                )
            )
        }));

        console2.log("------");
        console2.log("chain: %s (%s)", chain, block.chainid);
        console2.log("PWNSimpleLoan:", address(__d.simpleLoan));

        vm.stopBroadcast();
    }

/*
forge script script/PWN.s.sol:Deploy \
--sig "deployNewProtocolVersionMultichain()" \
--private-key $PRIVATE_KEY \
--multi --verify --broadcast
*/
    /// addresses set in the `deployments/latest.json`.
    function deployNewProtocolVersionMultichain() external {
        string[] memory chains = new string[](8);
        chains[0] = "polygon";
        chains[1] = "base";
        chains[2] = "optimism";
        chains[3] = "world";
        chains[4] = "gnosis";
        chains[5] = "arbitrum";
        chains[6] = "bsc";
        chains[7] = "cronos";
        // linea - gas estimate is always super low and tx is pending for days -> execute separately
        // ethereum - set custom gas price

        for (uint256 i; i < chains.length; ++i) {
            deployNewProtocolVersion(chains[i]);
        }

    }

/*
forge script script/PWN.s.sol:Deploy \
--sig "deployNewProtocolVersion(string)" "mainnet" \
--private-key $PRIVATE_KEY \
--with-gas-price $(cast --to-wei 3 gwei) \
--verify --broadcast
*/
    /// @dev Expecting to have deployer, deployerSafe, config, hub & revoked nonce
    /// addresses set in the `deployments/latest.json`.
    function deployNewProtocolVersion(string memory chain) public {
        vm.createSelectFork(chain);
        _loadDeployedAddresses();

        require(address(__e.deployer) != address(0), "Deployer not set");
        require(__e.deployerSafe != address(0), "Deployer safe not set");
        require(address(__d.config) != address(0), "Config not set");
        require(address(__d.hub) != address(0), "Hub not set");
        require(address(__d.revokedNonce) != address(0), "Revoked nonce not set");

        vm.startBroadcast();

        // Deploy new protocol version without Chainlink contracts

        // - Utilized credit
        __d.utilizedCredit = PWNUtilizedCredit(_deploy({
            salt: PWNContractDeployerSalt.UTILIZED_CREDIT,
            bytecode: abi.encodePacked(
                type(PWNUtilizedCredit).creationCode,
                abi.encode(address(__d.hub), PWNHubTags.LOAN_PROPOSAL)
            )
        }));

        // - Loan
        __d.simpleLoan = PWNSimpleLoan(_deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN,
            bytecode: abi.encodePacked(
                type(PWNSimpleLoan).creationCode,
                abi.encode(
                    address(__d.hub),
                    address(__d.loanToken),
                    address(__d.config),
                    address(__d.revokedNonce),
                    address(__d.categoryRegistry)
                )
            )
        }));

        // - Proposals
        __d.simpleLoanSimpleProposal = PWNSimpleLoanSimpleProposal(_deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN_SIMPLE_PROPOSAL,
            bytecode: abi.encodePacked(
                type(PWNSimpleLoanSimpleProposal).creationCode,
                abi.encode(
                    address(__d.hub),
                    address(__d.revokedNonce),
                    address(__d.config),
                    address(__d.utilizedCredit)
                )
            )
        }));

        __d.simpleLoanListProposal = PWNSimpleLoanListProposal(_deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN_LIST_PROPOSAL,
            bytecode: abi.encodePacked(
                type(PWNSimpleLoanListProposal).creationCode,
                abi.encode(
                    address(__d.hub),
                    address(__d.revokedNonce),
                    address(__d.config),
                    address(__d.utilizedCredit)
                )
            )
        }));

        __d.simpleLoanElasticProposal = PWNSimpleLoanElasticProposal(_deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN_ELASTIC_PROPOSAL,
            bytecode: abi.encodePacked(
                type(PWNSimpleLoanElasticProposal).creationCode,
                abi.encode(
                    address(__d.hub),
                    address(__d.revokedNonce),
                    address(__d.config),
                    address(__d.utilizedCredit)
                )
            )
        }));

        __d.simpleLoanDutchAuctionProposal = PWNSimpleLoanDutchAuctionProposal(_deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN_DUTCH_AUCTION_PROPOSAL,
            bytecode: abi.encodePacked(
                type(PWNSimpleLoanDutchAuctionProposal).creationCode,
                abi.encode(
                    address(__d.hub),
                    address(__d.revokedNonce),
                    address(__d.config),
                    address(__d.utilizedCredit)
                )
            )
        }));

        console2.log("Deployment:", chain);
        console2.log("PWNUtilizedCredit:", address(__d.utilizedCredit));
        console2.log("PWNSimpleLoan:", address(__d.simpleLoan));
        console2.log("PWNSimpleLoanSimpleProposal:", address(__d.simpleLoanSimpleProposal));
        console2.log("PWNSimpleLoanListProposal:", address(__d.simpleLoanListProposal));
        console2.log("PWNSimpleLoanElasticProposal:", address(__d.simpleLoanElasticProposal));
        console2.log("PWNSimpleLoanDutchAuctionProposal:", address(__d.simpleLoanDutchAuctionProposal));
        console2.log("-----------------");

        vm.stopBroadcast();
    }

/*
forge script script/PWN.s.sol:Deploy \
--sig "deployChainlinkSupportMultichain()" \
--private-key $PRIVATE_KEY \
--multi --verify --broadcast
*/
    /// addresses set in the `deployments/latest.json`.
    function deployChainlinkSupportMultichain() external {
        string[] memory chains = new string[](6);
        chains[0] = "polygon";
        chains[1] = "arbitrum";
        chains[2] = "base";
        chains[3] = "optimism";
        chains[4] = "bsc";
        chains[5] = "gnosis";
        // linea - gas estimate is always super low and tx is pending for days -> execute separately
        // ethereum - set custom gas price
        // cronos, world are not supported by Chainlink atm

        for (uint256 i; i < chains.length; ++i) {
            deployChainlinkSupport(chains[i]);
        }

    }

/*
forge script script/PWN.s.sol:Deploy \
--sig "deployChainlinkSupport(string)" "[chain]" \
--private-key $PRIVATE_KEY \
--verify --broadcast
*/
    /// @dev Expecting to have deployer, deployerSafe, config, hub & revoked nonce
    /// addresses set in the `deployments/latest.json`.
    function deployChainlinkSupport(string memory chain) public {
        vm.createSelectFork(chain);
        _loadDeployedAddresses();

        require(address(__e.deployer) != address(0), "Deployer not set");
        require(__e.deployerSafe != address(0), "Deployer safe not set");
        require(address(__d.config) != address(0), "Config not set");
        require(address(__d.hub) != address(0), "Hub not set");
        require(address(__d.revokedNonce) != address(0), "Revoked nonce not set");
        require(__e.weth != address(0), "WETH not set");

        vm.startBroadcast();

        // - Chainlink feed registry
        __d.chainlinkFeedRegistry = IChainlinkFeedRegistryLike(_deployAndTransferOwnership({ // Need ownership acceptance from the new owner
            salt: PWNContractDeployerSalt.CHAINLINK_FEED_REGISTRY,
            owner: __e.protocolTimelock,
            bytecode: __cc.chainlinkFeedRegistry
        }));

        // - Elastic Chainlink Proposal
        __d.simpleLoanElasticChainlinkProposal = PWNSimpleLoanElasticChainlinkProposal(_deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN_ELASTIC_CHAINLINK_PROPOSAL,
            bytecode: abi.encodePacked(
                type(PWNSimpleLoanElasticChainlinkProposal).creationCode,
                abi.encode(
                    address(__d.hub),
                    address(__d.revokedNonce),
                    address(__d.config),
                    address(__d.utilizedCredit),
                    address(__d.chainlinkFeedRegistry),
                    __e.chainlinkL2SequencerUptimeFeed,
                    __e.weth
                )
            )
        }));

        console2.log("Deployment:", chain);
        console2.log("PWNChainlinkFeedRegistry:", address(__d.chainlinkFeedRegistry));
        console2.log("PWNSimpleLoanElasticChainlinkProposal:", address(__d.simpleLoanElasticChainlinkProposal));
        console2.log("-----------------");

        vm.stopBroadcast();
    }

/*
forge script script/PWN.s.sol:Deploy \
--sig "deployProtocol()" \
--rpc-url $RPC_URL \
--private-key $PRIVATE_KEY \
--with-gas-price $(cast --to-wei 15 gwei) \
--verify --etherscan-api-key $ETHERSCAN_API_KEY \
--broadcast
*/
    /// @dev Expecting to have deployer, deployerSafe, adminTimelock, protocolTimelock & daoSafe
    /// addresses set in the `deployments/latest.json`.
    function deployProtocol() external {
        _loadDeployedAddresses();

        require(address(__e.deployer) != address(0), "Deployer not set");
        require(__e.deployerSafe != address(0), "Deployer safe not set");
        require(__e.adminTimelock != address(0), "Admin timelock not set");
        require(__e.protocolTimelock != address(0), "Protocol timelock not set");
        require(__e.daoSafe != address(0), "DAO safe not set");

        uint256 initialConfigHelper = vmSafe.envUint("INITIAL_CONFIG_HELPER");

        vm.startBroadcast();

        // Deploy protocol

        // - Config

        // Note: To have the same config proxy address on new chains independently of the config implementation,
        // the config proxy is deployed first with Deployer implementation that has the same address on all chains.
        // Proxy implementation is then upgraded to the correct one in the next transaction.

        __d.config = PWNConfig(_deploy({
            salt: PWNContractDeployerSalt.CONFIG_PROXY,
            bytecode: __cc.config
        }));
        __d.configSingleton = PWNConfig(_deploy({
            salt: PWNContractDeployerSalt.CONFIG,
            bytecode: __cc.configSingleton_v1_2
        }));

        vm.stopBroadcast();


        vm.startBroadcast(initialConfigHelper);
        ITransparentUpgradeableProxy(address(__d.config)).upgradeToAndCall(
            address(__d.configSingleton),
            abi.encodeWithSelector(PWNConfig.initialize.selector, __e.protocolTimelock, 0, __e.daoSafe)
        );
        ITransparentUpgradeableProxy(address(__d.config)).changeAdmin(__e.adminTimelock);
        vm.stopBroadcast();


        vm.startBroadcast();

        // - Chainlink feed registry
        __d.chainlinkFeedRegistry = IChainlinkFeedRegistryLike(_deployAndTransferOwnership({ // Need ownership acceptance from the new owner
            salt: PWNContractDeployerSalt.CHAINLINK_FEED_REGISTRY,
            owner: __e.protocolTimelock,
            bytecode: __cc.chainlinkFeedRegistry
        }));

        // - MultiToken category registry
        __d.categoryRegistry = MultiTokenCategoryRegistry(_deployAndTransferOwnership({ // Need ownership acceptance from the new owner
            salt: PWNContractDeployerSalt.CONFIG,
            owner: __e.protocolTimelock,
            bytecode: __cc.categoryRegistry
        }));

        // - Hub
        __d.hub = PWNHub(_deployAndTransferOwnership({ // Need ownership acceptance from the new owner
            salt: PWNContractDeployerSalt.HUB,
            owner: __e.protocolTimelock,
            bytecode: __cc.hub
        }));

        // - LOAN token
        __d.loanToken = PWNLOAN(_deploy({
            salt: PWNContractDeployerSalt.LOAN,
            bytecode: abi.encodePacked(__cc.loanToken, abi.encode(address(__d.hub)))
        }));

        // - Revoked nonces
        __d.revokedNonce = PWNRevokedNonce(_deploy({
            salt: PWNContractDeployerSalt.REVOKED_NONCE,
            bytecode: abi.encodePacked(__cc.revokedNonce, abi.encode(address(__d.hub), PWNHubTags.NONCE_MANAGER))
        }));

        // - Utilized credit
        __d.utilizedCredit = PWNUtilizedCredit(_deploy({
            salt: PWNContractDeployerSalt.UTILIZED_CREDIT,
            bytecode: abi.encodePacked(__cc.utilizedCredit, abi.encode(address(__d.hub), PWNHubTags.LOAN_PROPOSAL))
        }));

        // - Loan types
        __d.simpleLoan = PWNSimpleLoan(_deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN,
            bytecode: abi.encodePacked(
                __cc.simpleLoan_v1_3, abi.encode(address(__d.hub), address(__d.loanToken), address(__d.config), address(__d.revokedNonce), address(__d.categoryRegistry))
            )
        }));

        // - Proposals
        __d.simpleLoanSimpleProposal = PWNSimpleLoanSimpleProposal(_deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN_SIMPLE_PROPOSAL,
            bytecode: abi.encodePacked(
                __cc.simpleLoanSimpleProposal_v1_3, abi.encode(address(__d.hub), address(__d.revokedNonce), address(__d.config), address(__d.utilizedCredit))
            )
        }));

        __d.simpleLoanListProposal = PWNSimpleLoanListProposal(_deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN_LIST_PROPOSAL,
            bytecode: abi.encodePacked(
                __cc.simpleLoanListProposal_v1_3, abi.encode(address(__d.hub), address(__d.revokedNonce), address(__d.config), address(__d.utilizedCredit))
            )
        }));

        if (__e.weth != address(0) && (
            (__e.isL2 && __e.chainlinkL2SequencerUptimeFeed != address(0)) || (!__e.isL2 && __e.chainlinkL2SequencerUptimeFeed == address(0))
        )) {
            __d.simpleLoanElasticChainlinkProposal = PWNSimpleLoanElasticChainlinkProposal(_deploy({
                salt: PWNContractDeployerSalt.SIMPLE_LOAN_ELASTIC_CHAINLINK_PROPOSAL,
                bytecode: abi.encodePacked(
                    __cc.simpleLoanElasticChainlinkProposal_v1_0, abi.encode(address(__d.hub), address(__d.revokedNonce), address(__d.config), address(__d.utilizedCredit), address(__d.chainlinkFeedRegistry), __e.chainlinkL2SequencerUptimeFeed, __e.weth)
                )
            }));
        }

        __d.simpleLoanElasticProposal = PWNSimpleLoanElasticProposal(_deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN_ELASTIC_PROPOSAL,
            bytecode: abi.encodePacked(
                __cc.simpleLoanElasticProposal_v1_1, abi.encode(address(__d.hub), address(__d.revokedNonce), address(__d.config), address(__d.utilizedCredit))
            )
        }));

        __d.simpleLoanDutchAuctionProposal = PWNSimpleLoanDutchAuctionProposal(_deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN_DUTCH_AUCTION_PROPOSAL,
            bytecode: abi.encodePacked(
                __cc.simpleLoanDutchAuctionProposal_v1_1, abi.encode(address(__d.hub), address(__d.revokedNonce), address(__d.config), address(__d.utilizedCredit))
            )
        }));

        console2.log("PWNChainlinkFeedRegistry:", address(__d.chainlinkFeedRegistry));
        console2.log("MultiToken Category Registry:", address(__d.categoryRegistry));
        console2.log("PWNConfig - singleton:", address(__d.configSingleton));
        console2.log("PWNConfig - proxy:", address(__d.config));
        console2.log("PWNHub:", address(__d.hub));
        console2.log("PWNLOAN:", address(__d.loanToken));
        console2.log("PWNRevokedNonce:", address(__d.revokedNonce));
        console2.log("PWNUtilizedCredit:", address(__d.utilizedCredit));
        console2.log("PWNSimpleLoan:", address(__d.simpleLoan));
        console2.log("PWNSimpleLoanSimpleProposal:", address(__d.simpleLoanSimpleProposal));
        console2.log("PWNSimpleLoanListProposal:", address(__d.simpleLoanListProposal));
        console2.log("PWNSimpleLoanElasticChainlinkProposal:", address(__d.simpleLoanElasticChainlinkProposal));
        console2.log("PWNSimpleLoanElasticProposal:", address(__d.simpleLoanElasticProposal));
        console2.log("PWNSimpleLoanDutchAuctionProposal:", address(__d.simpleLoanDutchAuctionProposal));

        vm.stopBroadcast();
    }

}


contract Setup is Deployments, Script {
    using GnosisSafeUtils for GnosisSafeLike;
    using TimelockUtils for TimelockController;

    function _protocolNotDeployedOnSelectedChain() internal pure override {
        revert("PWN: selected chain is not set in deployments/latest.json");
    }

/*
forge script script/PWN.s.sol:Setup \
--sig "setupNewProtocolVersion()" \
--rpc-url $RPC_URL \
--private-key $PRIVATE_KEY \
--broadcast
*/
    /// @dev Expecting to have protocol addresses set in the `deployments/latest.json`
    /// Can be used only in fork tests, because safe has threshold >1 and hub is owner by a timelock.
    function setupNewProtocolVersion() external {
        _loadDeployedAddresses();

        vm.startBroadcast();

        _acceptOwnership(__e.daoSafe, __e.protocolTimelock, address(__d.chainlinkFeedRegistry));
        _setTags(true);

        vm.stopBroadcast();
    }

/*
forge script script/PWN.s.sol:Setup \
--sig "setupProtocol()" \
--rpc-url $RPC_URL \
--private-key $PRIVATE_KEY \
--with-gas-price $(cast --to-wei 15 gwei) \
--broadcast
*/
    /// @dev Expecting to have protocol addresses set in the `deployments/latest.json`
    function setupProtocol() external {
        _loadDeployedAddresses();

        require(address(__e.daoSafe) != address(0), "Protocol safe not set");
        require(address(__d.categoryRegistry) != address(0), "Category registry not set");
        require(address(__d.hub) != address(0), "Hub not set");
        require(address(__d.chainlinkFeedRegistry) != address(0), "Chainlink feed registry not set");

        vm.startBroadcast();

        _acceptOwnership(__e.daoSafe, __e.protocolTimelock, address(__d.categoryRegistry));
        _acceptOwnership(__e.daoSafe, __e.protocolTimelock, address(__d.hub));
        _acceptOwnership(__e.daoSafe, __e.protocolTimelock, address(__d.chainlinkFeedRegistry));
        _setTags(true);

        vm.stopBroadcast();
    }

/*
forge script script/PWN.s.sol:Setup \
--sig "removeCurrentLoanProposalTags()" \
--rpc-url $RPC_URL \
--private-key $PRIVATE_KEY \
--broadcast
*/
    function removeCurrentLoanProposalTags() external {
        _loadDeployedAddresses();

        vm.startBroadcast();
        _setTags(false);
        vm.stopBroadcast();
    }

    function _acceptOwnership(address safe, address timelock, address contract_) internal {
        TimelockController(payable(timelock)).scheduleAndExecute(
            GnosisSafeLike(safe),
            contract_,
            abi.encodeWithSignature("acceptOwnership()")
        );
        console2.log("Accept ownership tx succeeded");
    }

/*
forge script script/PWN.s.sol:Setup --sig "printTagsCalldata(string)" "polygon"
*/
    function printTagsCalldata(string memory chain) external {
        vm.createSelectFork(chain);
        _loadDeployedAddresses();

        require(address(__d.simpleLoan) != address(0), "Simple loan not set");
        require(address(__d.simpleLoanSimpleProposal) != address(0), "Simple loan simple proposal not set");
        require(address(__d.simpleLoanListProposal) != address(0), "Simple loan list proposal not set");
        require(address(__d.simpleLoanElasticProposal) != address(0), "Simple loan elastic proposal not set");
        require(address(__d.simpleLoanDutchAuctionProposal) != address(0), "Simple loan dutch auctin proposal not set");

        address[] memory addrs = new address[](10);
        addrs[0] = address(__d.simpleLoanSimpleProposal);
        addrs[1] = address(__d.simpleLoanSimpleProposal);

        addrs[2] = address(__d.simpleLoanListProposal);
        addrs[3] = address(__d.simpleLoanListProposal);

        addrs[4] = address(__d.simpleLoanElasticProposal);
        addrs[5] = address(__d.simpleLoanElasticProposal);

        addrs[6] = address(__d.simpleLoanDutchAuctionProposal);
        addrs[7] = address(__d.simpleLoanDutchAuctionProposal);

        addrs[8] = address(__d.simpleLoan);
        addrs[9] = address(__d.simpleLoan);

        bytes32[] memory tags = new bytes32[](10);
        tags[0] = PWNHubTags.LOAN_PROPOSAL;
        tags[1] = PWNHubTags.NONCE_MANAGER;

        tags[2] = PWNHubTags.LOAN_PROPOSAL;
        tags[3] = PWNHubTags.NONCE_MANAGER;

        tags[4] = PWNHubTags.LOAN_PROPOSAL;
        tags[5] = PWNHubTags.NONCE_MANAGER;

        tags[6] = PWNHubTags.LOAN_PROPOSAL;
        tags[7] = PWNHubTags.NONCE_MANAGER;

        tags[8] = PWNHubTags.ACTIVE_LOAN;
        tags[9] = PWNHubTags.NONCE_MANAGER;

        console2.logBytes(abi.encodeWithSignature("setTags(address[],bytes32[],bool)", addrs, tags, true));
    }

    function _setTags(bool set) internal {
        require(address(__d.simpleLoan) != address(0), "Simple loan not set");
        require(address(__d.simpleLoanSimpleProposal) != address(0), "Simple loan simple proposal not set");
        require(address(__d.simpleLoanListProposal) != address(0), "Simple loan list proposal not set");
        require(address(__d.simpleLoanElasticProposal) != address(0), "Simple loan elastic proposal not set");
        require(address(__d.simpleLoanDutchAuctionProposal) != address(0), "Simple loan dutch auctin proposal not set");
        require(address(__e.protocolTimelock) != address(0), "Protocol timelock not set");
        require(address(__e.daoSafe) != address(0), "DAO safe not set");
        require(address(__d.hub) != address(0), "Hub not set");

        bool chainlinkSupported = address(__d.simpleLoanElasticChainlinkProposal) != address(0);

        address[] memory addrs = new address[](chainlinkSupported ? 12 : 10);
        addrs[0] = address(__d.simpleLoan);
        addrs[1] = address(__d.simpleLoan);

        addrs[2] = address(__d.simpleLoanSimpleProposal);
        addrs[3] = address(__d.simpleLoanSimpleProposal);

        addrs[4] = address(__d.simpleLoanListProposal);
        addrs[5] = address(__d.simpleLoanListProposal);

        addrs[6] = address(__d.simpleLoanElasticProposal);
        addrs[7] = address(__d.simpleLoanElasticProposal);

        addrs[8] = address(__d.simpleLoanDutchAuctionProposal);
        addrs[9] = address(__d.simpleLoanDutchAuctionProposal);

        bytes32[] memory tags = new bytes32[](chainlinkSupported ? 12 : 10);
        tags[0] = PWNHubTags.ACTIVE_LOAN;
        tags[1] = PWNHubTags.NONCE_MANAGER;

        tags[2] = PWNHubTags.LOAN_PROPOSAL;
        tags[3] = PWNHubTags.NONCE_MANAGER;

        tags[4] = PWNHubTags.LOAN_PROPOSAL;
        tags[5] = PWNHubTags.NONCE_MANAGER;

        tags[6] = PWNHubTags.LOAN_PROPOSAL;
        tags[7] = PWNHubTags.NONCE_MANAGER;

        tags[8] = PWNHubTags.LOAN_PROPOSAL;
        tags[9] = PWNHubTags.NONCE_MANAGER;

        if (chainlinkSupported) {
            addrs[10] = address(__d.simpleLoanElasticChainlinkProposal);
            addrs[11] = address(__d.simpleLoanElasticChainlinkProposal);
            tags[10] = PWNHubTags.LOAN_PROPOSAL;
            tags[11] = PWNHubTags.NONCE_MANAGER;
        }

        TimelockController(payable(__e.protocolTimelock)).scheduleAndExecute(
            GnosisSafeLike(__e.daoSafe),
            address(__d.hub),
            abi.encodeWithSignature("setTags(address[],bytes32[],bool)", addrs, tags, set)
        );

        console2.log("Tags set succeeded (%s)", tags.length);
        for (uint256 i; i < addrs.length; ++i) {
            console2.log("-- tag set:", addrs[i]);
            console2.logBytes32(tags[i]);
        }
    }

/*
forge script script/PWN.s.sol:Setup \
--sig "setDefaultMetadata(string)" $METADATA \
--rpc-url $RPC_URL \
--private-key $PRIVATE_KEY \
--with-gas-price $(cast --to-wei 15 gwei) \
--broadcast
*/
    /// @dev Expecting to have daoSafe, protocol timelock & config addresses set in the `deployments/latest.json`
    function setDefaultMetadata(string memory metadata) external {
        _loadDeployedAddresses();

        require(address(__e.daoSafe) != address(0), "DAO safe not set");
        require(address(__e.protocolTimelock) != address(0), "Protocol timelock not set");
        require(address(__d.config) != address(0), "Config not set");

        vm.startBroadcast();

        TimelockController(payable(__e.protocolTimelock)).scheduleAndExecute(
            GnosisSafeLike(__e.daoSafe),
            address(__d.config),
            abi.encodeWithSignature("setDefaultLOANMetadataUri(string)", metadata)
        );
        console2.log("Metadata set:", metadata);

        vm.stopBroadcast();
    }

/*
forge script script/PWN.s.sol:Setup \
--sig "registerCategory()" {addr} {category} \
--rpc-url $RPC_URL \
--private-key $PRIVATE_KEY \
--with-gas-price $(cast --to-wei 15 gwei) \
--broadcast
*/
    /// @dev Expecting to have daoSafe, protocol timelock & category registry addresses set in the `deployments/latest.json`
    function registerCategory(address assetAddress, uint8 category) external {
        _loadDeployedAddresses();

        require(address(__e.daoSafe) != address(0), "DAO safe not set");
        require(address(__e.protocolTimelock) != address(0), "Protocol timelock not set");
        require(address(__d.categoryRegistry) != address(0), "Category Registry not set");

        vm.startBroadcast();

        TimelockController(payable(__e.protocolTimelock)).scheduleAndExecute(
            GnosisSafeLike(__e.daoSafe),
            address(__d.categoryRegistry),
            abi.encodeWithSignature("registerCategoryValue(address,uint8)", assetAddress, category)
        );
        console2.log("Category registered:", assetAddress, category);

        vm.stopBroadcast();
    }

}
