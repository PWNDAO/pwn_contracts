// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "openzeppelin-contracts/contracts/access/Ownable.sol";


contract PWNConfig is Ownable {

    /// Fee size in basis points
    /// 100 -> 1%
    uint16 public fee;

    constructor(uint16 _fee) Ownable() {
        fee = _fee;
    }


    function setFee(uint16 _fee) external onlyOwner {
        fee = _fee;
    }

}
