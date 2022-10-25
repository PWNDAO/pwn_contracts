// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Script.sol";

import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "@pwn/config/PWNConfig.sol";
import "@pwn/deployer/PWNContractDeployerSalt.sol";
import "@pwn/deployer/PWNDeployer.sol";
import "@pwn/hub/PWNHub.sol";
import "@pwn/hub/PWNHubTags.sol";
import "@pwn/loan/type/PWNSimpleLoan.sol";
import "@pwn/loan/PWNLOAN.sol";
import "@pwn/loan-factory/simple-loan/offer/PWNSimpleLoanListOffer.sol";
import "@pwn/loan-factory/simple-loan/offer/PWNSimpleLoanSimpleOffer.sol";
import "@pwn/loan-factory/simple-loan/request/PWNSimpleLoanSimpleRequest.sol";
import "@pwn/loan-factory/PWNRevokedNonce.sol";


/*

// Deployer
forge script script/PWN.s.sol:Deploy \
--sig "deployDeployer(address)" $ADMIN_ADDRESS \
--rpc-url $GOERLI_URL \
--private-key $PRIVATE_KEY_TESTNET \
--broadcast

// Protocol
forge script script/PWN.s.sol:Deploy \
--sig "deployProtocol(address,address,address,address)" $PWN_DEPLOYER $ADMIN_ADDRESS $OWNER_ADDRESS $FEE_COLLECTOR_ADDRESS \
--rpc-url $GOERLI_URL \
--private-key $PRIVATE_KEY_TESTNET \
--broadcast

*/

contract Deploy is Script {

    function deployDeployer(address owner) external {
        vm.startBroadcast();
        new PWNDeployer(owner);
        vm.stopBroadcast();
    }

    function deployProtocol(
        address deployer_,
        address admin,
        address owner,
        address feeCollector
    ) external {
        vm.startBroadcast();

        PWNDeployer deployer = PWNDeployer(deployer_);

        // Deploy realm

        // - Config
        PWNConfig configSingleton = new PWNConfig();
        PWNConfig config = PWNConfig(deployer.deploy({
            salt: PWNContractDeployerSalt.CONFIG,
            bytecode: abi.encodePacked(
                type(TransparentUpgradeableProxy).creationCode,
                abi.encode(
                    address(configSingleton),
                    admin,
                    abi.encodeWithSignature("initialize(address,uint16,address)", owner, 0, feeCollector)
                )
            )
        }));

        // - Hub
        PWNHub hub = PWNHub(deployer.deploy({
            salt: PWNContractDeployerSalt.HUB,
            bytecode: abi.encodePacked(
                type(PWNHub).creationCode,
                abi.encode(admin)
            )
        }));

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

        // Set hub tags
        hub.setTag(address(simpleLoan), PWNHubTags.ACTIVE_LOAN, true);

        hub.setTag(address(simpleOffer), PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY, true);
        hub.setTag(address(simpleOffer), PWNHubTags.LOAN_OFFER, true);

        hub.setTag(address(listOffer), PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY, true);
        hub.setTag(address(listOffer), PWNHubTags.LOAN_OFFER, true);

        hub.setTag(address(simpleRequest), PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY, true);
        hub.setTag(address(simpleRequest), PWNHubTags.LOAN_REQUEST, true);


        vm.stopBroadcast();
    }

}

contract Scripts {

}
