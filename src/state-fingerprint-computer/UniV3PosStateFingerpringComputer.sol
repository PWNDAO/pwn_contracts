// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { IStateFingerpringComputer } from "src/state-fingerprint-computer/IStateFingerpringComputer.sol";


interface UniswapNonFungiblePositionManagerLike {
    function positions(uint256 tokenId) external view returns (
        uint96 nonce,
        address operator,
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 feeGrowthInside0LastX128,
        uint256 feeGrowthInside1LastX128,
        uint128 tokensOwed0,
        uint128 tokensOwed1
    );
}

/**
 * @notice State fingerprint computer for Uniswap v3 positions.
 */
contract UniV3PosStateFingerpringComputer is IStateFingerpringComputer {

    address immutable public UNI_V3_POS;

    error UnsupportedToken();

    constructor(address _uniV3Pos) {
        UNI_V3_POS = _uniV3Pos;
    }

    /**
     * @inheritdoc IStateFingerpringComputer
     */
    function computeStateFingerprint(address token, uint256 tokenId) external view returns (bytes32) {
        if (token != UNI_V3_POS) {
            revert UnsupportedToken();
        }

        return _computeStateFingerprint(tokenId);
    }

    /**
     * @inheritdoc IStateFingerpringComputer
     */
    function supportsToken(address token) external view returns (bool) {
        return token == UNI_V3_POS;
    }

    /**
     * @notice Compute current token state fingerprint of a Uniswap v3 position.
     * @param tokenId Token id to compute state fingerprint for.
     * @return Current token state fingerprint.
     */
    function _computeStateFingerprint(uint256 tokenId) private view returns (bytes32) {
        (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = UniswapNonFungiblePositionManagerLike(UNI_V3_POS).positions(tokenId);

        return keccak256(abi.encode(
            nonce,
            operator,
            token0,
            token1,
            fee,
            tickLower,
            tickUpper,
            liquidity,
            feeGrowthInside0LastX128,
            feeGrowthInside1LastX128,
            tokensOwed0,
            tokensOwed1
        ));
    }

}
