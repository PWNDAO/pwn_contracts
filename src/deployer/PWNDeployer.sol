// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/utils/Create2.sol";


/**
 * @title PWN Deployer
 * @notice Contract that deploy other PWN protocol contracst with `CREATE2` opcode, to have the same address on a different chains.
 */
contract PWNDeployer is Ownable {

    constructor(address owner) Ownable() {
        _transferOwnership(owner);
    }


    /**
     * @notice Deploy new contract with salt.
     * @dev Set of salts is defined in {PWNContractDeployerSalt.sol}.
     *      Only deployer owner can call this function.
     * @param salt Salt used in `CREATE2` call.
     * @param bytecode Contracts create code encoded with constructor params.
     * @return Newly deployed contract address.
     */
    function deploy(bytes32 salt, bytes memory bytecode) external onlyOwner returns (address) {
        return Create2.deploy(0, salt, bytecode);
    }

    /**
     * @notice Compute address of a contract that would be deployed with given salt.
     * @param salt Salt used in `CREATE2` call.
     * @param bytecodeHash Hash of a contracts create code encoded with constructor params.
     * @return Computed contract address.
     */
    function computeAddress(bytes32 salt, bytes32 bytecodeHash) external view returns (address) {
        return Create2.computeAddress(salt, bytecodeHash);
    }

}
