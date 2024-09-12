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
    PWNSimpleLoanElasticProposal,
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
    bytes32 internal constant SIMPLE_LOAN_ELASTIC_PROPOSAL = keccak256("PWNSimpleLoanElasticProposal");
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

        deployment.simpleLoanElasticProposal = PWNSimpleLoanElasticProposal(_deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN_ELASTIC_PROPOSAL,
            bytecode: abi.encodePacked(
                type(PWNSimpleLoanElasticProposal).creationCode,
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
        console2.log("PWNSimpleLoanElasticProposal:", address(deployment.simpleLoanElasticProposal));
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

        // - Hub
        deployment.hub = PWNHub(_deployAndTransferOwnership({ // Need ownership acceptance from the new owner
            salt: PWNContractDeployerSalt.HUB,
            owner: deployment.protocolTimelock,
            bytecode: hex"608060405234801561001057600080fd5b5061001a3361001f565b610096565b600180546001600160a01b031916905561004381610046602090811b61035617901c565b50565b600080546001600160a01b038381166001600160a01b0319831681178455604051919092169283917f8be0079c531659141344cd1fd0a4f28419497f9722a3daafe3b4186f6b6457e09190a35050565b6106b6806100a56000396000f3fe608060405234801561001057600080fd5b50600436106100885760003560e01c8063d019577a1161005b578063d019577a146100dc578063e30c397814610125578063f12715a114610136578063f2fde38b1461014957600080fd5b8063715018a61461008d57806379ba5097146100975780638da5cb5b1461009f5780639cd9c520146100c9575b600080fd5b61009561015c565b005b610095610170565b6000546001600160a01b03165b6040516001600160a01b0390911681526020015b60405180910390f35b6100956100d7366004610445565b6101ef565b6101156100ea366004610481565b6001600160a01b03919091166000908152600260209081526040808320938352929052205460ff1690565b60405190151581526020016100c0565b6001546001600160a01b03166100ac565b610095610144366004610581565b610262565b610095610157366004610648565b6102e5565b6101646103a6565b61016e6000610400565b565b60015433906001600160a01b031681146101e35760405162461bcd60e51b815260206004820152602960248201527f4f776e61626c6532537465703a2063616c6c6572206973206e6f7420746865206044820152683732bb9037bbb732b960b91b60648201526084015b60405180910390fd5b6101ec81610400565b50565b6101f76103a6565b6001600160a01b0383166000818152600260209081526040808320868452825291829020805460ff191685151590811790915591519182528492917fb30f662698af140e14b21a677b92bf5a9787f9109294b3d206fa53ea23069d2b910160405180910390a3505050565b61026a6103a6565b815183511461028c57604051637016bd9b60e01b815260040160405180910390fd5b815160005b818110156102de576102d68582815181106102ae576102ae61066a565b60200260200101518583815181106102c8576102c861066a565b6020026020010151856101ef565b600101610291565b5050505050565b6102ed6103a6565b600180546001600160a01b0383166001600160a01b0319909116811790915561031e6000546001600160a01b031690565b6001600160a01b03167f38d16b8cac22d99fc7c124b9cd0de2d3fa1faef420bfe791d8c362d765e2270060405160405180910390a350565b600080546001600160a01b038381166001600160a01b0319831681178455604051919092169283917f8be0079c531659141344cd1fd0a4f28419497f9722a3daafe3b4186f6b6457e09190a35050565b6000546001600160a01b0316331461016e5760405162461bcd60e51b815260206004820181905260248201527f4f776e61626c653a2063616c6c6572206973206e6f7420746865206f776e657260448201526064016101da565b600180546001600160a01b03191690556101ec81610356565b80356001600160a01b038116811461043057600080fd5b919050565b8035801515811461043057600080fd5b60008060006060848603121561045a57600080fd5b61046384610419565b92506020840135915061047860408501610435565b90509250925092565b6000806040838503121561049457600080fd5b61049d83610419565b946020939093013593505050565b634e487b7160e01b600052604160045260246000fd5b604051601f8201601f1916810167ffffffffffffffff811182821017156104ea576104ea6104ab565b604052919050565b600067ffffffffffffffff82111561050c5761050c6104ab565b5060051b60200190565b600082601f83011261052757600080fd5b8135602061053c610537836104f2565b6104c1565b82815260059290921b8401810191818101908684111561055b57600080fd5b8286015b84811015610576578035835291830191830161055f565b509695505050505050565b60008060006060848603121561059657600080fd5b833567ffffffffffffffff808211156105ae57600080fd5b818601915086601f8301126105c257600080fd5b813560206105d2610537836104f2565b82815260059290921b8401810191818101908a8411156105f157600080fd5b948201945b838610156106165761060786610419565b825294820194908201906105f6565b9750508701359250508082111561062c57600080fd5b5061063986828701610516565b92505061047860408501610435565b60006020828403121561065a57600080fd5b61066382610419565b9392505050565b634e487b7160e01b600052603260045260246000fdfea2646970667358221220d1e6160af9be44b466470083a1ab56623b8e95e11070e3d1398cf335af77500c64736f6c63430008100033"
        }));

        // - LOAN token
        deployment.loanToken = PWNLOAN(_deploy({
            salt: PWNContractDeployerSalt.LOAN,
            bytecode: hex"60a06040523480156200001157600080fd5b506040516200191f3803806200191f8339810160408190526200003491620000a3565b6040805180820182526008815267282ba7102627a0a760c11b602080830191909152825180840190935260048352632627a0a760e11b908301526001600160a01b0383166080529060006200008a83826200017a565b5060016200009982826200017a565b5050505062000246565b600060208284031215620000b657600080fd5b81516001600160a01b0381168114620000ce57600080fd5b9392505050565b634e487b7160e01b600052604160045260246000fd5b600181811c908216806200010057607f821691505b6020821081036200012157634e487b7160e01b600052602260045260246000fd5b50919050565b601f8211156200017557600081815260208120601f850160051c81016020861015620001505750805b601f850160051c820191505b8181101562000171578281556001016200015c565b5050505b505050565b81516001600160401b03811115620001965762000196620000d5565b620001ae81620001a78454620000eb565b8462000127565b602080601f831160018114620001e65760008415620001cd5750858301515b600019600386901b1c1916600185901b17855562000171565b600085815260208120601f198616915b828110156200021757888601518255948401946001909101908401620001f6565b5085821015620002365787850151600019600388901b60f8161c191681555b5050505050600190811b01905550565b6080516116bd62000262600039600061062401526116bd6000f3fe608060405234801561001057600080fd5b50600436106101165760003560e01c80636a627842116100a2578063a22cb46511610071578063a22cb46514610252578063b88d4fde14610265578063c87b56dd14610278578063e985e9c51461028b578063f51123151461029e57600080fd5b80636a627842146101fb57806370a082311461020e57806395d89b4114610221578063a00d21fc1461022957600080fd5b806323b872dd116100e957806323b872dd1461019857806342842e0e146101ab57806342966c68146101be5780636352211e146101d157806368be92b4146101e457600080fd5b806301ffc9a71461011b57806306fdde0314610143578063081812fc14610158578063095ea7b314610183575b600080fd5b61012e610129366004611145565b6102b1565b60405190151581526020015b60405180910390f35b61014b6102dd565b60405161013a91906111b2565b61016b6101663660046111c5565b61036f565b6040516001600160a01b03909116815260200161013a565b6101966101913660046111fa565b610396565b005b6101966101a6366004611224565b6104b0565b6101966101b9366004611224565b6104e1565b6101966101cc3660046111c5565b6104fc565b61016b6101df3660046111c5565b610586565b6101ed60065481565b60405190815260200161013a565b6101ed610209366004611260565b6105e6565b6101ed61021c366004611260565b610756565b61014b6107dc565b61016b6102373660046111c5565b6007602052600090815260409020546001600160a01b031681565b610196610260366004611289565b6107eb565b61019661027336600461132f565b6107fa565b61014b6102863660046111c5565b610832565b61012e6102993660046113da565b6108b5565b6101ed6102ac3660046111c5565b6108e3565b60006102bc82610979565b806102d757506001600160e01b0319821663f511231560e01b145b92915050565b6060600080546102ec9061140d565b80601f01602080910402602001604051908101604052809291908181526020018280546103189061140d565b80156103655780601f1061033a57610100808354040283529160200191610365565b820191906000526020600020905b81548152906001019060200180831161034857829003601f168201915b5050505050905090565b600061037a826109c9565b506000908152600460205260409020546001600160a01b031690565b60006103a182610586565b9050806001600160a01b0316836001600160a01b0316036104135760405162461bcd60e51b815260206004820152602160248201527f4552433732313a20617070726f76616c20746f2063757272656e74206f776e656044820152603960f91b60648201526084015b60405180910390fd5b336001600160a01b038216148061042f575061042f81336108b5565b6104a15760405162461bcd60e51b815260206004820152603d60248201527f4552433732313a20617070726f76652063616c6c6572206973206e6f7420746f60448201527f6b656e206f776e6572206f7220617070726f76656420666f7220616c6c000000606482015260840161040a565b6104ab8383610a2b565b505050565b6104ba3382610a99565b6104d65760405162461bcd60e51b815260040161040a90611447565b6104ab838383610af8565b6104ab838383604051806020016040528060008152506107fa565b6000818152600760205260409020546001600160a01b03163314610533576040516374768c4960e11b815260040160405180910390fd5b600081815260076020526040902080546001600160a01b031916905561055881610c69565b60405181907f56f7da88d3aa2a8ad74b71a5b449a66a643193815eace8bbd6b089d4bc18294b90600090a250565b6000818152600260205260408120546001600160a01b0316806102d75760405162461bcd60e51b8152602060048201526018602482015277115490cdcc8c4e881a5b9d985b1a59081d1bdad95b88125160421b604482015260640161040a565b60405163680cabbd60e11b81523360048201527f9e56ea094d7a53440eef11fa42b63159fbf703b4ee579494a6ae85afc560359460248201526000907f00000000000000000000000000000000000000000000000000000000000000006001600160a01b03169063d019577a90604401602060405180830381865afa158015610673573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906106979190611494565b15156000036106db5760405163f8932b2d60e01b81527f9e56ea094d7a53440eef11fa42b63159fbf703b4ee579494a6ae85afc5603594600482015260240161040a565b6006600081546106ea906114c7565b9182905550600081815260076020526040902080546001600160a01b0319163317905590506107198282610d0c565b6040516001600160a01b03831690339083907f2ca529bede83c064afd9331357a1ce320271c9c7ceda28ac31472d76f7aff53090600090a4919050565b60006001600160a01b0382166107c05760405162461bcd60e51b815260206004820152602960248201527f4552433732313a2061646472657373207a65726f206973206e6f7420612076616044820152683634b21037bbb732b960b91b606482015260840161040a565b506001600160a01b031660009081526003602052604090205490565b6060600180546102ec9061140d565b6107f6338383610ea5565b5050565b6108043383610a99565b6108205760405162461bcd60e51b815260040161040a90611447565b61082c84848484610f73565b50505050565b606061083d826109c9565b60008281526007602052604080822054815163111d8a1560e01b815291516001600160a01b039091169263111d8a1592600480820193918290030181865afa15801561088d573d6000803e3d6000fd5b505050506040513d6000823e601f3d908101601f191682016040526102d791908101906114e0565b6001600160a01b03918216600090815260056020908152604080832093909416825291909152205460ff1690565b6000818152600760205260408120546001600160a01b0316806109095750600092915050565b60405163f511231560e01b8152600481018490526001600160a01b0382169063f511231590602401602060405180830381865afa15801561094e573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906109729190611557565b9392505050565b60006001600160e01b031982166380ac58cd60e01b14806109aa57506001600160e01b03198216635b5e139f60e01b145b806102d757506301ffc9a760e01b6001600160e01b03198316146102d7565b6000818152600260205260409020546001600160a01b0316610a285760405162461bcd60e51b8152602060048201526018602482015277115490cdcc8c4e881a5b9d985b1a59081d1bdad95b88125160421b604482015260640161040a565b50565b600081815260046020526040902080546001600160a01b0319166001600160a01b0384169081179091558190610a6082610586565b6001600160a01b03167f8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b92560405160405180910390a45050565b600080610aa583610586565b9050806001600160a01b0316846001600160a01b03161480610acc5750610acc81856108b5565b80610af05750836001600160a01b0316610ae58461036f565b6001600160a01b0316145b949350505050565b826001600160a01b0316610b0b82610586565b6001600160a01b031614610b315760405162461bcd60e51b815260040161040a90611570565b6001600160a01b038216610b935760405162461bcd60e51b8152602060048201526024808201527f4552433732313a207472616e7366657220746f20746865207a65726f206164646044820152637265737360e01b606482015260840161040a565b610ba08383836001610fa6565b826001600160a01b0316610bb382610586565b6001600160a01b031614610bd95760405162461bcd60e51b815260040161040a90611570565b600081815260046020908152604080832080546001600160a01b03199081169091556001600160a01b0387811680865260038552838620805460001901905590871680865283862080546001019055868652600290945282852080549092168417909155905184937fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef91a4505050565b6000610c7482610586565b9050610c84816000846001610fa6565b610c8d82610586565b600083815260046020908152604080832080546001600160a01b03199081169091556001600160a01b0385168085526003845282852080546000190190558785526002909352818420805490911690555192935084927fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef908390a45050565b6001600160a01b038216610d625760405162461bcd60e51b815260206004820181905260248201527f4552433732313a206d696e7420746f20746865207a65726f2061646472657373604482015260640161040a565b6000818152600260205260409020546001600160a01b031615610dc75760405162461bcd60e51b815260206004820152601c60248201527f4552433732313a20746f6b656e20616c7265616479206d696e74656400000000604482015260640161040a565b610dd5600083836001610fa6565b6000818152600260205260409020546001600160a01b031615610e3a5760405162461bcd60e51b815260206004820152601c60248201527f4552433732313a20746f6b656e20616c7265616479206d696e74656400000000604482015260640161040a565b6001600160a01b038216600081815260036020908152604080832080546001019055848352600290915280822080546001600160a01b0319168417905551839291907fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef908290a45050565b816001600160a01b0316836001600160a01b031603610f065760405162461bcd60e51b815260206004820152601960248201527f4552433732313a20617070726f766520746f2063616c6c657200000000000000604482015260640161040a565b6001600160a01b03838116600081815260056020908152604080832094871680845294825291829020805460ff191686151590811790915591519182527f17307eab39ab6107e8899845ad3d59bd9653f200f220920489ca2b5937696c31910160405180910390a3505050565b610f7e848484610af8565b610f8a8484848461102e565b61082c5760405162461bcd60e51b815260040161040a906115b5565b600181111561082c576001600160a01b03841615610fec576001600160a01b03841660009081526003602052604081208054839290610fe6908490611607565b90915550505b6001600160a01b0383161561082c576001600160a01b0383166000908152600360205260408120805483929061102390849061161a565b909155505050505050565b60006001600160a01b0384163b1561112457604051630a85bd0160e11b81526001600160a01b0385169063150b7a029061107290339089908890889060040161162d565b6020604051808303816000875af19250505080156110ad575060408051601f3d908101601f191682019092526110aa9181019061166a565b60015b61110a573d8080156110db576040519150601f19603f3d011682016040523d82523d6000602084013e6110e0565b606091505b5080516000036111025760405162461bcd60e51b815260040161040a906115b5565b805181602001fd5b6001600160e01b031916630a85bd0160e11b149050610af0565b506001949350505050565b6001600160e01b031981168114610a2857600080fd5b60006020828403121561115757600080fd5b81356109728161112f565b60005b8381101561117d578181015183820152602001611165565b50506000910152565b6000815180845261119e816020860160208601611162565b601f01601f19169290920160200192915050565b6020815260006109726020830184611186565b6000602082840312156111d757600080fd5b5035919050565b80356001600160a01b03811681146111f557600080fd5b919050565b6000806040838503121561120d57600080fd5b611216836111de565b946020939093013593505050565b60008060006060848603121561123957600080fd5b611242846111de565b9250611250602085016111de565b9150604084013590509250925092565b60006020828403121561127257600080fd5b610972826111de565b8015158114610a2857600080fd5b6000806040838503121561129c57600080fd5b6112a5836111de565b915060208301356112b58161127b565b809150509250929050565b634e487b7160e01b600052604160045260246000fd5b604051601f8201601f1916810167ffffffffffffffff811182821017156112ff576112ff6112c0565b604052919050565b600067ffffffffffffffff821115611321576113216112c0565b50601f01601f191660200190565b6000806000806080858703121561134557600080fd5b61134e856111de565b935061135c602086016111de565b925060408501359150606085013567ffffffffffffffff81111561137f57600080fd5b8501601f8101871361139057600080fd5b80356113a361139e82611307565b6112d6565b8181528860208385010111156113b857600080fd5b8160208401602083013760006020838301015280935050505092959194509250565b600080604083850312156113ed57600080fd5b6113f6836111de565b9150611404602084016111de565b90509250929050565b600181811c9082168061142157607f821691505b60208210810361144157634e487b7160e01b600052602260045260246000fd5b50919050565b6020808252602d908201527f4552433732313a2063616c6c6572206973206e6f7420746f6b656e206f776e6560408201526c1c881bdc88185c1c1c9bdd9959609a1b606082015260800190565b6000602082840312156114a657600080fd5b81516109728161127b565b634e487b7160e01b600052601160045260246000fd5b6000600182016114d9576114d96114b1565b5060010190565b6000602082840312156114f257600080fd5b815167ffffffffffffffff81111561150957600080fd5b8201601f8101841361151a57600080fd5b805161152861139e82611307565b81815285602083850101111561153d57600080fd5b61154e826020830160208601611162565b95945050505050565b60006020828403121561156957600080fd5b5051919050565b60208082526025908201527f4552433732313a207472616e736665722066726f6d20696e636f72726563742060408201526437bbb732b960d91b606082015260800190565b60208082526032908201527f4552433732313a207472616e7366657220746f206e6f6e20455243373231526560408201527131b2b4bb32b91034b6b83632b6b2b73a32b960711b606082015260800190565b818103818111156102d7576102d76114b1565b808201808211156102d7576102d76114b1565b6001600160a01b038581168252841660208201526040810183905260806060820181905260009061166090830184611186565b9695505050505050565b60006020828403121561167c57600080fd5b81516109728161112f56fea264697066735822122039ae91bd608a4faaff76f2a30605fb5f1b0a5634bce2e6aed4735db710f3dd7764736f6c6343000810003300000000000000000000000037807a2f031b3b44081f4b21500e5d70ebadadd5"
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

        deployment.simpleLoanElasticProposal = PWNSimpleLoanElasticProposal(_deploy({
            salt: PWNContractDeployerSalt.SIMPLE_LOAN_ELASTIC_PROPOSAL,
            bytecode: abi.encodePacked(
                type(PWNSimpleLoanElasticProposal).creationCode,
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
        console2.log("PWNSimpleLoanElasticProposal:", address(deployment.simpleLoanElasticProposal));
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
        require(address(deployment.simpleLoanElasticProposal) != address(0), "Simple loan elastic proposal not set");
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

        addrs[6] = address(deployment.simpleLoanElasticProposal);
        addrs[7] = address(deployment.simpleLoanElasticProposal);

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
    /// @dev Expecting to have daoSafe, protocol timelock & config addresses set in the `deployments/latest.json`
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

        require(address(deployment.daoSafe) != address(0), "DAO safe not set");
        require(address(deployment.protocolTimelock) != address(0), "Protocol timelock not set");
        require(address(deployment.categoryRegistry) != address(0), "Category Registry not set");

        vm.startBroadcast();

        TimelockController(payable(deployment.protocolTimelock)).scheduleAndExecute(
            GnosisSafeLike(deployment.daoSafe),
            address(deployment.categoryRegistry),
            abi.encodeWithSignature("registerCategoryValue(address,uint8)", assetAddress, category)
        );
        console2.log("Category registered:", assetAddress, category);

        vm.stopBroadcast();
    }

}
