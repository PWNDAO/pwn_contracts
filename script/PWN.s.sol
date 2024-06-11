// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Script, console2 } from "forge-std/Script.sol";

import { TransparentUpgradeableProxy, ITransparentUpgradeableProxy }
    from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

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
    PWNSimpleLoanFungibleProposal,
    PWNSimpleLoanListProposal,
    PWNSimpleLoanSimpleProposal,
    PWNLOAN,
    PWNRevokedNonce,
    MultiTokenCategoryRegistry
} from "pwn/Deployments.sol";

import { T20 } from "test/helper/T20.sol";
import { T721 } from "test/helper/T721.sol";
import { T1155 } from "test/helper/T1155.sol";


library PWNContractDeployerSalt {

    string internal constant VERSION = "1.2";

    // Singletons
    bytes32 internal constant CONFIG = keccak256("PWNConfig");
    bytes32 internal constant CONFIG_PROXY = keccak256("PWNConfigProxy");
    bytes32 internal constant HUB = keccak256("PWNHub");
    bytes32 internal constant LOAN = keccak256("PWNLOAN");
    bytes32 internal constant REVOKED_NONCE = keccak256("PWNRevokedNonce");

    // Loan types
    bytes32 internal constant SIMPLE_LOAN = keccak256("PWNSimpleLoan");

    // Proposal types
    bytes32 internal constant SIMPLE_LOAN_SIMPLE_PROPOSAL = keccak256("PWNSimpleLoanSimpleProposal");
    bytes32 internal constant SIMPLE_LOAN_LIST_PROPOSAL = keccak256("PWNSimpleLoanListProposal");
    bytes32 internal constant SIMPLE_LOAN_FUNGIBLE_PROPOSAL = keccak256("PWNSimpleLoanFungibleProposal");
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
        bool success = GnosisSafeLike(deployment.deployerSafe).execTransaction({
            to: address(deployment.deployer),
            data: abi.encodeWithSelector(
                IPWNDeployer.deployAndTransferOwnership.selector, salt, owner, bytecode
            )
        });
        require(success, "Deploy failed");
        return deployment.deployer.computeAddress(salt, keccak256(bytecode));
    }

    function _deploy(
        bytes32 salt,
        bytes memory bytecode
    ) internal returns (address) {
        bool success = GnosisSafeLike(deployment.deployerSafe).execTransaction({
            to: address(deployment.deployer),
            data: abi.encodeWithSelector(
                IPWNDeployer.deploy.selector, salt, bytecode
            )
        });
        require(success, "Deploy failed");
        return deployment.deployer.computeAddress(salt, keccak256(bytecode));
    }

