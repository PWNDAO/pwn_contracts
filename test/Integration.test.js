const { expect } = require("chai");
const { time } = require('@openzeppelin/test-helpers');

const delay = ms => new Promise(res => setTimeout(res, ms));

let ERC20;
let ERC721;
let ERC1155;

let NFT, WETH, DAI, GAME;

let PWN;
let PWNDeed;
let PWNVault;

let owner;

let borrower;
let lender1;
let lender2;

let addr1;
let addr2;
let addrs;

let date = new Date();

const CATEGORY = {
	ERC20: 0,
	ERC721: 1,
	ERC1155: 2,
	unknown: 3,
};


beforeEach(async function () {
	// Get the ContractFactory and Signers here.
	ERC20 = await ethers.getContractFactory("Basic20");
	ERC721 = await ethers.getContractFactory("Basic721");
	ERC1155 = await ethers.getContractFactory("Basic1155");

	PWN = await ethers.getContractFactory("PWN");
	PWNDeed = await ethers.getContractFactory("PWNDeed");
	PWNVault = await ethers.getContractFactory("PWNVault");

	[borrower, lender1, lender2, addr1, addr2, ...addrs] = await ethers.getSigners();

	WETH = await ERC20.deploy("Fake wETH", "WETH");
	DAI = await ERC20.deploy("Fake Dai", "DAI");
	NFT = await ERC721.deploy("Real NFT", "NFT");
	GAME = await ERC1155.deploy("https://pwn.finance/game/")

	PWNDeed = await PWNDeed.deploy("https://pwn.finance/");
	PWNVault = await PWNVault.deploy();
	PWN = await PWN.deploy(PWNDeed.address, PWNVault.address);

	await NFT.deployed();
	await DAI.deployed();
	await GAME.deployed();
	await PWNDeed.deployed();
	await PWNVault.deployed();
	await PWN.deployed();

	await PWNDeed.setPWN(PWN.address);
	await PWNVault.setPWN(PWN.address);

	await DAI.mint(await lender1.getAddress(),1000);
	await DAI.mint(await borrower.getAddress(),200);
	await NFT.mint(await borrower.getAddress(),42);
	await GAME.mint(await borrower.getAddress(), 1337, 1, 0);

	bDAI = DAI.connect(borrower);
	lDAI = DAI.connect(lender1);
	bNFT = NFT.connect(borrower);
	lNFT = NFT.connect(lender1);
	bGAME = GAME.connect(borrower);
	lGAME = GAME.connect(lender1);
	bPWN = PWN.connect(borrower);
	lPWN = PWN.connect(lender1);
	bPWND = PWNDeed.connect(borrower);
	lPWND = PWNDeed.connect(lender1);
});

