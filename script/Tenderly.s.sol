// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Script, console2 } from "forge-std/Script.sol";

import { Deployments } from "pwn/Deployments.sol";


/*
forge script script/Tenderly.s.sol --ffi
*/
contract Tenderly is Deployments, Script {

    function run() external {
        vm.createSelectFork("tenderly");
        _loadDeployedAddresses();

        console2.log("Fund deployment addresses");
        /// To fund an address use: cast rpc -r $TENDERLY_URL tenderly_addBalance {address} {hex_amount}
        {
            string[] memory args = new string[](7);
            args[0] = "cast";
            args[1] = "rpc";
            args[2] = "--rpc-url";
            args[3] = vm.envString("TENDERLY_URL");
            args[4] = "tenderly_addBalance";
            args[5] = "0x27e3E42E96cE78C34572b70381A400DA5B6E984C";
            args[6] = "0x1000000000000000000000000";
            vm.ffi(args);
        }

        /// To set safes threshold to 1 use: cast rpc -r $TENDERLY_URL tenderly_setStorageAt {safe_address} 0x0000000000000000000000000000000000000000000000000000000000000004 0x0000000000000000000000000000000000000000000000000000000000000001
        /// To set hubs owner to protocol safe use: cast rpc -r $TENDERLY_URL tenderly_setStorageAt {hub_address} 0x0000000000000000000000000000000000000000000000000000000000000000 {protocol_safe_addr_to_32}
    }

}
