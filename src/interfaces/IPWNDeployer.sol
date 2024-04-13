// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;


interface IPWNDeployer {
    function owner() external returns (address);

    function deploy(bytes32 salt, bytes memory bytecode) external returns (address);
    function deployAndTransferOwnership(bytes32 salt, address owner, bytes memory bytecode) external returns (address);
    function computeAddress(bytes32 salt, bytes32 bytecodeHash) external view returns (address);
}