describe("PWN contract", function () {

	// You can nest describe calls to create subsections.
	describe("Deployment", function () {

		it("Should deploy PWN with links to Deed & Vault", async function () {
			expect(await PWN.deed()).to.equal(await PWNDeed.address);
			expect(await PWN.vault()).to.equal(await PWNVault.address);
		});

		it("Should deploy Vault with a link to PWN", async function () {
			expect(await PWNVault.PWN()).to.equal(await PWN.address);
		});

		it("Should deploy Deed with a link to PWN", async function () {
			expect(await PWNDeed.PWN()).to.equal(await PWN.address);
		});

		it("Should set initial balances", async function () {
			expect(await DAI.balanceOf(await borrower.getAddress())).to.equal(200);
			expect(await DAI.balanceOf(await lender1.getAddress())).to.equal(1000);
			expect(await NFT.ownerOf(42)).to.equal(await borrower.getAddress());
			expect((await GAME.balanceOf(await borrower.getAddress(), 1337)).toNumber()).to.equal(1);
		});

	});


	describe("Workflow - New deeds with arbitrary collateral", function () {

		it("Should be possible to create an ERC20 deed", async function () {
			await bDAI.approve(PWNVault.address, 100);
			const DID = await bPWN.callStatic.createDeed(DAI.address, CATEGORY.ERC20, 3600, 0, 100);
			await bPWN.createDeed(DAI.address, CATEGORY.ERC20, 3600, 0, 100);


			const balance = await PWNDeed.balanceOf(await borrower.getAddress(), DID.toNumber());
			expect(await DAI.balanceOf(PWNVault.address)).to.equal(100);
			expect(balance.toNumber()).to.equal(1);
		});

		it("Should be possible to create an ERC721 deed", async function () {
			await bNFT.approve(PWNVault.address, 42);
			const DID = await bPWN.callStatic.createDeed(NFT.address, CATEGORY.ERC721, 3600, 42, 0);

			await bPWN.createDeed(NFT.address, CATEGORY.ERC721, 3600, 42, 0);

			const balance = await PWNDeed.balanceOf(await borrower.getAddress(), DID.toNumber());
			expect(await NFT.ownerOf(42)).to.equal(PWNVault.address);
			expect(balance).to.equal(1);
		});

		it("Should be possible to create an ERC1155 deed", async function () {
			await bGAME.setApprovalForAll(PWNVault.address, true);
			const DID = await bPWN.callStatic.createDeed(GAME.address, CATEGORY.ERC1155, 3600, 1337, 1);

			await bPWN.createDeed(GAME.address, CATEGORY.ERC1155, 3600, 1337, 1);

			const balance = await PWNDeed.balanceOf(await borrower.getAddress(), DID.toNumber());
			expect(await GAME.balanceOf(await borrower.getAddress(), 1337)).to.equal(0);
			expect(await GAME.balanceOf(await PWNVault.address, 1337)).to.equal(1);
			expect(balance).to.equal(1);
		});

	});


	describe("Workflow - New deeds with arbitrary collateral", function () {

		it("Should be possible to revoke an ERC20 deed", async function () {
			await bDAI.approve(PWNVault.address, 100);
			const DID = await bPWN.callStatic.createDeed(DAI.address, CATEGORY.ERC20, 3600, 0, 100);
			await bPWN.createDeed(DAI.address, CATEGORY.ERC20, 3600, 0, 100);

			await bPWN.revokeDeed(DID.toNumber());

			const balance = await PWNDeed.balanceOf(await borrower.getAddress(), DID.toNumber());
			expect(await DAI.balanceOf(PWNVault.address)).to.equal(0);
			expect(await DAI.balanceOf(borrower.getAddress())).to.equal(200);
			expect(balance.toNumber()).to.equal(0);
		});

		it("Should be possible to revoke an ERC721 deed", async function () {
			await bNFT.approve(PWNVault.address, 42);
			const DID = await bPWN.callStatic.createDeed(NFT.address, CATEGORY.ERC721, 3600, 42, 0);
			await bPWN.createDeed(NFT.address, CATEGORY.ERC721, 3600, 42, 0);

			await bPWN.revokeDeed(DID.toNumber());

			const balance = await PWNDeed.balanceOf(await borrower.getAddress(), DID.toNumber());
			expect(await NFT.ownerOf(42)).to.equal(await borrower.getAddress());
			expect(balance).to.equal(0);
		});

		it("Should be possible to revoke an ERC1155 deed", async function () {
			await bGAME.setApprovalForAll(PWNVault.address, true);
			const DID = await bPWN.callStatic.createDeed(GAME.address, CATEGORY.ERC1155, 3600, 1337, 1);
			await bPWN.createDeed(GAME.address, CATEGORY.ERC1155, 3600, 1337, 1);

			await bPWN.revokeDeed(DID.toNumber());

			const balance = await PWNDeed.balanceOf(await borrower.getAddress(), DID.toNumber());
			expect(await GAME.balanceOf(await borrower.getAddress(), 1337)).to.equal(1);
			expect(await GAME.balanceOf(await PWNVault.address, 1337)).to.equal(0);
			expect(balance).to.equal(0);
		});

	});


	describe("Workflow - Offers handling", function () {

		it("Should be possible make an offer", async function () {
			await bPWND.setApprovalForAll(PWNVault.address, true);

			await bNFT.approve(PWNVault.address, 42);
			const DID = await bPWN.callStatic.createDeed(NFT.address, CATEGORY.ERC721, 3600, 42, 0);
			await bPWN.createDeed(NFT.address, CATEGORY.ERC721, 3600, 42, 0);
			await lDAI.approve(PWNVault.address, 1000);

			const offer = await lPWN.callStatic.makeOffer(lDAI.address, 1000, DID, 1200);
			await lPWN.makeOffer(lDAI.address, 1000, DID, 1200);

			const offers = await PWNDeed.getOffers(DID);
			expect(offers[0]).is.equal(offer);
		});

		it("Should be possible to revoke an offer", async function () {
			await bPWND.setApprovalForAll(PWNVault.address, true);

			await bNFT.approve(PWNVault.address, 42);
			const DID = await bPWN.callStatic.createDeed(NFT.address, CATEGORY.ERC721, 3600, 42, 0);
			await bPWN.createDeed(NFT.address, CATEGORY.ERC721, 3600, 42, 0);

			await lDAI.approve(PWNVault.address, 1000);
			const offer = await lPWN.callStatic.makeOffer(lDAI.address, 1000, DID, 1200);
			await lPWN.makeOffer(lDAI.address, 1000, DID, 1200);

			await lPWN.revokeOffer(offer);

			expect((await PWNDeed.getDeedID(offer)).toNumber()).is.equal(0);
		});

		it("Should be possible to accept an offer", async function () {
			await bPWND.setApprovalForAll(PWNVault.address, true);

			await bNFT.approve(PWNVault.address, 42);
			const DID = await bPWN.callStatic.createDeed(NFT.address, CATEGORY.ERC721, 3600, 42, 0);
			await bPWN.createDeed(NFT.address, CATEGORY.ERC721, 3600, 42, 0);

			await lDAI.approve(PWNVault.address, 1000);
			const offer = await lPWN.callStatic.makeOffer(DAI.address, 1000, DID, 1200);
			await lPWN.makeOffer(DAI.address, 1000, DID, 1200);

			await bPWN.acceptOffer(offer);

			expect(await PWNDeed.getAcceptedOffer(DID)).is.equal(offer);
			expect(await DAI.balanceOf(await borrower.getAddress())).is.equal(1200);
			expect(await DAI.balanceOf(await lender1.getAddress())).is.equal(0);
			expect(await DAI.balanceOf(PWNVault.address)).is.equal(0);
			expect(await NFT.ownerOf(42)).to.equal(PWNVault.address);
			BBalance = await PWNDeed.balanceOf(await borrower.getAddress(), DID);
			expect(BBalance.toNumber()).to.equal(0);
			LBalance = await PWNDeed.balanceOf(await lender1.getAddress(), DID);
			expect(LBalance.toNumber()).to.equal(1);
		});

	});


	describe("Workflow - Settlement", function () {

		it("Should be possible to pay back", async function () {
			await bPWND.setApprovalForAll(PWNVault.address, true);

			await bNFT.approve(PWNVault.address, 42);
			const DID = await bPWN.callStatic.createDeed(NFT.address, CATEGORY.ERC721, 3600, 42, 0);
			await bPWN.createDeed(NFT.address, CATEGORY.ERC721, 3600, 42, 0);

			await lDAI.approve(PWNVault.address, 1000);
			const offer = await lPWN.callStatic.makeOffer(DAI.address, 1000, DID, 1200);
			await lPWN.makeOffer(DAI.address, 1000, DID, 1200);

			await bPWN.acceptOffer(offer);
			await bDAI.approve(PWNVault.address,1200);

			await bPWN.repayLoan(DID);

			expect(await DAI.balanceOf(await borrower.getAddress())).is.equal(0);
			expect(await DAI.balanceOf(await lender1.getAddress())).is.equal(0);
			expect(await DAI.balanceOf(PWNVault.address)).is.equal(1200);
			expect(await NFT.ownerOf(42)).to.equal(await borrower.getAddress());
			BBalance = await PWNDeed.balanceOf(await borrower.getAddress(), DID);
			expect(BBalance.toNumber()).to.equal(0);
			LBalance = await PWNDeed.balanceOf(await lender1.getAddress(), DID);
			expect(LBalance.toNumber()).to.equal(1);
		});

		it("Should be possible to claim after deed was paid", async function () {
			await bPWND.setApprovalForAll(PWNVault.address, true);

			await bNFT.approve(PWNVault.address, 42);
			const DID = await bPWN.callStatic.createDeed(NFT.address, CATEGORY.ERC721, 3600, 42, 0);
			await bPWN.createDeed(NFT.address, CATEGORY.ERC721, 3600, 42, 0);

			await lDAI.approve(PWNVault.address, 1000);
			const offer = await lPWN.callStatic.makeOffer(DAI.address, 1000, DID, 1200);
			await lPWN.makeOffer(DAI.address, 1000, DID, 1200);

			await bPWN.acceptOffer(offer);
			await bDAI.approve(PWNVault.address,1200);
			await bPWN.repayLoan(DID);

			await lPWN.claimDeed(DID);

			expect(await DAI.balanceOf(await borrower.getAddress())).is.equal(0);
			expect(await DAI.balanceOf(await lender1.getAddress())).is.equal(1200);
			expect(await DAI.balanceOf(PWNVault.address)).is.equal(0);
			expect(await NFT.ownerOf(42)).to.equal(await borrower.getAddress());
			BBalance = await PWNDeed.balanceOf(await borrower.getAddress(), DID);
			expect(BBalance.toNumber()).to.equal(0);
			LBalance = await PWNDeed.balanceOf(await lender1.getAddress(), DID);
			expect(LBalance.toNumber()).to.equal(0);
		});

		it("Should be possible to claim if deed wasn't paid", async function () {
			await bPWND.setApprovalForAll(PWNVault.address, true);

			await bNFT.approve(PWNVault.address, 42);
			const DID = await bPWN.callStatic.createDeed(NFT.address, CATEGORY.ERC721, 3600, 42, 0);
			await bPWN.createDeed(NFT.address, CATEGORY.ERC721, 3600, 42, 0);

			await lDAI.approve(PWNVault.address, 1000);
			const offer = await lPWN.callStatic.makeOffer(DAI.address, 1000, DID, 1200);
			await lPWN.makeOffer(DAI.address, 1000, DID, 1200);

			await bPWN.acceptOffer(offer);

			await ethers.provider.send("evm_increaseTime", [parseInt(time.duration.days(7)) + 2000]); // move
			await ethers.provider.send("evm_mine");

			await lPWN.claimDeed(DID);

			expect(await DAI.balanceOf(await borrower.getAddress())).is.equal(1200);
			expect(await DAI.balanceOf(await lender1.getAddress())).is.equal(0);
			expect(await DAI.balanceOf(PWNVault.address)).is.equal(0);
			expect(await NFT.ownerOf(42)).to.equal(await lender1.getAddress());
			BBalance = await PWNDeed.balanceOf(borrower.getAddress(), DID);
			expect(BBalance.toNumber()).to.equal(0);
			LBalance = await PWNDeed.balanceOf(lender1.getAddress(), DID);
			expect(LBalance.toNumber()).to.equal(0);
		});

	});

});
