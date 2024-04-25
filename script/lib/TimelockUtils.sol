// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { TimelockController } from "openzeppelin/governance/TimelockController.sol";

import { GnosisSafeLike, GnosisSafeUtils } from "./GnosisSafeUtils.sol";


library TimelockUtils {
    using GnosisSafeUtils for GnosisSafeLike;

    function scheduleAndExecute(TimelockController timelock, address target, bytes memory payload) internal {
        timelock.schedule({ target: target, value: 0, data: payload, predecessor: 0, salt: 0, delay: 0 });
        timelock.execute({ target: target, value: 0, payload: payload, predecessor: 0, salt: 0 });
    }

    function scheduleAndExecute(TimelockController timelock, GnosisSafeLike safe, address target, bytes memory payload) internal {
        bool success = safe.execTransaction({
            to: address(timelock),
            data: abi.encodeWithSelector(TimelockController.schedule.selector, target, 0, payload, 0, 0, 0)
        });
        require(success, "Schedule failed");

        timelock.execute({ target: target, value: 0, payload: payload, predecessor: 0, salt: 0 });
    }

    function scheduleAndExecuteBatch(
        TimelockController timelock,
        address[] memory targets,
        bytes[] memory payloads
    ) internal {
        uint256[] memory values = new uint256[](payloads.length);
        for (uint256 i; i < payloads.length; ++i) {
            values[i] = 0;
        }

        timelock.scheduleBatch({ targets: targets, values: values, payloads: payloads, predecessor: 0, salt: 0, delay: 0 });
        timelock.executeBatch({ targets: targets, values: values, payloads: payloads, predecessor: 0, salt: 0 });
    }

    function scheduleAndExecuteBatch(
        TimelockController timelock,
        GnosisSafeLike safe,
        address[] memory targets,
        bytes[] memory payloads
    ) internal {
        uint256[] memory values = new uint256[](payloads.length);
        for (uint256 i; i < payloads.length; ++i) {
            values[i] = 0;
        }

        bool success = safe.execTransaction({
            to: address(timelock),
            data: abi.encodeWithSelector(TimelockController.scheduleBatch.selector, targets, values, payloads, 0, 0, 0)
        });
        require(success, "Schedule batch failed");

        timelock.executeBatch({ targets: targets, values: values, payloads: payloads, predecessor: 0, salt: 0 });
    }

}
