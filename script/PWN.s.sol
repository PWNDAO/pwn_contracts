// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Script.sol";

import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

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


/*

// Deployer
forge script script/PWN.s.sol:Deploy \
--sig "deployDeployerBroadcast(address)" $ADMIN \
--rpc-url $GOERLI_URL \
--private-key $PRIVATE_KEY_TESTNET \
--broadcast

// Protocol
forge script script/PWN.s.sol:Deploy \
--sig "deployProtocolBroadcast(address,address,address,address)" $PWN_DEPLOYER $ADMIN $DAO $FEE_COLLECTOR \
--rpc-url $GOERLI_URL \
--private-key $PRIVATE_KEY_TESTNET \
--broadcast

*/

contract Deploy is Script {

    function deployDeployerBroadcast(address admin) external {
        vm.startBroadcast();
        deployDeployer(admin);
        vm.stopBroadcast();
    }

    function deployProtocolBroadcast(
        address deployer,
        address admin,
        address dao,
        address feeCollector
    ) external {
        vm.startBroadcast();
        deployProtocol(deployer, admin, dao, feeCollector);
        vm.stopBroadcast();
    }


    function deployDeployer(address admin) public returns (PWNDeployer) {
        return new PWNDeployer(admin);
    }

    function deployProtocol(
        address deployer_,
        address admin,
        address dao,
        address feeCollector
    ) public {
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
                    abi.encodeWithSignature("initialize(address,uint16,address)", dao, 0, feeCollector)
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

}
