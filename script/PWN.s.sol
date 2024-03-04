// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Script.sol";

import { TransparentUpgradeableProxy, ITransparentUpgradeableProxy }
from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { GnosisSafeLike, GnosisSafeUtils } from "./lib/GnosisSafeUtils.sol";

import { PWNConfig } from "@pwn/config/PWNConfig.sol";
import { IPWNDeployer } from "@pwn/deployer/IPWNDeployer.sol";
import { PWNHub } from "@pwn/hub/PWNHub.sol";
import { PWNHubTags } from "@pwn/hub/PWNHubTags.sol";
import { PWNSimpleLoan } from "@pwn/loan/terms/simple/loan/PWNSimpleLoan.sol";
import { PWNSimpleLoanListOffer } from "@pwn/loan/terms/simple/factory/offer/PWNSimpleLoanListOffer.sol";
import { PWNSimpleLoanSimpleOffer } from "@pwn/loan/terms/simple/factory/offer/PWNSimpleLoanSimpleOffer.sol";
import { PWNSimpleLoanSimpleRequest } from "@pwn/loan/terms/simple/factory/request/PWNSimpleLoanSimpleRequest.sol";
import { PWNLOAN } from "@pwn/loan/token/PWNLOAN.sol";
import { PWNRevokedNonce } from "@pwn/nonce/PWNRevokedNonce.sol";
import { Deployments } from "@pwn/Deployments.sol";

import { T20 } from "@pwn-test/helper/token/T20.sol";
import { T721 } from "@pwn-test/helper/token/T721.sol";
import { T1155 } from "@pwn-test/helper/token/T1155.sol";


library PWNContractDeployerSalt {

    string internal constant VERSION = "1.2";

    // Singletons
    bytes32 internal constant CONFIG_V1 = keccak256("PWNConfigV1");
    bytes32 internal constant CONFIG_PROXY = keccak256("PWNConfigProxy");
    bytes32 internal constant HUB = keccak256("PWNHub");
    bytes32 internal constant LOAN = keccak256("PWNLOAN");
    bytes32 internal constant REVOKED_NONCE = keccak256("PWNRevokedNonce");

    // Loan types
    bytes32 internal constant SIMPLE_LOAN = keccak256("PWNSimpleLoan");

    // Offer types
    bytes32 internal constant SIMPLE_LOAN_SIMPLE_OFFER = keccak256("PWNSimpleLoanSimpleOffer");
    bytes32 internal constant SIMPLE_LOAN_LIST_OFFER = keccak256("PWNSimpleLoanListOffer");

    // Request types
    bytes32 internal constant SIMPLE_LOAN_SIMPLE_REQUEST = keccak256("PWNSimpleLoanSimpleRequest");

}


