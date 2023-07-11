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
    function isOwner(address owner) external view returns (bool);
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


contract Deploy is Deployments, Script {

    function _protocolNotDeployedOnSelectedChain() internal pure override {
        revert("PWN: selected chain is not set in deployments.json");
    }

/*
forge script script/PWN.s.sol:Deploy \
--sig "deployProtocol()" \
--rpc-url $RPC_URL \
--private-key $PRIVATE_KEY \
--verify --etherscan-api-key $ETHERSCAN_API_KEY \
--broadcast
*/
    /// @dev Expecting to have deployer, protocolSafe, daoSafe & feeCollector addresses set in the `deployments.json`
    function deployProtocol() external {
        _loadDeployedAddresses();

        vm.startBroadcast();

        // Deploy protocol

        // - Config
        address configSingleton = deployer.deploy({
            salt: PWNContractDeployerSalt.CONFIG_V1,
            bytecode: type(PWNConfig).creationCode
        });
        config = PWNConfig(deployer.deploy({
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
        hub = PWNHub(deployer.deployAndTransferOwnership({
            salt: PWNContractDeployerSalt.HUB,
            owner: protocolSafe,
            bytecode: type(PWNHub).creationCode
        }));

        // - LOAN token
        loanToken = PWNLOAN(deployer.deploy({
            salt: PWNContractDeployerSalt.LOAN,
            bytecode: abi.encodePacked(
                type(PWNLOAN).creationCode,
                abi.encode(address(hub))
            )
        }));

        // - Revoked nonces
        revokedOfferNonce = PWNRevokedNonce(deployer.deploy({
            salt: PWNContractDeployerSalt.REVOKED_OFFER_NONCE,
            bytecode: abi.encodePacked(
                type(PWNRevokedNonce).creationCode,
                abi.encode(address(hub), PWNHubTags.LOAN_OFFER)
            )
        }));
        revokedRequestNonce = PWNRevokedNonce(deployer.deploy({
            salt: PWNContractDeployerSalt.REVOKED_REQUEST_NONCE,
            bytecode: abi.encodePacked(
                type(PWNRevokedNonce).creationCode,
                abi.encode(address(hub), PWNHubTags.LOAN_REQUEST)
            )
        }));

        // - Loan types
        simpleLoan = PWNSimpleLoan(deployer.deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN,
            bytecode: abi.encodePacked(
                type(PWNSimpleLoan).creationCode,
                abi.encode(address(hub), address(loanToken), address(config))
            )
        }));

        // - Offers
        simpleLoanSimpleOffer = PWNSimpleLoanSimpleOffer(deployer.deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN_SIMPLE_OFFER,
            bytecode: abi.encodePacked(
                type(PWNSimpleLoanSimpleOffer).creationCode,
                abi.encode(address(hub), address(revokedOfferNonce))
            )
        }));
        simpleLoanListOffer = PWNSimpleLoanListOffer(deployer.deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN_LIST_OFFER,
            bytecode: abi.encodePacked(
                type(PWNSimpleLoanListOffer).creationCode,
                abi.encode(address(hub), address(revokedOfferNonce))
            )
        }));

        // - Requests
        simpleLoanSimpleRequest = PWNSimpleLoanSimpleRequest(deployer.deploy({
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
--verify --etherscan-api-key $ETHERSCAN_API_KEY \
--broadcast
*/
    /// @dev Expecting to have deployer & protocolSafe addresses set in the `deployments.json`
    function deployProtocolTimelockController() external {
        _loadDeployedAddresses();

        vm.startBroadcast();

        address[] memory proposers = new address[](1);
        proposers[0] = protocolSafe;
        address[] memory executors = new address[](1);

        address timelock = deployer.deploy({
            salt: PWNContractDeployerSalt.PROTOCOL_TEAM_TIMELOCK_CONTROLLER,
            bytecode: abi.encodePacked(
                type(TimelockController).creationCode,
                abi.encode(uint256(0), proposers, executors, address(0))
            )
        });

        console2.log("Deployed protocol timelock controller:", timelock);

        vm.stopBroadcast();
    }

/*
forge script script/PWN.s.sol:Deploy \
--sig "deployProductTimelockController()" \
--rpc-url $RPC_URL \
--private-key $PRIVATE_KEY \
--verify --etherscan-api-key $ETHERSCAN_API_KEY \
--broadcast
*/
    /// @dev Expecting to have deployer & daoSafe addresses set in the `deployments.json`
    function deployProductTimelockController() external {
        _loadDeployedAddresses();

        vm.startBroadcast();

        address[] memory proposers = new address[](1);
        proposers[0] = daoSafe;
        address[] memory executors = new address[](1);

        address timelock = deployer.deploy({
            salt: PWNContractDeployerSalt.PRODUCT_TEAM_TIMELOCK_CONTROLLER,
            bytecode: abi.encodePacked(
                type(TimelockController).creationCode,
                abi.encode(uint256(0), proposers, executors, address(0))
            )
        });

        console2.log("Deployed product timelock controller:", timelock);

        vm.stopBroadcast();
    }

/*
forge script script/PWN.s.sol:Deploy \
--sig "deployTestTokens()" \
--rpc-url $RPC_URL \
--private-key $PRIVATE_KEY \
--verify --etherscan-api-key $ETHERSCAN_API_KEY \
--broadcast
*/
    /// @dev Not expecting any addresses set in the `deployments.json`
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

}


contract Setup is Deployments, Script {

    function _protocolNotDeployedOnSelectedChain() internal pure override {
        revert("PWN: selected chain is not set in deployments.json");
    }

    function _gnosisSafeTx(address safe, address to, bytes memory data) private returns (bool) {
        uint256 ownerValue = uint256(uint160(msg.sender));
        return GnosisSafeLike(safe).execTransaction({
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


// Initialize config implementation
// $DEAD_ADDR = 0x000000000000000000000000000000000000dEaD
// cast send --rpc-url $RPC_URL --private-key $PRIVATE_KEY $CONFIG_IMPL_ADDRESS 'initialize(address,uint16,address)' $DEAD_ADDR 0 $DEAD_ADDR


/*
forge script script/PWN.s.sol:Setup \
--sig "setTags()" \
--rpc-url $LOCAL_URL \
--private-key $PRIVATE_KEY \
--broadcast
*/
    /// @dev Expecting to have protocol addresses set in the `deployments.json`
    function setTags() external {
        _loadDeployedAddresses();

        vm.startBroadcast();

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

        bool success = _gnosisSafeTx({
            safe: protocolSafe,
            to: address(hub),
            data: abi.encodeWithSignature(
                "setTags(address[],bytes32[],bool)", addrs, tags, true
            )
        });

        if (success)
            console2.log("Tags set succeeded");
        else
            console2.log("Tags set failed");

        vm.stopBroadcast();
    }

/*
forge script script/PWN.s.sol:Setup \
--sig "acceptOwnership(address,address)" $SAFE $CONTRACT \
--rpc-url $RPC_URL \
--private-key $PRIVATE_KEY \
--broadcast
*/
    /// @dev Not expecting any addresses set in the `deployments.json`
    function acceptOwnership(address safe, address contract_) external {
        vm.startBroadcast();

        bool success = _gnosisSafeTx({
            safe: safe,
            to: contract_,
            data: abi.encodeWithSignature("acceptOwnership()")
        });
        if (success)
            console2.log("Accept ownership tx succeeded");
        else
            console2.log("Accept ownership tx failed");

        vm.stopBroadcast();
    }

/*
forge script script/PWN.s.sol:Setup \
--sig "swapSafeOwner(address,address)" $SAFE $NEW_OWNER \
--rpc-url $RPC_URL \
--private-key $PRIVATE_KEY \
--broadcast
*/
    /// @dev Not expecting any addresses set in the `deployments.json`
    function swapSafeOwner(address safe, address newOwner) external {
        vm.startBroadcast();

        bool success = _gnosisSafeTx({
            safe: safe,
            to: safe,
            data: abi.encodeWithSignature(
                "swapOwner(address,address,address)", address(0x1), msg.sender, newOwner
            )
        });

        if (success && GnosisSafeLike(safe).isOwner(newOwner))
            console2.log("Swap owner tx succeeded");
        else
            console2.log("Swap owner tx failed");

        vm.stopBroadcast();
    }

/*
forge script script/PWN.s.sol:Setup \
--sig "setMetadata(address,string)" $LOAN_CONTRACT $METADATA" \
--rpc-url $RPC_URL \
--private-key $PRIVATE_KEY \
--broadcast
*/
    /// @dev Expecting to have daoSafe & config addresses set in the `deployments.json`
    function setMetadata(address address_, string memory metadata) external {
        _loadDeployedAddresses();

        vm.startBroadcast();

        bool success = _gnosisSafeTx({
            safe: daoSafe,
            to: address(config),
            data: abi.encodeWithSignature(
                "setLoanMetadataUri(address,string)", address_, metadata
            )
        });

        if (success)
            console2.log("Set metadata tx succeeded");
        else
            console2.log("Set metadata tx failed");

        vm.stopBroadcast();
    }

}

// Current addrs
// [0x50160ff9c19fbE2B5643449e1A321cAc15af2b2C, 0xAbA34804D2aDE17dd5064Ac7183e7929E4F940BD, 0xAbA34804D2aDE17dd5064Ac7183e7929E4F940BD, 0x6F831783954a9fd8A7243814841F43A2E2C9Ec15, 0x6F831783954a9fd8A7243814841F43A2E2C9Ec15, 0xcf600646707e525C2d031b9d1ab3C28b0fF97096, 0xcf600646707e525C2d031b9d1ab3C28b0fF97096]

// New addre
// [0x57c88D78f6D08b5c88b4A3b7BbB0C1AA34c3280A, 0x5E551f09b8d1353075A1FF3B484Ee688aCAc02F6, 0x5E551f09b8d1353075A1FF3B484Ee688aCAc02F6, 0xDA027058708961Be3676daEB68Fde1758B210065, 0xDA027058708961Be3676daEB68Fde1758B210065, 0x9Cb87eC6448299aBc326F32d60E191Ef32Ab225D, 0x9Cb87eC6448299aBc326F32d60E191Ef32Ab225D]

// Tags
// [0x9e56ea094d7a53440eef11fa42b63159fbf703b4ee579494a6ae85afc5603594, 0xad7661817597136ce476ebc3173f62ce62c618f21c1809bd506e6dee26b217be, 0xe28f844deb305d6f42bccd9495572366ffc5df5d7ae8aca8b455248373c4ecfb, 0xad7661817597136ce476ebc3173f62ce62c618f21c1809bd506e6dee26b217be, 0xe28f844deb305d6f42bccd9495572366ffc5df5d7ae8aca8b455248373c4ecfb, 0xad7661817597136ce476ebc3173f62ce62c618f21c1809bd506e6dee26b217be, 0xcc3e8039ebc82cf2dfc85f5e6f3b220fb59b5b4077418e8b935c7113f42bd229]

// set tags to new addrs
// 0xf12715a1000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000700000000000000000000000057c88d78f6d08b5c88b4a3b7bbb0c1aa34c3280a0000000000000000000000005e551f09b8d1353075a1ff3b484ee688acac02f60000000000000000000000005e551f09b8d1353075a1ff3b484ee688acac02f6000000000000000000000000da027058708961be3676daeb68fde1758b210065000000000000000000000000da027058708961be3676daeb68fde1758b2100650000000000000000000000009cb87ec6448299abc326f32d60e191ef32ab225d0000000000000000000000009cb87ec6448299abc326f32d60e191ef32ab225d00000000000000000000000000000000000000000000000000000000000000079e56ea094d7a53440eef11fa42b63159fbf703b4ee579494a6ae85afc5603594ad7661817597136ce476ebc3173f62ce62c618f21c1809bd506e6dee26b217bee28f844deb305d6f42bccd9495572366ffc5df5d7ae8aca8b455248373c4ecfbad7661817597136ce476ebc3173f62ce62c618f21c1809bd506e6dee26b217bee28f844deb305d6f42bccd9495572366ffc5df5d7ae8aca8b455248373c4ecfbad7661817597136ce476ebc3173f62ce62c618f21c1809bd506e6dee26b217becc3e8039ebc82cf2dfc85f5e6f3b220fb59b5b4077418e8b935c7113f42bd229
