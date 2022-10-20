// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "@pwn/hub/PWNHubTags.sol";
import "@pwn/loan/PWNLOAN.sol";
import "@pwn/PWNError.sol";


abstract contract PWNLOANTest is Test {

    bytes32 internal constant LAST_LOAN_ID_SLOT = bytes32(uint256(6)); // `lastLoanId` property position
    bytes32 internal constant LOAN_CONTRACT_SLOT = bytes32(uint256(7)); // `loanContract` mapping position

    PWNLOAN loanToken;
    address hub = address(0x80b);
    address alice = address(0xa11ce);
    address activeLoanContract = address(0x01);

    event LOANMinted(uint256 indexed loanId, address indexed owner);
    event LOANBurned(uint256 indexed loanId);

    constructor() {
        vm.etch(hub, bytes("data"));
    }

    function setUp() virtual public {
        loanToken = new PWNLOAN(hub);

        vm.mockCall(
            hub,
            abi.encodeWithSignature("hasTag(address,bytes32)"),
            abi.encode(false)
        );
        vm.mockCall(
            hub,
            abi.encodeWithSignature("hasTag(address,bytes32)", activeLoanContract, PWNHubTags.ACTIVE_LOAN),
            abi.encode(true)
        );
    }


    function _loanContractSlot(uint256 loanId) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            loanId,
            LOAN_CONTRACT_SLOT
        ));
    }

}


/*----------------------------------------------------------*|
|*  # CONSTRUCTOR                                           *|
|*----------------------------------------------------------*/

contract PWNLOAN_Constructor_Test is PWNLOANTest {

    function test_shouldHaveCorrectNameAndSymbol() external {
        assertTrue(keccak256(abi.encodePacked(loanToken.name())) == keccak256("PWN LOAN"));
        assertTrue(keccak256(abi.encodePacked(loanToken.symbol())) == keccak256("LOAN"));
    }

}


/*----------------------------------------------------------*|
|*  # MINT                                                  *|
|*----------------------------------------------------------*/

contract PWNLOAN_Mint_Test is PWNLOANTest {

    function test_shouldFail_whenCallerIsNotActiveLoanContract() external {
        vm.expectRevert(
            abi.encodeWithSelector(PWNError.CallerMissingHubTag.selector, PWNHubTags.ACTIVE_LOAN)
        );
        vm.prank(alice);
        loanToken.mint(alice);
    }

    function test_shouldIncreaseLastLoanId() external {
        uint256 lastLoanId = 3123;
        vm.store(address(loanToken), LAST_LOAN_ID_SLOT, bytes32(lastLoanId));

        vm.prank(activeLoanContract);
        loanToken.mint(alice);

        bytes32 lastLoanIdValue = vm.load(address(loanToken), LAST_LOAN_ID_SLOT);
        assertTrue(uint256(lastLoanIdValue) == lastLoanId + 1);
    }

    function test_shouldStoreLoanContractUnderLoanId() external {
        vm.prank(activeLoanContract);
        uint256 loanId = loanToken.mint(alice);

        bytes32 loanContractValue = vm.load(address(loanToken), _loanContractSlot(loanId));
        assertTrue(loanContractValue == bytes32(uint256(uint160(activeLoanContract))));
    }

    function test_shouldMintLOANToken() external {
        vm.prank(activeLoanContract);
        uint256 loanId = loanToken.mint(alice);

        assertTrue(loanToken.ownerOf(loanId) == alice);
    }

    function test_shouldReturnLoanId() external {
        uint256 lastLoanId = 3123;
        vm.store(address(loanToken), LAST_LOAN_ID_SLOT, bytes32(lastLoanId));

        vm.prank(activeLoanContract);
        uint256 loanId = loanToken.mint(alice);

        assertTrue(loanId == lastLoanId + 1);
    }

    function test_shouldEmitEvent_LOANMinted() external {
        uint256 lastLoanId = 3123;
        vm.store(address(loanToken), LAST_LOAN_ID_SLOT, bytes32(lastLoanId));

        vm.expectEmit(true, true, false, false);
        emit LOANMinted(lastLoanId + 1, alice);

        vm.prank(activeLoanContract);
        loanToken.mint(alice);
    }

}


/*----------------------------------------------------------*|
|*  # BURN                                                  *|
|*----------------------------------------------------------*/

contract PWNLOAN_Burn_Test is PWNLOANTest {

    uint256 loanId;

    function setUp() override public {
        super.setUp();

        vm.prank(activeLoanContract);
        loanId = loanToken.mint(alice);
    }


    function test_shouldFail_whenCallerIsNotStoredLoanContractForGivenLoanId() external {
        vm.expectRevert(
            abi.encodeWithSelector(PWNError.InvalidLoanContractCaller.selector)
        );
        vm.prank(alice);
        loanToken.burn(loanId);
    }

    function test_shouldDeleteStoredLoanContract() external {
        vm.prank(activeLoanContract);
        loanToken.burn(loanId);

        bytes32 loanContractValue = vm.load(address(loanToken), _loanContractSlot(loanId));
        assertTrue(loanContractValue == bytes32(0));
    }

    function test_shouldBurnLOANToken() external {
        vm.prank(activeLoanContract);
        loanToken.burn(loanId);

        vm.expectRevert("ERC721: invalid token ID");
        loanToken.ownerOf(loanId);
    }

    function test_shouldEmitEvent_LOANBurned() external {
        vm.expectEmit(true, false, false, false);
        emit LOANBurned(loanId);

        vm.prank(activeLoanContract);
        loanToken.burn(loanId);
    }

}


/*----------------------------------------------------------*|
|*  # TOKEN URI                                             *|
|*----------------------------------------------------------*/

contract PWNLOAN_TokenUri_Test is PWNLOANTest {

    string tokenUri;
    uint256 loanId;

    function setUp() override public {
        super.setUp();

        tokenUri = "test.uri.xyz";

        vm.mockCall(
            activeLoanContract,
            abi.encodeWithSignature("loanMetadataUri()"),
            abi.encode(tokenUri)
        );

        vm.prank(activeLoanContract);
        loanId = loanToken.mint(alice);
    }


    function test_shouldCallLoanContract() external {
        vm.expectCall(
            activeLoanContract,
            abi.encodeWithSignature("loanMetadataUri()")
        );

        loanToken.tokenURI(loanId);
    }

    function test_shouldReturnCorrectValue() external {
        string memory _tokenUri = loanToken.tokenURI(loanId);

        assertEq(tokenUri, _tokenUri);
    }

}
