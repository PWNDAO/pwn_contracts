// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

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

    T20 t20;
    T721 t721;
    T1155 t1155;
    T20 credit;


    function setUp() public override {
        super.setUp();

        // Deploy tokens
        t20 = new T20();
        t721 = new T721();
        t1155 = new T1155();
        credit = new T20();
    }


    function test_mortgage() external {
        // workshop todo:
    }

}