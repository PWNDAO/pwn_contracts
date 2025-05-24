// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { House } from "pwn/workshop/House.sol";

import { T20 } from "test/helper/T20.sol";
import { T721 } from "test/helper/T721.sol";
import { T1155 } from "test/helper/T1155.sol";
import {
    DeploymentTest,
    PWNConfig,
    IPWNDeployer,
    PWNHub,
    PWNHubTags,
    PWNLoan,
    PWNMortgageProposal,
    PWNLOAN,
    PWNRevokedNonce,
    PWNUtilizedCredit
} from "test/DeploymentTest.t.sol";


contract IntegrationTest is DeploymentTest {

    T20 credit;
    House house;

    function setUp() public override {
        super.setUp();

        credit = new T20();
        house = new House(address(credit), 1 ether);
    }


    function test_mortgage() external {
        // workshop todo:
    }

}
