// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "openzeppelin-contracts/contracts/utils/Create2.sol";

import "@pwn/deployer/PWNDeployer.sol";
import "@pwn/hub/PWNHub.sol";


abstract contract PWNDeployerTest is Test {

    address owner = address(0x01);
    PWNDeployer deployer;

    function setUp() external {
        deployer = new PWNDeployer(owner);
    }

}


/*----------------------------------------------------------*|
|*  # CONSTRUCTOR                                           *|
|*----------------------------------------------------------*/

contract PWNDeployer_Constructor_Test is PWNDeployerTest {

    function test_shouldSetParameters(address owner_) external {
        deployer = new PWNDeployer(owner_);

        assertEq(deployer.owner(), owner_);
    }

}


/*----------------------------------------------------------*|
|*  # DEPLOY                                                *|
|*----------------------------------------------------------*/

contract PWNDeployer_Deploy_Test is PWNDeployerTest {

    function test_shouldFail_whenCallerIsNotOwner() external {
        vm.expectRevert("Ownable: caller is not the owner");
        deployer.deploy(keccak256("PWNHub"), type(PWNHub).creationCode);
    }

    function test_shouldDeployContract() external {
        vm.prank(owner);
        address newAddr = deployer.deploy({
            salt: keccak256("PWNHub"),
            bytecode: abi.encodePacked(type(PWNHub).creationCode, abi.encode(address(0x10)))
        });

        assertEq(keccak256(newAddr.code), keccak256(type(PWNHub).runtimeCode));
    }

}


/*----------------------------------------------------------*|
|*  # COMPUTE ADDRESS                                       *|
|*----------------------------------------------------------*/

contract PWNDeployer_ComputeAddress_Test is PWNDeployerTest {

    function test_shouldComputeAddress(bytes32 salt, bytes32 bytecodeHash) external {
        assertEq(
            deployer.computeAddress(salt, bytecodeHash),
            Create2.computeAddress(salt, bytecodeHash, address(deployer))
        );
    }

}
