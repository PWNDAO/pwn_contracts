// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/utils/Create2.sol";


/// TODO: Doc
contract PWNDeployer is Ownable {

    constructor(address owner) Ownable() {
        _transferOwnership(owner);
    }


    /// TODO: Doc
    function deploy(bytes32 salt, bytes memory bytecode) external onlyOwner returns (address) {
        return Create2.deploy(0, salt, bytecode);
    }

    /// TODO: Doc
    function computeAddress(bytes32 salt, bytes32 bytecodeHash) external view returns (address) {
        return Create2.computeAddress(salt, bytecodeHash);
    }

}
