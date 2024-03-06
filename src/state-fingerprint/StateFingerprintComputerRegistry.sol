// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Ownable2Step } from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { ERC165Checker } from "openzeppelin-contracts/contracts/utils/introspection/ERC165Checker.sol";

import { IERC5646 } from "@pwn/loan/token/IERC5646.sol";


/**
 * @title State Fingerprint Computer Registry
 * @notice Registry for state fingerprint computers.
 * @dev The computers are used to calculate the state fingerprint of an asset.
 *      It can be a dedicated contract or the asset itself if it implements the IERC5646 interface.
 */
contract StateFingerprintComputerRegistry is Ownable2Step {

    /**
     * @notice Error emitted when registering a computer which does not implement the IERC5646 interface.
     */
    error InvalidComputerContract();

    /**
     * @notice Mapping holding registered computer to an asset.
     * @dev Only owner can update the mapping.
     */
    mapping (address => address) private _computerRegistry;

    /**
     * @notice Returns the ERC5646 computer for a given asset.
     * @param asset The asset for which the computer is requested.
     * @return The computer for the given asset.
     */
    function getStateFingerprintComputer(address asset) external view returns (IERC5646) {
        address computer = _computerRegistry[asset];
        if (computer == address(0))
            if (ERC165Checker.supportsInterface(asset, type(IERC5646).interfaceId))
                computer = asset;

        return IERC5646(computer);
    }

    /**
     * @notice Registers a state fingerprint computer for a given asset.
     * @dev Only owner can register a computer. Computer can be set to address(0) to remove the computer.
     * @param asset The asset for which the computer is registered.
     * @param computer The computer to be registered.
     */
    function registerStateFingerprintComputer(address asset, address computer) external onlyOwner {
        if (computer != address(0))
            if (!ERC165Checker.supportsInterface(computer, type(IERC5646).interfaceId))
                revert InvalidComputerContract();

        _computerRegistry[asset] = computer;
    }

}
