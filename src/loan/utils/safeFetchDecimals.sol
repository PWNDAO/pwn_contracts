// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Address } from "openzeppelin/utils/Address.sol";


function safeFetchDecimals(address asset) view returns (uint256) {
    bytes memory rawDecimals = Address.functionStaticCall(asset, abi.encodeWithSignature("decimals()"));
    if (rawDecimals.length == 0) {
        return 0;
    }
    return abi.decode(rawDecimals, (uint256));
}
