// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "@pwn/config/PWNConfig.sol";


abstract contract PWNConfigTest is Test {

    PWNConfig config;

    event FeeUpdated(uint16 oldFee, uint16 newFee);
    event LoanMetadataUriUpdated(address indexed loanContract, string newUri);

    function setUp() virtual public {
        config = new PWNConfig();
    }

}


/*----------------------------------------------------------*|
|*  # INITIALIZE                                            *|
|*----------------------------------------------------------*/

contract PWNConfig_Initialize_Test is PWNConfigTest {

    address owner = address(0x43);
    uint16 fee = 32;


    function test_shouldSetParameters() external {
        config.initialize(owner, fee);

        bytes32 firstSlotValue = vm.load(address(config), bytes32(0));
        assertEq(address(uint160(uint256(firstSlotValue))), owner);
        assertEq(uint16(uint256(firstSlotValue >> 176)), fee);
    }

    function test_shouldFail_whenCalledSecondTime() external {
        config.initialize(owner, fee);

        vm.expectRevert("Initializable: contract is already initialized");
        config.initialize(owner, fee);
    }

}


/*----------------------------------------------------------*|
|*  # SET FEE                                               *|
|*----------------------------------------------------------*/

contract PWNConfig_SetFee_Test is PWNConfigTest {

    address owner = address(0x43);

    function setUp() override public {
        super.setUp();

        config.initialize(owner, 0);
    }


    function test_shouldFail_whenCallerIsNotOwner() external {
        vm.expectRevert("Ownable: caller is not the owner");
        config.setFee(9);
    }

    function test_shouldSetFeeValue() external {
        uint16 fee = 9;

        vm.prank(owner);
        config.setFee(fee);

        bytes32 firstSlotValue = vm.load(address(config), bytes32(0));
        assertEq(uint16(uint256(firstSlotValue >> 176)), fee);
    }

    function test_shouldEmitEvent_FeeUpdated() external {
        vm.expectEmit(true, true, false, false);
        emit FeeUpdated(0, 9);

        vm.prank(owner);
        config.setFee(9);
    }

}


/*----------------------------------------------------------*|
|*  # SET LOAN METADATA URI                                 *|
|*----------------------------------------------------------*/

contract PWNConfig_SetLoanMetadataUri_Test is PWNConfigTest {

    address owner = address(0x43);
    string tokenUri = "test.token.uri";
    address loanContract = address(0x63);

    function setUp() override public {
        super.setUp();

        config.initialize(owner, 0);
    }


    function test_shouldFail_whenCallerIsNotOwner() external {
        vm.expectRevert("Ownable: caller is not the owner");
        config.setLoanMetadataUri(loanContract, tokenUri);
    }

    function test_shouldSetLoanMetadataUriToLoanContract() external {
        vm.prank(owner);
        config.setLoanMetadataUri(loanContract, tokenUri);

        bytes32 tokenUriValue = vm.load(
            address(config),
            keccak256(abi.encode(loanContract, uint256(1)))
        );
        bytes memory memoryTokenUri = bytes(tokenUri);
        bytes32 _tokenUri;
        assembly {
            _tokenUri := mload(add(memoryTokenUri, 0x20))
        }
        // Remove string length
        assertEq(keccak256(abi.encodePacked(tokenUriValue >> 8)), keccak256(abi.encodePacked(_tokenUri >> 8)));
    }

    function test_shouldEmitEvent_LoanMetadataUriUpdated() external {
        vm.expectEmit(true, true, false, false);
        emit LoanMetadataUriUpdated(loanContract, tokenUri);

        vm.prank(owner);
        config.setLoanMetadataUri(loanContract, tokenUri);
    }

}
