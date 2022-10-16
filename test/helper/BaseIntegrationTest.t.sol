// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "MultiToken/MultiToken.sol";

import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "@pwn/config/PWNConfig.sol";
import "@pwn/hub/PWNHub.sol";
import "@pwn/hub/PWNHubTags.sol";
import "@pwn/loan/type/PWNSimpleLoan.sol";
import "@pwn/loan/PWNLOAN.sol";
import "@pwn/loan-factory/simple-loan/offer/PWNSimpleLoanSimpleOffer.sol";
import "@pwn/loan-factory/PWNRevokedOfferNonce.sol";

import "@pwn-test/helper/token/T20.sol";
import "@pwn-test/helper/token/T721.sol";
import "@pwn-test/helper/token/T1155.sol";


abstract contract BaseIntegrationTest is Test {

    T20 t20;
    T721 t721;
    T1155 t1155;
    T20 loanAsset;

    PWNHub hub;
    PWNConfig config;
    PWNLOAN loanToken;
    PWNSimpleLoan simpleLoan;
    PWNRevokedOfferNonce revokedOfferNonce;
    PWNSimpleLoanSimpleOffer simpleOffer;

    address admin = address(0xad814);
    uint256 lenderPK = uint256(777);
    address lender = vm.addr(lenderPK);
    address borrower = address(0x1001);
    bytes32 nonce = keccak256("nonce_1");
    PWNSimpleLoanSimpleOffer.Offer offer;

    function setUp() external {
        // Deploy realm
        PWNConfig configSingleton = new PWNConfig();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(configSingleton),
            admin,
            abi.encodeWithSignature("initialize(address,uint16)", address(this), 0)
        );
        config = PWNConfig(address(proxy));
        hub = new PWNHub();

        loanToken = new PWNLOAN(address(hub));
        simpleLoan = new PWNSimpleLoan(address(hub), address(loanToken), address(config));

        revokedOfferNonce = new PWNRevokedOfferNonce(address(hub));
        simpleOffer = new PWNSimpleLoanSimpleOffer(address(hub), address(revokedOfferNonce));

        // Set hub tags
        hub.setTag(address(simpleLoan), PWNHubTags.ACTIVE_LOAN, true);
        hub.setTag(address(simpleOffer), PWNHubTags.LOAN_FACTORY, true);
        hub.setTag(address(simpleOffer), PWNHubTags.LOAN_OFFER, true);

        // Deploy tokens
        t20 = new T20();
        t721 = new T721();
        t1155 = new T1155();
        loanAsset = new T20();

        // Default offer
        offer = PWNSimpleLoanSimpleOffer.Offer({
            collateralCategory: MultiToken.Category.ERC1155,
            collateralAddress: address(t1155),
            collateralId: 42,
            collateralAmount: 10e18,
            loanAssetAddress: address(loanAsset),
            loanAmount: 100e18,
            loanYield: 10e18,
            duration: 3600,
            expiration: 0,
            borrower: borrower,
            lender: lender,
            isPersistent: false,
            nonce: nonce
        });
    }

    function _sign(uint256 pk, bytes32 digest) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _createERC20Loan() internal returns (uint256) {
        // Offer
        offer.collateralCategory = MultiToken.Category.ERC20;
        offer.collateralAddress = address(t20);
        offer.collateralId = 0;
        offer.collateralAmount = 10e18;

        // Mint initial state
        t20.mint(borrower, 10e18);

        // Approve collateral
        vm.prank(borrower);
        t20.approve(address(simpleLoan), 10e18);

        // Create LOAN
        return _createLoan(offer, "");
    }

    function _createERC721Loan() internal returns (uint256) {
        // Offer
        offer.collateralCategory = MultiToken.Category.ERC721;
        offer.collateralAddress = address(t721);
        offer.collateralId = 42;
        offer.collateralAmount = 1;

        // Mint initial state
        t721.mint(borrower, 42);

        // Approve collateral
        vm.prank(borrower);
        t721.approve(address(simpleLoan), 42);

        // Create LOAN
        return _createLoan(offer, "");
    }

    function _createERC1155Loan() internal returns (uint256) {
        return _createERC1155LoanFailing("");
    }

    function _createERC1155LoanFailing(bytes memory revertMessage) internal returns (uint256) {
        // Offer
        offer.collateralCategory = MultiToken.Category.ERC1155;
        offer.collateralAddress = address(t1155);
        offer.collateralId = 42;
        offer.collateralAmount = 10e18;

        // Mint initial state
        t1155.mint(borrower, 42, 10e18);

        // Approve collateral
        vm.prank(borrower);
        t1155.setApprovalForAll(address(simpleLoan), true);

        // Create LOAN
        return _createLoan(offer, revertMessage);
    }

    function _createLoan(PWNSimpleLoanSimpleOffer.Offer memory _offer, bytes memory revertMessage) private returns (uint256) {
        // Sign offer
        bytes memory signature = _sign(lenderPK, simpleOffer.getOfferHash(_offer));

        // Mint initial state
        loanAsset.mint(lender, 100e18);

        // Approve loan asset
        vm.prank(lender);
        loanAsset.approve(address(simpleLoan), 100e18);

        // Create LOAN
        if (keccak256(revertMessage) != keccak256("")) {
            vm.expectRevert(revertMessage);
        }
        vm.prank(borrower);
        return simpleLoan.createLOAN({
            loanFactoryContract: address(simpleOffer),
            loanFactoryData: abi.encode(_offer),
            signature: signature,
            loanAssetPermit: "",
            collateralPermit: ""
        });
    }

    function _repayLoan(uint256 loanId) internal {
        _repayLoanFailing(loanId, "");
    }

    function _repayLoanFailing(uint256 loanId, bytes memory revertMessage) internal {
        // Get the yield by farming 100000% APR food tokens
        loanAsset.mint(borrower, 10e18);

        // Approve loan asset
        vm.prank(borrower);
        loanAsset.approve(address(simpleLoan), 110e18);

        // Repay loan
        if (keccak256(revertMessage) != keccak256("")) {
            vm.expectRevert(revertMessage);
        }
        vm.prank(borrower);
        simpleLoan.repayLoan(loanId, "");
    }

}