// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Script.sol";

import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/contracts/governance/TimelockController.sol";

import "@pwn/config/PWNConfig.sol";
import "@pwn/deployer/PWNContractDeployerSalt.sol";
import "@pwn/deployer/PWNDeployer.sol";
import "@pwn/hub/PWNHub.sol";
import "@pwn/hub/PWNHubTags.sol";
import "@pwn/loan/terms/simple/loan/PWNSimpleLoan.sol";
import "@pwn/loan/terms/simple/factory/offer/PWNSimpleLoanListOffer.sol";
import "@pwn/loan/terms/simple/factory/offer/PWNSimpleLoanSimpleOffer.sol";
import "@pwn/loan/terms/simple/factory/request/PWNSimpleLoanSimpleRequest.sol";
import "@pwn/loan/token/PWNLOAN.sol";
import "@pwn/nonce/PWNRevokedNonce.sol";

import "@pwn-test/helper/token/T20.sol";
import "@pwn-test/helper/token/T721.sol";
import "@pwn-test/helper/token/T1155.sol";


/*

// Deployer
forge script script/PWN.s.sol:Deploy \
--sig "deployDeployer(address)" $ADMIN \
--rpc-url $RPC_URL \
--private-key $PRIVATE_KEY \
--verify --etherscan-api-key $ETHERSCAN_API_KEY \
--broadcast

// Protocol
forge script script/PWN.s.sol:Deploy \
--sig "deployProtocol(address,address,address,address)" $PWN_DEPLOYER $ADMIN $DAO $FEE_COLLECTOR \
--rpc-url $RPC_URL \
--private-key $PRIVATE_KEY \
--verify --etherscan-api-key $ETHERSCAN_API_KEY \
--broadcast

// Test tokens
forge script script/PWN.s.sol:Deploy \
--sig "deployTestTokens()" \
--rpc-url $RPC_URL \
--private-key $PRIVATE_KEY \
--verify --etherscan-api-key $ETHERSCAN_API_KEY \
--broadcast

// Timelocks
forge script script/PWN.s.sol:Deploy --sig "timelockControllerProtocol()"
forge script script/PWN.s.sol:Deploy --sig "timelockControllerProduct()"

*/
contract Deploy is Script {

    function deployDeployer(address admin) external {
        vm.startBroadcast();

        PWNDeployer deployer = new PWNDeployer();
        deployer.transferOwnership(admin);

        vm.stopBroadcast();
    }

    function deployProtocol(
        address deployer_,
        address admin,
        address dao,
        address feeCollector
    ) external {
        vm.startBroadcast();

        PWNDeployer deployer = PWNDeployer(deployer_);

        // Deploy protocol

        // - Config
        address configSingleton = deployer.deploy({
            salt: PWNContractDeployerSalt.CONFIG_V1,
            bytecode: type(PWNConfig).creationCode
        });
        PWNConfig config = PWNConfig(deployer.deploy({
            salt: PWNContractDeployerSalt.CONFIG_PROXY,
            bytecode: abi.encodePacked(
                type(TransparentUpgradeableProxy).creationCode,
                abi.encode(
                    configSingleton,
                    admin,
                    abi.encodeWithSignature("initialize(address,uint16,address)", dao, 0, feeCollector)
                )
            )
        }));

        // - Hub
        PWNHub hub = PWNHub(deployer.deployAndTransferOwnership({
            salt: PWNContractDeployerSalt.HUB,
            owner: msg.sender, // To be able to set tags at the end of this script, otherwise `admin`
            bytecode: type(PWNHub).creationCode
        }));
        hub.acceptOwnership(); // Because PWNHub is Ownable2Step contract

        // - LOAN token
        PWNLOAN loanToken = PWNLOAN(deployer.deploy({
            salt: PWNContractDeployerSalt.LOAN,
            bytecode: abi.encodePacked(
                type(PWNLOAN).creationCode,
                abi.encode(address(hub))
            )
        }));

        // - Revoked nonces
        PWNRevokedNonce revokedOfferNonce = PWNRevokedNonce(deployer.deploy({
            salt: PWNContractDeployerSalt.REVOKED_OFFER_NONCE,
            bytecode: abi.encodePacked(
                type(PWNRevokedNonce).creationCode,
                abi.encode(address(hub), PWNHubTags.LOAN_OFFER)
            )
        }));
        PWNRevokedNonce revokedRequestNonce = PWNRevokedNonce(deployer.deploy({
            salt: PWNContractDeployerSalt.REVOKED_REQUEST_NONCE,
            bytecode: abi.encodePacked(
                type(PWNRevokedNonce).creationCode,
                abi.encode(address(hub), PWNHubTags.LOAN_REQUEST)
            )
        }));

        // - Loan types
        PWNSimpleLoan simpleLoan = PWNSimpleLoan(deployer.deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN_V1,
            bytecode: abi.encodePacked(
                type(PWNSimpleLoan).creationCode,
                abi.encode(address(hub), address(loanToken), address(config))
            )
        }));

        // - Offers
        PWNSimpleLoanSimpleOffer simpleOffer = PWNSimpleLoanSimpleOffer(deployer.deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN_SIMPLE_OFFER_V1,
            bytecode: abi.encodePacked(
                type(PWNSimpleLoanSimpleOffer).creationCode,
                abi.encode(address(hub), address(revokedOfferNonce))
            )
        }));
        PWNSimpleLoanListOffer listOffer = PWNSimpleLoanListOffer(deployer.deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN_LIST_OFFER_V1,
            bytecode: abi.encodePacked(
                type(PWNSimpleLoanListOffer).creationCode,
                abi.encode(address(hub), address(revokedOfferNonce))
            )
        }));

        // - Requests
        PWNSimpleLoanSimpleRequest simpleRequest = PWNSimpleLoanSimpleRequest(deployer.deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN_SIMPLE_REQUEST_V1,
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
        console2.log("PWNSimpleLoanSimpleOffer:", address(simpleOffer));
        console2.log("PWNSimpleLoanListOffer:", address(listOffer));
        console2.log("PWNSimpleLoanSimpleRequest:", address(simpleRequest));

        // Set hub tags
        {
            address[] memory addrs = new address[](7);
            addrs[0] = address(simpleLoan);
            addrs[1] = address(simpleOffer);
            addrs[2] = address(simpleOffer);
            addrs[3] = address(listOffer);
            addrs[4] = address(listOffer);
            addrs[5] = address(simpleRequest);
            addrs[6] = address(simpleRequest);

            bytes32[] memory tags = new bytes32[](7);
            tags[0] = PWNHubTags.ACTIVE_LOAN;
            tags[1] = PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY;
            tags[2] = PWNHubTags.LOAN_OFFER;
            tags[3] = PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY;
            tags[4] = PWNHubTags.LOAN_OFFER;
            tags[5] = PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY;
            tags[6] = PWNHubTags.LOAN_REQUEST;

            hub.setTags(addrs, tags, true);
        }

        hub.transferOwnership(admin);

        vm.stopBroadcast();
    }

    function deployTestTokens() external {
        vm.startBroadcast();

        T20 t20 = new T20();
        T721 t721 = new T721();
        T1155 t1155 = new T1155();
        T20 loanAsset = new T20();

        console2.log("T20:", address(t20));
        console2.log("T721:", address(t721));
        console2.log("T1155:", address(t1155));
        console2.log("Loan asset:", address(loanAsset));

        vm.stopBroadcast();
    }

    function timelockControllerProtocol() external view {
        address[] memory proposers = new address[](1);
        proposers[0] = 0x61a77B19b7F4dB82222625D7a969698894d77473; // protocol safe
        address[] memory executors = new address[](1);

        bytes32 salt = PWNContractDeployerSalt.PROTOCOL_TEAM_TIMELOCK_CONTROLLER;
        bytes memory deployProtocolTimelockData = abi.encodePacked(
            type(TimelockController).creationCode,
            abi.encode(type(uint256).max, proposers, executors, address(0))
        );

        console2.log("Deploy protocol timelock controller salt:");
        console2.logBytes32(salt);
        console2.log("Deploy protocol timelock controller data:");
        console2.logBytes(deployProtocolTimelockData);
    }

    function timelockControllerProduct() external view {
        address[] memory proposers = new address[](1);
        proposers[0] = 0xd56635c0E91D31F88B89F195D3993a9e34516e59; // product safe
        address[] memory executors = new address[](1);

        bytes32 salt = PWNContractDeployerSalt.PRODUCT_TEAM_TIMELOCK_CONTROLLER;
        bytes memory deployProductTimelockData = abi.encodePacked(
            type(TimelockController).creationCode,
            abi.encode(uint256(0), proposers, executors, address(0))
        );

        console2.log("Deploy product timelock controller salt:");
        console2.logBytes32(salt);
        console2.log("Deploy product timelock controller data:");
        console2.logBytes(deployProductTimelockData);
    }

}
