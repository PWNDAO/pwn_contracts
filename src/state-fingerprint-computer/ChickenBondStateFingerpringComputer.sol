// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { IStateFingerpringComputer } from "@pwn/state-fingerprint-computer/IStateFingerpringComputer.sol";


interface IChickenBondManagerLike {
    function getBondData(uint256 _bondID)
        external
        view
        returns (
            uint256 lusdAmount,
            uint64 claimedBLUSD,
            uint64 startTime,
            uint64 endTime,
            uint8 status
        );
}

interface IChickenBondNFTLike {
    function getBondExtraData(uint256 _tokenID)
        external
        view
        returns (
            uint80 initialHalfDna,
            uint80 finalHalfDna,
            uint32 troveSize,
            uint32 lqtyAmount,
            uint32 curveGaugeSlopes
        );
}

/**
 * @notice State fingerprint computer for Chicken Bond positions.
 * @dev Computer will get bond data from `CHICKEN_BOND_MANAGER` and `CHICKEN_BOND`.
 */
contract ChickenBondStateFingerpringComputer is IStateFingerpringComputer {

    address immutable public CHICKEN_BOND_MANAGER;
    address immutable public CHICKEN_BOND;

    error UnsupportedToken();

    constructor(address _chickenBondManager, address _chickenBond) {
        CHICKEN_BOND_MANAGER = _chickenBondManager;
        CHICKEN_BOND = _chickenBond;
    }

    /**
     * @inheritdoc IStateFingerpringComputer
     */
    function computeStateFingerprint(address token, uint256 tokenId) external view returns (bytes32) {
        if (token != CHICKEN_BOND) {
            revert UnsupportedToken();
        }

        return _computeStateFingerprint(tokenId);
    }

    /**
     * @inheritdoc IStateFingerpringComputer
     */
    function supportsToken(address token) external view returns (bool) {
        return token == CHICKEN_BOND;
    }

    /**
     * @notice Compute current token state fingerprint of a Chicken Bond.
     * @param tokenId Token id to compute state fingerprint for.
     * @return Current token state fingerprint.
     */
    function _computeStateFingerprint(uint256 tokenId) private view returns (bytes32) {
        (
            uint256 lusdAmount,
            uint64 claimedBLUSD,
            uint64 startTime,
            uint64 endTime,
            uint8 status
        ) = IChickenBondManagerLike(CHICKEN_BOND_MANAGER).getBondData(tokenId);

        (
            uint80 initialHalfDna,
            uint80 finalHalfDna,
            uint32 troveSize,
            uint32 lqtyAmount,
            uint32 curveGaugeSlopes
        ) = IChickenBondNFTLike(CHICKEN_BOND).getBondExtraData(tokenId);

        return keccak256(abi.encode(
            lusdAmount,
            claimedBLUSD,
            startTime,
            endTime,
            status,
            initialHalfDna,
            finalHalfDna,
            troveSize,
            lqtyAmount,
            curveGaugeSlopes
        ));
    }

}
