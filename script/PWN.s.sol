// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Script.sol";

import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/contracts/governance/TimelockController.sol";

import "@pwn/config/PWNConfig.sol";
import "@pwn/deployer/IPWNDeployer.sol";
import "@pwn/deployer/PWNContractDeployerSalt.sol";
import "@pwn/hub/PWNHub.sol";
import "@pwn/hub/PWNHubTags.sol";
import "@pwn/loan/terms/simple/loan/PWNSimpleLoan.sol";
import "@pwn/loan/terms/simple/factory/offer/PWNSimpleLoanListOffer.sol";
import "@pwn/loan/terms/simple/factory/offer/PWNSimpleLoanSimpleOffer.sol";
import "@pwn/loan/terms/simple/factory/request/PWNSimpleLoanSimpleRequest.sol";
import "@pwn/loan/token/PWNLOAN.sol";
import "@pwn/nonce/PWNRevokedNonce.sol";
import "@pwn/Deployments.sol";

import "@pwn-test/helper/token/T20.sol";
import "@pwn-test/helper/token/T721.sol";
import "@pwn-test/helper/token/T1155.sol";


interface GnosisSafeLike {
    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures
    ) external payable returns (bool success);
}


library GnosisSafeUtils {

    function execTransaction(GnosisSafeLike safe, address to, bytes memory data) internal returns (bool) {
        uint256 ownerValue = uint256(uint160(msg.sender));
        return safe.execTransaction({
            to: to,
            value: 0,
            data: data,
            operation: 0,
            safeTxGas: 0,
            baseGas: 0,
            gasPrice: 0,
            gasToken: address(0),
            refundReceiver: payable(0),
            signatures: abi.encodePacked(ownerValue, bytes32(0), uint8(1))
        });
    }

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
    /// @dev Expecting to have deployer, deployerSafe, protocolSafe, daoSafe & feeCollector addresses set in the `deployments.json`
    function deployProtocol() external {
        _loadDeployedAddresses();

        require(address(deployer) != address(0), "Deployer not set");
        require(deployerSafe != address(0), "Deployer safe not set");
        require(protocolSafe != address(0), "Protocol safe not set");
        require(daoSafe != address(0), "DAO safe not set");
        require(feeCollector != address(0), "Fee collector not set");

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
                abi.encode(
                    configSingleton,
                    protocolSafe,
                    abi.encodeWithSignature("initialize(address,uint16,address)", daoSafe, 0, feeCollector)
                )
            )
        }));

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
        revokedOfferNonce = PWNRevokedNonce(_deploy({
            salt: PWNContractDeployerSalt.REVOKED_OFFER_NONCE,
            bytecode: abi.encodePacked(
                type(PWNRevokedNonce).creationCode,
                abi.encode(address(hub), PWNHubTags.LOAN_OFFER)
            )
        }));
        revokedRequestNonce = PWNRevokedNonce(_deploy({
            salt: PWNContractDeployerSalt.REVOKED_REQUEST_NONCE,
            bytecode: abi.encodePacked(
                type(PWNRevokedNonce).creationCode,
                abi.encode(address(hub), PWNHubTags.LOAN_REQUEST)
            )
        }));

        // - Loan types
        simpleLoan = PWNSimpleLoan(_deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN,
            bytecode: abi.encodePacked(
                type(PWNSimpleLoan).creationCode,
                abi.encode(address(hub), address(loanToken), address(config))
            )
        }));

        // - Offers
        simpleLoanSimpleOffer = PWNSimpleLoanSimpleOffer(_deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN_SIMPLE_OFFER,
            bytecode: abi.encodePacked(
                type(PWNSimpleLoanSimpleOffer).creationCode,
                abi.encode(address(hub), address(revokedOfferNonce))
            )
        }));
        simpleLoanListOffer = PWNSimpleLoanListOffer(_deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN_LIST_OFFER,
            bytecode: abi.encodePacked(
                type(PWNSimpleLoanListOffer).creationCode,
                abi.encode(address(hub), address(revokedOfferNonce))
            )
        }));

        // - Requests
        simpleLoanSimpleRequest = PWNSimpleLoanSimpleRequest(_deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN_SIMPLE_REQUEST,
            bytecode: abi.encodePacked(
                type(PWNSimpleLoanSimpleRequest).creationCode,
                abi.encode(address(hub), address(revokedRequestNonce))
            )
        }));

        console2.log("PWNConfig - singleton:", configSingleton);
        console2.log("PWNConfig - proxy:", address(config));
        console2.log("PWNHub:", address(hub));
        console2.log("PWNLOAN:", address(loanToken));
        console2.log("PWNRevokedNonce (offer):", address(revokedOfferNonce));
        console2.log("PWNRevokedNonce (request):", address(revokedRequestNonce));
        console2.log("PWNSimpleLoan:", address(simpleLoan));
        console2.log("PWNSimpleLoanSimpleOffer:", address(simpleLoanSimpleOffer));
        console2.log("PWNSimpleLoanListOffer:", address(simpleLoanListOffer));
        console2.log("PWNSimpleLoanSimpleRequest:", address(simpleLoanSimpleRequest));

        vm.stopBroadcast();
    }

