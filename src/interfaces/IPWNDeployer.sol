// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

/**
 * @title IPWNDeployer
 * @notice Interface of the PWN deployer contract.
 */
interface IPWNDeployer {

    /**
     * @notice Function to return the owner of the deployer contract.
     * @return Owner of the deployer contract.
     */
    function owner() external returns (address);

    /**
     * @notice Function to deploy a contract with a given salt and bytecode.
     * @param salt Salt to be used for deployment.
     * @param bytecode Bytecode of the contract to be deployed.
     * @return Address of the deployed contract.
     */
    function deploy(bytes32 salt, bytes memory bytecode) external returns (address);

    /**
     * @notice Function to deploy a contract and transfer ownership with a given salt, owner and bytecode.
     * @param salt Salt to be used for deployment.
     * @param owner Address to which ownership of the deployed contract is transferred.
     * @param bytecode Bytecode of the contract to be deployed.
     * @return Address of the deployed contract.
     */
    function deployAndTransferOwnership(bytes32 salt, address owner, bytes memory bytecode) external returns (address);

    /**
     * @notice Function to compute the address of a contract with a given salt and bytecode hash.
     * @param salt Salt to be used for deployment.
     * @param bytecodeHash Hash of the bytecode of the contract to be deployed.
     * @return Address of the deployed contract.
     */
    function computeAddress(bytes32 salt, bytes32 bytecodeHash) external view returns (address);

}