contract Deploy is Deployments, Script {
    using GnosisSafeUtils for GnosisSafeLike;

    function _protocolNotDeployedOnSelectedChain() internal pure override {
        revert("PWN: selected chain is not set in deployments.json");
    }

    function _deployAndTransferOwnership(
        bytes32 salt,
        address owner,
        bytes memory bytecode
    ) internal returns (address) {
        bool success = GnosisSafeLike(deployerSafe).execTransaction({
            to: address(deployer),
            data: abi.encodeWithSelector(
                IPWNDeployer.deployAndTransferOwnership.selector, salt, owner, bytecode
            )
        });
        require(success, "Deploy failed");
        return deployer.computeAddress(salt, keccak256(bytecode));
    }

    function _deploy(
        bytes32 salt,
        bytes memory bytecode
    ) internal returns (address) {
        bool success = GnosisSafeLike(deployerSafe).execTransaction({
            to: address(deployer),
            data: abi.encodeWithSelector(
                IPWNDeployer.deploy.selector, salt, bytecode
            )
        });
        require(success, "Deploy failed");
        return deployer.computeAddress(salt, keccak256(bytecode));
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
    /// @dev Expecting to have deployer, deployerSafe, protocolSafe, daoSafe, feeCollector & categoryRegistry addresses set in the `deployments.json`
    function deployProtocol() external {
        _loadDeployedAddresses();

        require(address(deployer) != address(0), "Deployer not set");
        require(deployerSafe != address(0), "Deployer safe not set");
        require(protocolSafe != address(0), "Protocol safe not set");
        require(daoSafe != address(0), "DAO safe not set");
        require(feeCollector != address(0), "Fee collector not set");
        require(address(categoryRegistry) != address(0), "Category registry not set");

        uint256 initialConfigHelper = vmSafe.envUint("INITIAL_CONFIG_HELPER");

        vm.startBroadcast();

        // Deploy protocol

        // - Config
        address configSingleton = _deploy({
            salt: PWNContractDeployerSalt.CONFIG_V1,
            bytecode: type(PWNConfig).creationCode
        });
        config = PWNConfig(_deploy({
            salt: PWNContractDeployerSalt.CONFIG_PROXY,
            bytecode: abi.encodePacked(
                type(TransparentUpgradeableProxy).creationCode,
                abi.encode(configSingleton, vm.addr(initialConfigHelper), "")
            )
        }));
        config.initialize(daoSafe, 0, feeCollector);

        vm.stopBroadcast();

        vm.broadcast(initialConfigHelper);
        ITransparentUpgradeableProxy(address(config)).changeAdmin(protocolSafe);

        vm.startBroadcast();

        // - Hub
        hub = PWNHub(_deployAndTransferOwnership({
            salt: PWNContractDeployerSalt.HUB,
            owner: protocolSafe,
            bytecode: type(PWNHub).creationCode
        }));

        // - LOAN token
        loanToken = PWNLOAN(_deploy({
            salt: PWNContractDeployerSalt.LOAN,
            bytecode: abi.encodePacked(
                type(PWNLOAN).creationCode,
                abi.encode(address(hub))
            )
        }));

        // - Revoked nonces
        revokedNonce = PWNRevokedNonce(_deploy({
            salt: PWNContractDeployerSalt.REVOKED_NONCE,
            bytecode: abi.encodePacked(
                type(PWNRevokedNonce).creationCode,
                abi.encode(address(hub), PWNHubTags.NONCE_MANAGER)
            )
        }));

        // - Loan types
        simpleLoan = PWNSimpleLoan(_deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN,
            bytecode: abi.encodePacked(
                type(PWNSimpleLoan).creationCode,
                abi.encode(
                    address(hub),
                    address(loanToken),
                    address(config),
                    address(revokedNonce),
                    address(categoryRegistry)
                )
            )
        }));

        // - Offers
        simpleLoanSimpleOffer = PWNSimpleLoanSimpleOffer(_deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN_SIMPLE_OFFER,
            bytecode: abi.encodePacked(
                type(PWNSimpleLoanSimpleOffer).creationCode,
                abi.encode(address(hub), address(revokedNonce))
            )
        }));
        simpleLoanListOffer = PWNSimpleLoanListOffer(_deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN_LIST_OFFER,
            bytecode: abi.encodePacked(
                type(PWNSimpleLoanListOffer).creationCode,
                abi.encode(address(hub), address(revokedNonce))
            )
        }));

        // - Requests
        simpleLoanSimpleRequest = PWNSimpleLoanSimpleRequest(_deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN_SIMPLE_REQUEST,
            bytecode: abi.encodePacked(
                type(PWNSimpleLoanSimpleRequest).creationCode,
                abi.encode(address(hub), address(revokedNonce))
            )
        }));

        console2.log("PWNConfig - singleton:", configSingleton);
        console2.log("PWNConfig - proxy:", address(config));
        console2.log("PWNHub:", address(hub));
        console2.log("PWNLOAN:", address(loanToken));
        console2.log("PWNRevokedNonce:", address(revokedNonce));
        console2.log("PWNSimpleLoan:", address(simpleLoan));
        console2.log("PWNSimpleLoanSimpleOffer:", address(simpleLoanSimpleOffer));
        console2.log("PWNSimpleLoanListOffer:", address(simpleLoanListOffer));
        console2.log("PWNSimpleLoanSimpleRequest:", address(simpleLoanSimpleRequest));

        vm.stopBroadcast();
    }

}