/*
forge script script/PWN.s.sol:Deploy \
--sig "deployProtocolTimelockController()" \
--rpc-url $RPC_URL \
--private-key $PRIVATE_KEY \
--with-gas-price $(cast --to-wei 15 gwei) \
--verify --etherscan-api-key $ETHERSCAN_API_KEY \
--broadcast
*/
    /// @dev Expecting to have deployer, deployerSafe & protocolSafe addresses set in the `deployments.json`
    function deployProtocolTimelockController() external {
        _loadDeployedAddresses();

        vm.startBroadcast();

        address[] memory proposers = new address[](1);
        proposers[0] = protocolSafe;
        address[] memory executors = new address[](1);
        executors[0] = address(0);

        address timelock = _deploy({
            salt: PWNContractDeployerSalt.PROTOCOL_TEAM_TIMELOCK_CONTROLLER,
            bytecode: abi.encodePacked(
                type(TimelockController).creationCode,
                abi.encode(uint256(0), proposers, executors, address(0))
            )
        });
        console2.log("Protocol timelock deployed:", timelock);

        vm.stopBroadcast();
    }

/*
forge script script/PWN.s.sol:Deploy \
--sig "deployProductTimelockController()" \
--rpc-url $RPC_URL \
--private-key $PRIVATE_KEY \
--with-gas-price $(cast --to-wei 15 gwei) \
--verify --etherscan-api-key $ETHERSCAN_API_KEY \
--broadcast
*/
    /// @dev Expecting to have deployer, deployerSafe & daoSafe addresses set in the `deployments.json`
    function deployProductTimelockController() external {
        _loadDeployedAddresses();

        vm.startBroadcast();

        address[] memory proposers = new address[](1);
        proposers[0] = daoSafe;
        address[] memory executors = new address[](1);
        executors[0] = address(0);

        address timelock = _deploy({
            salt: PWNContractDeployerSalt.PRODUCT_TEAM_TIMELOCK_CONTROLLER,
            bytecode: abi.encodePacked(
                type(TimelockController).creationCode,
                abi.encode(uint256(0), proposers, executors, address(0))
            )
        });
        console2.log("Product timelock deployed:", timelock);

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

        _initializeConfigImpl();
        _acceptOwnership(protocolSafe, address(hub));
        _setTags();

        vm.stopBroadcast();
    }

