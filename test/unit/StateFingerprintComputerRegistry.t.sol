// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import { IERC165 } from "openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";

import { StateFingerprintComputerRegistry, IERC5646 } from "@pwn/state-fingerprint/StateFingerprintComputerRegistry.sol";


abstract contract StateFingerprintComputerRegistryTest is Test {

    bytes32 internal constant OWNER_SLOT = bytes32(uint256(0));
    bytes32 internal constant REGISTRY_SLOT = bytes32(uint256(2));

    address owner = makeAddr("owner");
    StateFingerprintComputerRegistry registry;

    function setUp() external {
        vm.prank(owner);
        registry = new StateFingerprintComputerRegistry();
    }

    function _mockERC5646Support(address asset, bool result) internal {
        _mockERC165Call(asset, type(IERC165).interfaceId, true);
        _mockERC165Call(asset, hex"ffffffff", false);
        _mockERC165Call(asset, type(IERC5646).interfaceId, result);
    }

    function _mockERC165Call(address asset, bytes4 interfaceId, bool result) internal {
        vm.mockCall(
            asset,
            abi.encodeWithSignature("supportsInterface(bytes4)", interfaceId),
            abi.encode(result)
        );
    }

}


/*----------------------------------------------------------*|
|*  # GET STATE FINGERPRINT COMPUTER                        *|
|*----------------------------------------------------------*/

contract StateFingerprintComputerRegistry_GetStateFingerprintComputer_Test is StateFingerprintComputerRegistryTest {

    function testFuzz_shouldReturnStoredComputer_whenIsRegistered(address asset, address computer) external {
        bytes32 assetSlot = keccak256(abi.encode(asset, REGISTRY_SLOT));
        vm.store(address(registry), assetSlot, bytes32(uint256(uint160(computer))));

        assertEq(address(registry.getStateFingerprintComputer(asset)), computer);
    }

    function testFuzz_shouldReturnAsset_whenComputerIsNotRegistered_whenAssetImplementsERC5646(address asset) external {
        assumeAddressIsNot(asset, AddressType.ForgeAddress, AddressType.Precompile);

        _mockERC5646Support(asset, true);

        assertEq(address(registry.getStateFingerprintComputer(asset)), asset);
    }

    function testFuzz_shouldReturnZeroAddress_whenComputerIsNotRegistered_whenAssetNotImplementsERC5646(address asset) external {
        assertEq(address(registry.getStateFingerprintComputer(asset)), address(0));
    }

}


/*----------------------------------------------------------*|
|*  # REGISTER STATE FINGERPRINT COMPUTER                   *|
|*----------------------------------------------------------*/

contract StateFingerprintComputerRegistry_RegisterStateFingerprintComputer_Test is StateFingerprintComputerRegistryTest {

    function testFuzz_shouldFail_whenCallerIsNotOwner(address caller) external {
        vm.assume(caller != owner);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(caller);
        registry.registerStateFingerprintComputer(address(0), address(0));
    }

    function testFuzz_shouldUnregisterComputer_whenComputerIsZeroAddress(address asset) external {
        address computer = makeAddr("computer");
        bytes32 assetSlot = keccak256(abi.encode(asset, REGISTRY_SLOT));
        vm.store(address(registry), assetSlot, bytes32(uint256(uint160(computer))));

        vm.prank(owner);
        registry.registerStateFingerprintComputer(asset, address(0));

        assertEq(address(registry.getStateFingerprintComputer(asset)), address(0));
    }

    function testFuzz_shouldFail_whenComputerDoesNotImplementERC165(address asset, address computer) external {
        assumeAddressIsNot(computer, AddressType.ForgeAddress, AddressType.Precompile, AddressType.ZeroAddress);

        vm.expectRevert(abi.encodeWithSelector(StateFingerprintComputerRegistry.InvalidComputerContract.selector));
        vm.prank(owner);
        registry.registerStateFingerprintComputer(asset, computer);
    }

    function testFuzz_shouldFail_whenComputerDoesNotImplementERC5646(address asset, address computer) external {
        assumeAddressIsNot(computer, AddressType.ForgeAddress, AddressType.Precompile, AddressType.ZeroAddress);
        _mockERC5646Support(computer, false);

        vm.expectRevert(abi.encodeWithSelector(StateFingerprintComputerRegistry.InvalidComputerContract.selector));
        vm.prank(owner);
        registry.registerStateFingerprintComputer(asset, computer);
    }

    function testFuzz_shouldRegisterComputer(address asset, address computer) external {
        assumeAddressIsNot(computer, AddressType.ForgeAddress, AddressType.Precompile, AddressType.ZeroAddress);
        _mockERC5646Support(computer, true);

        vm.prank(owner);
        registry.registerStateFingerprintComputer(asset, computer);

        assertEq(address(registry.getStateFingerprintComputer(asset)), computer);
    }

}