contract Setup is Deployments, Script {
    using GnosisSafeUtils for GnosisSafeLike;

    function _protocolNotDeployedOnSelectedChain() internal pure override {
        revert("PWN: selected chain is not set in deployments.json");
    }

/*
forge script script/PWN.s.sol:Setup \
--sig "setupProtocol()" \
--rpc-url $RPC_URL \
--private-key $PRIVATE_KEY \
--with-gas-price $(cast --to-wei 15 gwei) \
--broadcast
*/
    /// @dev Expecting to have protocol addresses set in the `deployments.json`
    function setupProtocol() external {
        _loadDeployedAddresses();

        vm.startBroadcast();

        _acceptOwnership(protocolSafe, address(hub));
        _setTags();

        vm.stopBroadcast();
    }

/*
forge script script/PWN.s.sol:Setup \
--sig "acceptOwnership(address,address)" $SAFE $CONTRACT \
--rpc-url $RPC_URL \
--private-key $PRIVATE_KEY \
--with-gas-price $(cast --to-wei 15 gwei) \
--broadcast
*/
    /// @dev Not expecting any addresses set in the `deployments.json`
    function acceptOwnership(address safe, address contract_) external {
        vm.startBroadcast();
        _acceptOwnership(safe, contract_);
        vm.stopBroadcast();
    }

    function _acceptOwnership(address safe, address contract_) internal {
        bool success = GnosisSafeLike(safe).execTransaction({
            to: contract_,
            data: abi.encodeWithSignature("acceptOwnership()")
        });

        require(success, "Accept ownership tx failed");
        console2.log("Accept ownership tx succeeded");
    }

/*
forge script script/PWN.s.sol:Setup \
--sig "setTags()" \
--rpc-url $RPC_URL \
--private-key $PRIVATE_KEY \
--with-gas-price $(cast --to-wei 15 gwei) \
--broadcast
*/
    /// @dev Expecting to have protocol addresses set in the `deployments.json`
    function setTags() external {
        _loadDeployedAddresses();

        vm.startBroadcast();
        _setTags();
        vm.stopBroadcast();
    }

    function _setTags() internal {
        address[] memory addrs = new address[](8);
        addrs[0] = address(simpleLoan);
        addrs[1] = address(simpleLoan);
        addrs[2] = address(simpleLoanSimpleOffer);
        addrs[3] = address(simpleLoanSimpleOffer);
        addrs[4] = address(simpleLoanListOffer);
        addrs[5] = address(simpleLoanListOffer);
        addrs[6] = address(simpleLoanSimpleRequest);
        addrs[7] = address(simpleLoanSimpleRequest);

        bytes32[] memory tags = new bytes32[](8);
        tags[0] = PWNHubTags.ACTIVE_LOAN;
        tags[1] = PWNHubTags.NONCE_MANAGER;
        tags[2] = PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY;
        tags[3] = PWNHubTags.NONCE_MANAGER;
        tags[4] = PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY;
        tags[5] = PWNHubTags.NONCE_MANAGER;
        tags[6] = PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY;
        tags[7] = PWNHubTags.NONCE_MANAGER;

        bool success = GnosisSafeLike(protocolSafe).execTransaction({
            to: address(hub),
            data: abi.encodeWithSignature(
                "setTags(address[],bytes32[],bool)", addrs, tags, true
            )
        });

        require(success, "Tags set failed");
        console2.log("Tags set succeeded");
    }

/*
forge script script/PWN.s.sol:Setup \
--sig "setMetadata(address,string)" $LOAN_CONTRACT $METADATA \
--rpc-url $RPC_URL \
--private-key $PRIVATE_KEY \
--with-gas-price $(cast --to-wei 15 gwei) \
--broadcast
*/
    /// @dev Expecting to have daoSafe & config addresses set in the `deployments.json`
    function setMetadata(address address_, string memory metadata) external {
        _loadDeployedAddresses();

        vm.startBroadcast();

        bool success = GnosisSafeLike(daoSafe).execTransaction({
            to: address(config),
            data: abi.encodeWithSignature(
                "setLoanMetadataUri(address,string)", address_, metadata
            )
        });

        require(success, "Set metadata failed");
        console2.log("Metadata set:", metadata);

        vm.stopBroadcast();
    }

}