/*
forge script script/PWN.s.sol:Deploy \
--sig "deployNewProtocolVersion()" \
--rpc-url $RPC_URL \
--private-key $PRIVATE_KEY \
--with-gas-price $(cast --to-wei 15 gwei) \
--verify --etherscan-api-key $ETHERSCAN_API_KEY \
--broadcast
*/
    /// @dev Expecting to have deployer, deployerSafe, adminTimelock, protocolTimelock, daoSafe, hub & LOAN token
    /// addresses set in the `deployments/latest.json`.
    function deployNewProtocolVersion() external {
        _loadDeployedAddresses();

        require(address(deployment.deployer) != address(0), "Deployer not set");
        require(deployment.deployerSafe != address(0), "Deployer safe not set");
        require(deployment.adminTimelock != address(0), "Admin timelock not set");
        require(deployment.protocolTimelock != address(0), "Protocol timelock not set");
        require(deployment.daoSafe != address(0), "DAO safe not set");
        require(address(deployment.hub) != address(0), "Hub not set");
        require(address(deployment.loanToken) != address(0), "LOAN token not set");

        uint256 initialConfigHelper = vmSafe.envUint("INITIAL_CONFIG_HELPER");

        vm.startBroadcast();

        // Deploy new protocol version

        // - Config

        // Note: To have the same config proxy address on new chains independently of the config implementation,
        // the config proxy is deployed first with Deployer implementation that has the same address on all chains.
        // Proxy implementation is then upgraded to the correct one in the next transaction.

        deployment.config = PWNConfig(_deploy({
            salt: PWNContractDeployerSalt.CONFIG_PROXY,
            bytecode: abi.encodePacked(
                type(TransparentUpgradeableProxy).creationCode,
                abi.encode(deployment.deployer, vm.addr(initialConfigHelper), "")
            )
        }));
        deployment.configSingleton = PWNConfig(_deploy({
            salt: PWNContractDeployerSalt.CONFIG,
            bytecode: type(PWNConfig).creationCode
        }));

        vm.stopBroadcast();


        vm.startBroadcast(initialConfigHelper);
        ITransparentUpgradeableProxy(address(deployment.config)).upgradeToAndCall(
            address(deployment.configSingleton),
            abi.encodeWithSelector(PWNConfig.initialize.selector, deployment.protocolTimelock, 0, deployment.daoSafe)
        );
        ITransparentUpgradeableProxy(address(deployment.config)).changeAdmin(deployment.adminTimelock);
        vm.stopBroadcast();


        vm.startBroadcast();

        // - MultiToken category registry
        deployment.categoryRegistry = MultiTokenCategoryRegistry(_deployAndTransferOwnership({ // Need ownership acceptance from the new owner
            salt: PWNContractDeployerSalt.CONFIG,
            owner: deployment.protocolTimelock,
            bytecode: type(MultiTokenCategoryRegistry).creationCode
        }));

        // - Revoked nonces
        deployment.revokedNonce = PWNRevokedNonce(_deploy({
            salt: PWNContractDeployerSalt.REVOKED_NONCE,
            bytecode: abi.encodePacked(
                type(PWNRevokedNonce).creationCode,
                abi.encode(address(deployment.hub), PWNHubTags.NONCE_MANAGER)
            )
        }));

        // - Loan types
        deployment.simpleLoan = PWNSimpleLoan(_deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN,
            bytecode: abi.encodePacked(
                type(PWNSimpleLoan).creationCode,
                abi.encode(
                    address(deployment.hub),
                    address(deployment.loanToken),
                    address(deployment.config),
                    address(deployment.revokedNonce),
                    address(deployment.categoryRegistry)
                )
            )
        }));

        // - Proposals
        deployment.simpleLoanSimpleProposal = PWNSimpleLoanSimpleProposal(_deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN_SIMPLE_PROPOSAL,
            bytecode: abi.encodePacked(
                type(PWNSimpleLoanSimpleProposal).creationCode,
                abi.encode(
                    address(deployment.hub),
                    address(deployment.revokedNonce),
                    address(deployment.config)
                )
            )
        }));

        deployment.simpleLoanListProposal = PWNSimpleLoanListProposal(_deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN_LIST_PROPOSAL,
            bytecode: abi.encodePacked(
                type(PWNSimpleLoanListProposal).creationCode,
                abi.encode(
                    address(deployment.hub),
                    address(deployment.revokedNonce),
                    address(deployment.config)
                )
            )
        }));

        deployment.simpleLoanFungibleProposal = PWNSimpleLoanFungibleProposal(_deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN_FUNGIBLE_PROPOSAL,
            bytecode: abi.encodePacked(
                type(PWNSimpleLoanFungibleProposal).creationCode,
                abi.encode(
                    address(deployment.hub),
                    address(deployment.revokedNonce),
                    address(deployment.config)
                )
            )
        }));

        deployment.simpleLoanDutchAuctionProposal = PWNSimpleLoanDutchAuctionProposal(_deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN_DUTCH_AUCTION_PROPOSAL,
            bytecode: abi.encodePacked(
                type(PWNSimpleLoanDutchAuctionProposal).creationCode,
                abi.encode(
                    address(deployment.hub),
                    address(deployment.revokedNonce),
                    address(deployment.config)
                )
            )
        }));

        console2.log("MultiToken Category Registry:", address(deployment.categoryRegistry));
        console2.log("PWNConfig - singleton:", address(deployment.configSingleton));
        console2.log("PWNConfig - proxy:", address(deployment.config));
        console2.log("PWNHub:", address(deployment.hub));
        console2.log("PWNLOAN:", address(deployment.loanToken));
        console2.log("PWNRevokedNonce:", address(deployment.revokedNonce));
        console2.log("PWNSimpleLoan:", address(deployment.simpleLoan));
        console2.log("PWNSimpleLoanSimpleProposal:", address(deployment.simpleLoanSimpleProposal));
        console2.log("PWNSimpleLoanListProposal:", address(deployment.simpleLoanListProposal));
        console2.log("PWNSimpleLoanFungibleProposal:", address(deployment.simpleLoanFungibleProposal));
        console2.log("PWNSimpleLoanDutchAuctionProposal:", address(deployment.simpleLoanDutchAuctionProposal));

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

        require(address(deployment.deployer) != address(0), "Deployer not set");
        require(deployment.deployerSafe != address(0), "Deployer safe not set");
        require(deployment.adminTimelock != address(0), "Admin timelock not set");
        require(deployment.protocolTimelock != address(0), "Protocol timelock not set");
        require(deployment.daoSafe != address(0), "DAO safe not set");

        uint256 initialConfigHelper = vmSafe.envUint("INITIAL_CONFIG_HELPER");

        vm.startBroadcast();

        // Deploy protocol

        // - Config

        // Note: To have the same config proxy address on new chains independently of the config implementation,
        // the config proxy is deployed first with Deployer implementation that has the same address on all chains.
        // Proxy implementation is then upgraded to the correct one in the next transaction.

        deployment.config = PWNConfig(_deploy({
            salt: PWNContractDeployerSalt.CONFIG_PROXY,
            bytecode: abi.encodePacked(
                type(TransparentUpgradeableProxy).creationCode,
                abi.encode(deployment.deployer, vm.addr(initialConfigHelper), "")
            )
        }));
        address configSingleton = _deploy({
            salt: PWNContractDeployerSalt.CONFIG,
            bytecode: type(PWNConfig).creationCode
        });

        vm.stopBroadcast();


        vm.startBroadcast(initialConfigHelper);
        ITransparentUpgradeableProxy(address(deployment.config)).upgradeToAndCall(
            configSingleton,
            abi.encodeWithSelector(PWNConfig.initialize.selector, deployment.protocolTimelock, 0, deployment.daoSafe)
        );
        ITransparentUpgradeableProxy(address(deployment.config)).changeAdmin(deployment.adminTimelock);
        vm.stopBroadcast();


        vm.startBroadcast();

        // - MultiToken category registry
        deployment.categoryRegistry = MultiTokenCategoryRegistry(_deployAndTransferOwnership({ // Need ownership acceptance from the new owner
            salt: PWNContractDeployerSalt.CONFIG,
            owner: deployment.protocolTimelock,
            bytecode: type(MultiTokenCategoryRegistry).creationCode
        }));

        // - Hub
        deployment.hub = PWNHub(_deployAndTransferOwnership({ // Need ownership acceptance from the new owner
            salt: PWNContractDeployerSalt.HUB,
            owner: deployment.protocolTimelock,
            bytecode: type(PWNHub).creationCode
        }));

        // - LOAN token
        deployment.loanToken = PWNLOAN(_deploy({
            salt: PWNContractDeployerSalt.LOAN,
            bytecode: abi.encodePacked(
                type(PWNLOAN).creationCode,
                abi.encode(address(deployment.hub))
            )
        }));

        // - Revoked nonces
        deployment.revokedNonce = PWNRevokedNonce(_deploy({
            salt: PWNContractDeployerSalt.REVOKED_NONCE,
            bytecode: abi.encodePacked(
                type(PWNRevokedNonce).creationCode,
                abi.encode(address(deployment.hub), PWNHubTags.NONCE_MANAGER)
            )
        }));

        // - Loan types
        deployment.simpleLoan = PWNSimpleLoan(_deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN,
            bytecode: abi.encodePacked(
                type(PWNSimpleLoan).creationCode,
                abi.encode(
                    address(deployment.hub),
                    address(deployment.loanToken),
                    address(deployment.config),
                    address(deployment.revokedNonce),
                    address(deployment.categoryRegistry)
                )
            )
        }));

        // - Proposals
        deployment.simpleLoanSimpleProposal = PWNSimpleLoanSimpleProposal(_deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN_SIMPLE_PROPOSAL,
            bytecode: abi.encodePacked(
                type(PWNSimpleLoanSimpleProposal).creationCode,
                abi.encode(
                    address(deployment.hub),
                    address(deployment.revokedNonce),
                    address(deployment.config)
                )
            )
        }));

        deployment.simpleLoanListProposal = PWNSimpleLoanListProposal(_deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN_LIST_PROPOSAL,
            bytecode: abi.encodePacked(
                type(PWNSimpleLoanListProposal).creationCode,
                abi.encode(
                    address(deployment.hub),
                    address(deployment.revokedNonce),
                    address(deployment.config)
                )
            )
        }));

        deployment.simpleLoanFungibleProposal = PWNSimpleLoanFungibleProposal(_deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN_FUNGIBLE_PROPOSAL,
            bytecode: abi.encodePacked(
                type(PWNSimpleLoanFungibleProposal).creationCode,
                abi.encode(
                    address(deployment.hub),
                    address(deployment.revokedNonce),
                    address(deployment.config)
                )
            )
        }));

        deployment.simpleLoanDutchAuctionProposal = PWNSimpleLoanDutchAuctionProposal(_deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN_DUTCH_AUCTION_PROPOSAL,
            bytecode: abi.encodePacked(
                type(PWNSimpleLoanDutchAuctionProposal).creationCode,
                abi.encode(
                    address(deployment.hub),
                    address(deployment.revokedNonce),
                    address(deployment.config)
                )
            )
        }));

        console2.log("MultiToken Category Registry:", address(deployment.categoryRegistry));
        console2.log("PWNConfig - singleton:", configSingleton);
        console2.log("PWNConfig - proxy:", address(deployment.config));
        console2.log("PWNHub:", address(deployment.hub));
        console2.log("PWNLOAN:", address(deployment.loanToken));
        console2.log("PWNRevokedNonce:", address(deployment.revokedNonce));
        console2.log("PWNSimpleLoan:", address(deployment.simpleLoan));
        console2.log("PWNSimpleLoanSimpleProposal:", address(deployment.simpleLoanSimpleProposal));
        console2.log("PWNSimpleLoanListProposal:", address(deployment.simpleLoanListProposal));
        console2.log("PWNSimpleLoanFungibleProposal:", address(deployment.simpleLoanFungibleProposal));
        console2.log("PWNSimpleLoanDutchAuctionProposal:", address(deployment.simpleLoanDutchAuctionProposal));

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

        require(address(deployment.daoSafe) != address(0), "Protocol safe not set");
        require(address(deployment.categoryRegistry) != address(0), "Category registry not set");

        vm.startBroadcast();

        _acceptOwnership(deployment.daoSafe, deployment.protocolTimelock, address(deployment.categoryRegistry));
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

        require(address(deployment.daoSafe) != address(0), "Protocol safe not set");
        require(address(deployment.categoryRegistry) != address(0), "Category registry not set");
        require(address(deployment.hub) != address(0), "Hub not set");

        vm.startBroadcast();

        _acceptOwnership(deployment.daoSafe, deployment.protocolTimelock, address(deployment.categoryRegistry));
        _acceptOwnership(deployment.daoSafe, deployment.protocolTimelock, address(deployment.hub));
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

    function _setTags(bool set) internal {
        require(address(deployment.simpleLoan) != address(0), "Simple loan not set");
        require(address(deployment.simpleLoanSimpleProposal) != address(0), "Simple loan simple proposal not set");
        require(address(deployment.simpleLoanListProposal) != address(0), "Simple loan list proposal not set");
        require(address(deployment.simpleLoanFungibleProposal) != address(0), "Simple loan fungible proposal not set");
        require(address(deployment.simpleLoanDutchAuctionProposal) != address(0), "Simple loan dutch auctin proposal not set");
        require(address(deployment.protocolTimelock) != address(0), "Protocol timelock not set");
        require(address(deployment.daoSafe) != address(0), "DAO safe not set");
        require(address(deployment.hub) != address(0), "Hub not set");

        address[] memory addrs = new address[](10);
        addrs[0] = address(deployment.simpleLoan);
        addrs[1] = address(deployment.simpleLoan);

        addrs[2] = address(deployment.simpleLoanSimpleProposal);
        addrs[3] = address(deployment.simpleLoanSimpleProposal);

        addrs[4] = address(deployment.simpleLoanListProposal);
        addrs[5] = address(deployment.simpleLoanListProposal);

        addrs[6] = address(deployment.simpleLoanFungibleProposal);
        addrs[7] = address(deployment.simpleLoanFungibleProposal);

        addrs[8] = address(deployment.simpleLoanDutchAuctionProposal);
        addrs[9] = address(deployment.simpleLoanDutchAuctionProposal);

        bytes32[] memory tags = new bytes32[](10);
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

        TimelockController(payable(deployment.protocolTimelock)).scheduleAndExecute(
            GnosisSafeLike(deployment.daoSafe),
            address(deployment.hub),
            abi.encodeWithSignature("setTags(address[],bytes32[],bool)", addrs, tags, set)
        );
        console2.log("Tags set succeeded");
    }

/*
forge script script/PWN.s.sol:Setup \
--sig "setDefaultMetadata(string)" $METADATA \
--rpc-url $RPC_URL \
--private-key $PRIVATE_KEY \
--with-gas-price $(cast --to-wei 15 gwei) \
--broadcast
*/
    /// @dev Expecting to have daoSafe & config addresses set in the `deployments/latest.json`
    function setDefaultMetadata(string memory metadata) external {
        _loadDeployedAddresses();

        require(address(deployment.daoSafe) != address(0), "DAO safe not set");
        require(address(deployment.protocolTimelock) != address(0), "Protocol timelock not set");
        require(address(deployment.config) != address(0), "Config not set");

        vm.startBroadcast();

        TimelockController(payable(deployment.protocolTimelock)).scheduleAndExecute(
            GnosisSafeLike(deployment.daoSafe),
            address(deployment.config),
            abi.encodeWithSignature("setDefaultLOANMetadataUri(string)", metadata)
        );
        console2.log("Metadata set:", metadata);

        vm.stopBroadcast();
    }

}
