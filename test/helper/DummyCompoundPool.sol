// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { ICometLike } from "@pwn/loan/vault/ICometLike.sol";


contract DummyCompoundPool is ICometLike {

    function supplyFrom(address from, address, address asset, uint amount) external {
        IERC20(asset).transferFrom(from, address(this), amount);
    }

    function withdrawFrom(address, address to, address asset, uint amount) external {
        IERC20(asset).transfer(to, amount);
    }

}
