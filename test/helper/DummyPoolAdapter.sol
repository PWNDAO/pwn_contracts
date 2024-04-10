// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { IPoolAdapter } from "@pwn/pool-adapter/IPoolAdapter.sol";


contract DummyPoolAdapter is IPoolAdapter {

    function withdraw(address pool, address /* owner */, address asset, uint256 amount) external {
        IERC20(asset).transferFrom(pool, msg.sender, amount);
    }

    function supply(address pool, address /* owner */, address asset, uint256 amount) external {
        IERC20(asset).transfer(pool, amount);
    }

}
