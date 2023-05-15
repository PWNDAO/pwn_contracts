// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "@pwn/config/PWNConfig.sol";


abstract contract PWNConfigTest is Test {

    bytes32 internal constant OWNER_SLOT = bytes32(uint256(0)); // `_owner` property position
    bytes32 internal constant PENDING_OWNER_SLOT = bytes32(uint256(1)); // `_pendingOwner` property position
    bytes32 internal constant FEE_SLOT = bytes32(uint256(1)); // `fee` property position
    bytes32 internal constant FEE_COLLECTOR_SLOT = bytes32(uint256(2)); // `feeCollector` property position
    bytes32 internal constant LOAN_METADATA_URI_SLOT = bytes32(uint256(3)); // `loanMetadataUri` mapping position

    PWNConfig config;
    address owner = address(0x43);
    address feeCollector = address(0xfeeC001ec704);

    event FeeUpdated(uint16 oldFee, uint16 newFee);
    event FeeCollectorUpdated(address oldFeeCollector, address newFeeCollector);
    event LoanMetadataUriUpdated(address indexed loanContract, string newUri);

    function setUp() virtual public {
        config = new PWNConfig();
    }

}


/*----------------------------------------------------------*|
|*  # INITIALIZE                                            *|
|*----------------------------------------------------------*/

contract PWNConfig_Initialize_Test is PWNConfigTest {

    uint16 fee = 32;

    function test_shouldSetOwner() external {
        config.initialize(owner, fee, feeCollector);

        bytes32 ownerValue = vm.load(address(config), OWNER_SLOT);
        assertEq(address(uint160(uint256(ownerValue))), owner);

        bytes32 feeSlotValue = vm.load(address(config), FEE_SLOT);
        assertEq(uint16(uint256(feeSlotValue >> 176)), fee);

        bytes32 feeCollectorValue = vm.load(address(config), FEE_COLLECTOR_SLOT);
        assertEq(address(uint160(uint256(feeCollectorValue))), feeCollector);
    }

    function test_shouldFail_whenCalledSecondTime() external {
        config.initialize(owner, fee, feeCollector);

        vm.expectRevert("Initializable: contract is already initialized");
        config.initialize(owner, fee, feeCollector);
    }

    function test_shouldFail_whenOwnerIsZeroAddress() external {
        vm.expectRevert("Owner is zero address");
        config.initialize(address(0), fee, feeCollector);
    }

    function test_shouldFail_whenFeeCollectorIsZeroAddress() external {
        vm.expectRevert("Fee collector is zero address");
        config.initialize(owner, fee, address(0));
    }

}


/*----------------------------------------------------------*|
|*  # SET FEE                                               *|
|*----------------------------------------------------------*/

contract PWNConfig_SetFee_Test is PWNConfigTest {

    function setUp() override public {
        super.setUp();

        config.initialize(owner, 0, feeCollector);
    }


    function test_shouldFail_whenCallerIsNotOwner() external {
        vm.expectRevert("Ownable: caller is not the owner");
        config.setFee(9);
    }

    function test_shouldFaile_whenNewValueBiggerThanMaxFee() external {
        uint16 maxFee = config.MAX_FEE();

        vm.expectRevert(abi.encodeWithSelector(InvalidFeeValue.selector));
        vm.prank(owner);
        config.setFee(maxFee + 1);
    }

    function test_shouldSetFeeValue() external {
        uint16 fee = 9;

        vm.prank(owner);
        config.setFee(fee);

        bytes32 feeSlotValue = vm.load(address(config), FEE_SLOT);
        assertEq(uint16(uint256(feeSlotValue >> 176)), fee);
    }

    function test_shouldEmitEvent_FeeUpdated() external {
        vm.expectEmit(true, true, false, false);
        emit FeeUpdated(0, 9);

        vm.prank(owner);
        config.setFee(9);
    }

}


/*----------------------------------------------------------*|
|*  # SET FEE COLLECTOR                                     *|
|*----------------------------------------------------------*/

contract PWNConfig_SetFeeCollector_Test is PWNConfigTest {

    address newFeeCollector = address(0xfee);


    function setUp() override public {
        super.setUp();

        config.initialize(owner, 0, feeCollector);
    }


    function test_shouldFail_whenCallerIsNotOwner() external {
        vm.expectRevert("Ownable: caller is not the owner");
        config.setFeeCollector(newFeeCollector);
    }

    function test_shouldFail_whenSettingZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(InvalidFeeCollector.selector));
        vm.prank(owner);
        config.setFeeCollector(address(0));
    }

    function test_shouldSetFeeCollectorAddress() external {
        vm.prank(owner);
        config.setFeeCollector(newFeeCollector);

        bytes32 feeCollectorValue = vm.load(address(config), FEE_COLLECTOR_SLOT);
        assertEq(uint160(uint256(feeCollectorValue)), uint160(newFeeCollector));
    }

    function test_shouldEmitEvent_FeeCollectorUpdated() external {
        vm.expectEmit(true, true, false, false);
        emit FeeCollectorUpdated(feeCollector, newFeeCollector);

        vm.prank(owner);
        config.setFeeCollector(newFeeCollector);
    }

}


/*----------------------------------------------------------*|
|*  # SET LOAN METADATA URI                                 *|
|*----------------------------------------------------------*/

contract PWNConfig_SetLoanMetadataUri_Test is PWNConfigTest {

    string tokenUri = "test.token.uri";
    address loanContract = address(0x63);

    function setUp() override public {
        super.setUp();

        config.initialize(owner, 0, feeCollector);
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
            keccak256(abi.encode(loanContract, LOAN_METADATA_URI_SLOT))
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
