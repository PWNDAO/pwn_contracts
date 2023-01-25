// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "MultiToken/MultiToken.sol";

import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "@pwn/config/PWNConfig.sol";
import "@pwn/hub/PWNHub.sol";
import "@pwn/hub/PWNHubTags.sol";
import "@pwn/loan/terms/simple/loan/PWNSimpleLoan.sol";
import "@pwn/loan/terms/simple/factory/offer/PWNSimpleLoanSimpleOffer.sol";
import "@pwn/loan/terms/simple/factory/offer/PWNSimpleLoanListOffer.sol";
import "@pwn/loan/terms/simple/factory/request/PWNSimpleLoanSimpleRequest.sol";
import "@pwn/loan/token/PWNLOAN.sol";
import "@pwn/nonce/PWNRevokedNonce.sol";

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
    PWNRevokedNonce revokedOfferNonce;
    PWNRevokedNonce revokedRequestNonce;
    PWNSimpleLoanSimpleOffer simpleOffer;
    PWNSimpleLoanListOffer listOffer;
    PWNSimpleLoanSimpleRequest simpleRequest;

    address admin = address(0xad814);
    address feeCollector = address(0xfeeC001ec704);
    uint256 lenderPK = uint256(777);
    address lender = vm.addr(lenderPK);
    uint256 borrowerPK = uint256(888);
    address borrower = vm.addr(borrowerPK);
    uint256 nonce = uint256(keccak256("nonce_1"));
    PWNSimpleLoanSimpleOffer.Offer defaultOffer;

    function setUp() external {
        if (block.chainid == 31337)
            _deployRealm();
        else if (block.chainid == 5) {
            hub = PWNHub(0xd31b4cfee06B8a662F522CaBC2D925038Be0aAC5);
            config = PWNConfig(0x2adA1d4F43021A5786393E7C62bE6A8efF766b1C);
            loanToken = PWNLOAN(0xa0A4886398e509250d5734B31F7323019774B5e5);
            simpleLoan = PWNSimpleLoan(0x05397F372130bE1Ab43dF72c896278Bff2Db8A9E);
            revokedOfferNonce = PWNRevokedNonce(0xF5A49a2f6d9E03e152dDCDEaaC6d479AC8eB92A7);
            revokedRequestNonce = PWNRevokedNonce(0x70aDA3E22E755593Db05B5342062eB849B8E8ccd);
            simpleOffer = PWNSimpleLoanSimpleOffer(0xaff389b04AC4D42Ff0d497d2a3C305ab4A5d629D);
            listOffer = PWNSimpleLoanListOffer(0xC0d64e5cc29a7FE91a82C40b71E46f69F0fFFBdd);
            simpleRequest = PWNSimpleLoanSimpleRequest(0x6f3E641DA9201B6C60bb7964Ac4d55EE27af24C3);
        }

        // Deploy tokens
        t20 = new T20();
        t721 = new T721();
        t1155 = new T1155();
        loanAsset = new T20();

        // Default offer
        defaultOffer = PWNSimpleLoanSimpleOffer.Offer({
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
            lateRepaymentEnabled: false,
            nonce: nonce
        });
    }

    function _deployRealm() private {
        // Deploy realm
        PWNConfig configSingleton = new PWNConfig();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(configSingleton),
            admin,
            abi.encodeWithSignature("initialize(address,uint16,address)", address(this), 0, feeCollector)
        );
        config = PWNConfig(address(proxy));
        hub = new PWNHub(address(this));

        loanToken = new PWNLOAN(address(hub));
        simpleLoan = new PWNSimpleLoan(address(hub), address(loanToken), address(config));

        revokedOfferNonce = new PWNRevokedNonce(address(hub), PWNHubTags.LOAN_OFFER);
        simpleOffer = new PWNSimpleLoanSimpleOffer(address(hub), address(revokedOfferNonce));
        listOffer = new PWNSimpleLoanListOffer(address(hub), address(revokedOfferNonce));

        revokedRequestNonce = new PWNRevokedNonce(address(hub), PWNHubTags.LOAN_REQUEST);
        simpleRequest = new PWNSimpleLoanSimpleRequest(address(hub), address(revokedRequestNonce));

        // Set hub tags
        address[] memory addrs = new address[](7);
        addrs[0] = address(simpleLoan);
        addrs[1] = address(simpleOffer);
        addrs[2] = address(simpleOffer);
        addrs[3] = address(listOffer);
        addrs[4] = address(listOffer);
        addrs[5] = address(simpleRequest);
        addrs[6] = address(simpleRequest);

        bytes32[] memory tags = new bytes32[](7);
        tags[0] = PWNHubTags.ACTIVE_LOAN;
        tags[1] = PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY;
        tags[2] = PWNHubTags.LOAN_OFFER;
        tags[3] = PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY;
        tags[4] = PWNHubTags.LOAN_OFFER;
        tags[5] = PWNHubTags.SIMPLE_LOAN_TERMS_FACTORY;
        tags[6] = PWNHubTags.LOAN_REQUEST;

        hub.setTags(addrs, tags, true);
    }

    function _sign(uint256 pk, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    // Create from offer

    function _createERC20Loan() internal returns (uint256) {
        // Offer
        defaultOffer.collateralCategory = MultiToken.Category.ERC20;
        defaultOffer.collateralAddress = address(t20);
        defaultOffer.collateralId = 0;
        defaultOffer.collateralAmount = 10e18;

        // Mint initial state
        t20.mint(borrower, 10e18);

        // Approve collateral
        vm.prank(borrower);
        t20.approve(address(simpleLoan), 10e18);

        // Create LOAN
        return _createLoan(defaultOffer, "");
    }

    function _createERC721Loan() internal returns (uint256) {
        // Offer
        defaultOffer.collateralCategory = MultiToken.Category.ERC721;
        defaultOffer.collateralAddress = address(t721);
        defaultOffer.collateralId = 42;
        defaultOffer.collateralAmount = 0;

        // Mint initial state
        t721.mint(borrower, 42);

        // Approve collateral
        vm.prank(borrower);
        t721.approve(address(simpleLoan), 42);

        // Create LOAN
        return _createLoan(defaultOffer, "");
    }

    function _createERC1155Loan() internal returns (uint256) {
        return _createERC1155LoanFailing("");
    }

    function _createERC1155LoanFailing(bytes memory revertData) internal returns (uint256) {
        // Offer
        defaultOffer.collateralCategory = MultiToken.Category.ERC1155;
        defaultOffer.collateralAddress = address(t1155);
        defaultOffer.collateralId = 42;
        defaultOffer.collateralAmount = 10e18;

        // Mint initial state
        t1155.mint(borrower, 42, 10e18);

        // Approve collateral
        vm.prank(borrower);
        t1155.setApprovalForAll(address(simpleLoan), true);

        // Create LOAN
        return _createLoan(defaultOffer, revertData);
    }

    function _createLoan(PWNSimpleLoanSimpleOffer.Offer memory _offer, bytes memory revertData) private returns (uint256) {
        // Sign offer
        bytes memory signature = _sign(lenderPK, simpleOffer.getOfferHash(_offer));

        // Mint initial state
        loanAsset.mint(lender, 100e18);

        // Approve loan asset
        vm.prank(lender);
        loanAsset.approve(address(simpleLoan), 100e18);

        // Loan factory data (need for vm.prank to work properly when creating a loan)
        bytes memory loanTermsFactoryData = simpleOffer.encodeLoanTermsFactoryData(_offer);

        // Create LOAN
        if (keccak256(revertData) != keccak256("")) {
            vm.expectRevert(revertData);
        }
        vm.prank(borrower);
        return simpleLoan.createLOAN({
            loanTermsFactoryContract: address(simpleOffer),
            loanTermsFactoryData: loanTermsFactoryData,
            signature: signature,
            loanAssetPermit: "",
            collateralPermit: ""
        });
    }

    // Repay

    function _repayLoan(uint256 loanId) internal {
        _repayLoanFailing(loanId, "");
    }

    function _repayLoanFailing(uint256 loanId, bytes memory revertData) internal {
        // Get the yield by farming 100000% APR food tokens
        loanAsset.mint(borrower, 10e18);

        // Approve loan asset
        vm.prank(borrower);
        loanAsset.approve(address(simpleLoan), 110e18);

        // Repay loan
        if (keccak256(revertData) != keccak256("")) {
            vm.expectRevert(revertData);
        }
        vm.prank(borrower);
        simpleLoan.repayLOAN(loanId, "");
    }

}