/*
forge script script/PWN.s.sol:Setup \
--sig "initializeConfigImpl()" \
--rpc-url $RPC_URL \
--private-key $PRIVATE_KEY \
--with-gas-price $(cast --to-wei 15 gwei) \
--broadcast
*/
    /// @dev Expecting to have configSingleton address set in the `deployments.json`
    function initializeConfigImpl() external {
        _loadDeployedAddresses();

        vm.startBroadcast();
        _initializeConfigImpl();
        vm.stopBroadcast();
    }

    function _initializeConfigImpl() internal {
        address deadAddr = 0x000000000000000000000000000000000000dEaD;
        configSingleton.initialize(deadAddr, 0, deadAddr);

        console2.log("Config impl initialized");
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


/*
forge script script/PWN.s.sol:Setup \
--sig "setProtocolTimelock()" \
--rpc-url $RPC_URL \
--private-key $PRIVATE_KEY \
--with-gas-price $(cast --to-wei 15 gwei) \
--broadcast
*/
    /// @dev Expecting to have protocol, protocolSafe & protocolTimelock addresses set in the `deployments.json`
    function setProtocolTimelock() external {
        _loadDeployedAddresses();

        uint256 protocolTimelockMinDelay = 345_600;

        vm.startBroadcast();

        // set PWNConfig admin
        bool success;
        success = GnosisSafeLike(protocolSafe).execTransaction({
            to: address(config),
            data: abi.encodeWithSignature("changeAdmin(address)", protocolTimelock)
        });
        require(success, "PWN: change admin failed");

        // transfer PWNHub owner
        success = GnosisSafeLike(protocolSafe).execTransaction({
            to: address(hub),
            data: abi.encodeWithSignature("transferOwnership(address)", protocolTimelock)
        });
        require(success, "PWN: change owner failed");

        // accept PWNHub owner
        success = GnosisSafeLike(protocolSafe).execTransaction({
            to: address(protocolTimelock),
            data: abi.encodeWithSignature(
                "schedule(address,uint256,bytes,bytes32,bytes32,uint256)",
                address(hub), 0, abi.encodeWithSignature("acceptOwnership()"), 0, 0, 0
            )
        });
        require(success, "PWN: schedule failed");

        TimelockController(payable(protocolTimelock)).execute({
            target: address(hub),
            value: 0,
            payload: abi.encodeWithSignature("acceptOwnership()"),
            predecessor: 0,
            salt: 0
        });

        // Set min delay
        success = GnosisSafeLike(protocolSafe).execTransaction({
            to: address(protocolTimelock),
            data: abi.encodeWithSignature(
                "schedule(address,uint256,bytes,bytes32,bytes32,uint256)",
                address(protocolTimelock), 0, abi.encodeWithSignature("updateDelay(uint256)", protocolTimelockMinDelay), 0, 0, 0
            )
        });
        require(success, "PWN: update delay failed");

        TimelockController(payable(protocolTimelock)).execute({
            target: protocolTimelock,
            value: 0,
            payload: abi.encodeWithSignature("updateDelay(uint256)", protocolTimelockMinDelay),
            predecessor: 0,
            salt: 0
        });

        console2.log("Protocol timelock set");

        vm.stopBroadcast();
    }

/*
forge script script/PWN.s.sol:Setup \
--sig "setProductTimelock()" \
--rpc-url $RPC_URL \
--private-key $PRIVATE_KEY \
--with-gas-price $(cast --to-wei 15 gwei) \
--broadcast
*/
    /// @dev Expecting to have protocol, daoSafe & productTimelock addresses set in the `deployments.json`
    function setProductTimelock() external {
        _loadDeployedAddresses();

        uint256 productTimelockMinDelay = 345_600;

        vm.startBroadcast();

        // transfer PWNConfig owner
        bool success;
        success = GnosisSafeLike(daoSafe).execTransaction({
            to: address(config),
            data: abi.encodeWithSignature("transferOwnership(address)", productTimelock)
        });
        require(success, "PWN: change owner failed");

        // accept PWNConfig owner
        success = GnosisSafeLike(daoSafe).execTransaction({
            to: address(productTimelock),
            data: abi.encodeWithSignature(
                "schedule(address,uint256,bytes,bytes32,bytes32,uint256)",
                address(config), 0, abi.encodeWithSignature("acceptOwnership()"), 0, 0, 0
            )
        });
        require(success, "PWN: schedule failed");

        TimelockController(payable(productTimelock)).execute({
            target: address(config),
            value: 0,
            payload: abi.encodeWithSignature("acceptOwnership()"),
            predecessor: 0,
            salt: 0
        });

        // Set min delay
        success = GnosisSafeLike(daoSafe).execTransaction({
            to: address(productTimelock),
            data: abi.encodeWithSignature(
                "schedule(address,uint256,bytes,bytes32,bytes32,uint256)",
                address(productTimelock), 0, abi.encodeWithSignature("updateDelay(uint256)", productTimelockMinDelay), 0, 0, 0
            )
        });
        require(success, "PWN: update delay failed");

        TimelockController(payable(productTimelock)).execute({
            target: productTimelock,
            value: 0,
            payload: abi.encodeWithSignature("updateDelay(uint256)", productTimelockMinDelay),
            predecessor: 0,
            salt: 0
        });

        console2.log("Product timelock set");

        vm.stopBroadcast();
    }

}
