const { expect } = require("chai");
const { time } = require('@openzeppelin/test-helpers');
const { CATEGORY, getOfferHashBytes, getOfferStruct } = require("./test-helpers");


describe("PWN contract", function () {

	let ERC20, ERC721, ERC1155;
	let NFT, WETH, DAI, GAME;
	let PWN, PWNDeed, PWNVault;
	let borrower, lender;
	let addr1, addr2, addrs;

	const deedEventIface = new ethers.utils.Interface([
		"event DeedCreated(uint256 indexed did, address indexed lender, bytes32 indexed offerHash)",
	]);

	const lInitialDAI = 1000;
	const bInitialDAI = 200;
	const bInitialWETH = 100;
	const nonce = ethers.utils.solidityKeccak256([ "string" ], [ "nonce" ]);

	beforeEach(async function () {
		ERC20 = await ethers.getContractFactory("Basic20");
		ERC721 = await ethers.getContractFactory("Basic721");
		ERC1155 = await ethers.getContractFactory("Basic1155");

		PWN = await ethers.getContractFactory("PWN");
		PWNDeed = await ethers.getContractFactory("PWNDeed");
		PWNVault = await ethers.getContractFactory("PWNVault");

		[borrower, lender, addr1, addr2, ...addrs] = await ethers.getSigners();

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

		await DAI.mint(lender.address, lInitialDAI);
		await DAI.mint(borrower.address, bInitialDAI);
		await WETH.mint(borrower.address, bInitialWETH);
		await NFT.mint(borrower.address, 42);
		await GAME.mint(borrower.address, 1337, 1, 0);

		bDAI = DAI.connect(borrower);
		lDAI = DAI.connect(lender);
		bWETH = WETH.connect(borrower);
		lWETH = WETH.connect(lender);
		bNFT = NFT.connect(borrower);
		lNFT = NFT.connect(lender);
		bGAME = GAME.connect(borrower);
		lGAME = GAME.connect(lender);
		bPWN = PWN.connect(borrower);
		lPWN = PWN.connect(lender);
		bPWND = PWNDeed.connect(borrower);
		lPWND = PWNDeed.connect(lender);
	});


	describe("Deployment", function () {

		it("Should deploy PWN with links to Deed & Vault", async function () {
			expect(await PWN.deed()).to.equal(PWNDeed.address);
			expect(await PWN.vault()).to.equal(PWNVault.address);
		});

		it("Should deploy Vault with a link to PWN", async function () {
			expect(await PWNVault.PWN()).to.equal(PWN.address);
		});

		it("Should deploy Deed with a link to PWN", async function () {
			expect(await PWNDeed.PWN()).to.equal(PWN.address);
		});

		it("Should set initial balances", async function () {
			expect(await DAI.balanceOf(lender.address)).to.equal(lInitialDAI);
			expect(await DAI.balanceOf(borrower.address)).to.equal(bInitialDAI);
			expect(await WETH.balanceOf(borrower.address)).to.equal(bInitialWETH);
			expect(await NFT.ownerOf(42)).to.equal(borrower.address);
			expect((await GAME.balanceOf(borrower.address, 1337)).toNumber()).to.equal(1);
		});

	});


	describe("Workflow - Offers handling", function () {

		it("Should be possible to revoke an offer", async function () {
			const offerHash = getOfferHashBytes(
				getOfferStruct(
					NFT.address, CATEGORY.ERC721, 0, 42,
					DAI.address, 1000,
					1200, 3600, 0, lender.address, nonce, 31337,
				)
			);
			const signature = await lender.signMessage(offerHash);

			lPWN.revokeOffer(offerHash, signature);

			const isRevoked = await lPWND.isRevoked(offerHash);
			expect(isRevoked).to.equal(true);
		});

	});


	describe("Workflow - New deeds with arbitrary collateral", function () {

		it("Should be possible to create a deed with ERC20 collateral", async function () {
			const offer = [
				WETH.address, CATEGORY.ERC20, 100, 0,
				DAI.address, 1000,
				1200, 3600, 0, lender.address, nonce,
			];
			const offerHash = getOfferHashBytes(
				getOfferStruct(...offer)
			);
			const signature = await lender.signMessage(offerHash);
			await lDAI.approve(PWNVault.address, 1000);

			await bWETH.approve(PWNVault.address, 200);
			const tx = await bPWN.createDeed(...offer, signature);
			const response = await tx.wait();
			const logDescription = deedEventIface.parseLog(response.logs[1]);
			const did = logDescription.args.did.toNumber();

			expect(await PWNDeed.balanceOf(lender.address, did)).to.equal(1);
			expect(await WETH.balanceOf(PWNVault.address)).to.equal(bInitialWETH);
			expect(await DAI.balanceOf(borrower.address)).to.equal(bInitialDAI + 1000);
		});

		it("Should be possible to create a deed with ERC721 collateral", async function () {
			const offer = [
				NFT.address, CATEGORY.ERC721, 0, 42,
				DAI.address, 1000,
				1200, 3600, 0, lender.address, nonce,
			];
			const offerHash = getOfferHashBytes(
				getOfferStruct(...offer)
			);
			const signature = await lender.signMessage(offerHash);
			await lDAI.approve(PWNVault.address, 1000);

			await bNFT.approve(PWNVault.address, 42);
			const tx = await bPWN.createDeed(...offer, signature);
			const response = await tx.wait();
			const logDescription = deedEventIface.parseLog(response.logs[1]);
			const did = logDescription.args.did.toNumber();

			expect(await PWNDeed.balanceOf(lender.address, did)).to.equal(1);
			expect(await NFT.ownerOf(42)).to.equal(PWNVault.address);
			expect(await DAI.balanceOf(borrower.address)).to.equal(bInitialDAI + 1000);
		});

		it("Should be possible to create a deed with ERC1155 collateral", async function () {
			const offer = [
				GAME.address, CATEGORY.ERC1155, 1, 1337,
				DAI.address, 1000,
				1200, 3600, 0, lender.address, nonce,
			];
			const offerHash = getOfferHashBytes(
				getOfferStruct(...offer)
			);
			const signature = await lender.signMessage(offerHash);
			await lDAI.approve(PWNVault.address, 1000);

			await bGAME.setApprovalForAll(PWNVault.address, true);
			const tx = await bPWN.createDeed(...offer, signature);
			const response = await tx.wait();
			const logDescription = deedEventIface.parseLog(response.logs[1]);
			const did = logDescription.args.did.toNumber();

			expect(await PWNDeed.balanceOf(lender.address, did)).to.equal(1);
			expect(await GAME.balanceOf(borrower.address, 1337)).to.equal(0);
			expect(await GAME.balanceOf(PWNVault.address, 1337)).to.equal(1);
			expect(await DAI.balanceOf(borrower.address)).to.equal(bInitialDAI + 1000);
		});

	});


	describe("Workflow - Settlement", function () {

		it("Should be possible to pay back", async function () {
			const offer = [
				NFT.address, CATEGORY.ERC721, 0, 42,
				DAI.address, 1000,
				1200, 3600, 0, lender.address, nonce,
			];
			const offerHash = getOfferHashBytes(
				getOfferStruct(...offer)
			);
			const signature = await lender.signMessage(offerHash);
			await lDAI.approve(PWNVault.address, 1000);

			await bNFT.approve(PWNVault.address, 42);
			const tx = await bPWN.createDeed(...offer, signature);
			const response = await tx.wait();
			const logDescription = deedEventIface.parseLog(response.logs[1]);
			const did = logDescription.args.did.toNumber();

			await bDAI.approve(PWNVault.address, 1200);
			await bPWN.repayLoan(did);

			expect(await DAI.balanceOf(borrower.address)).is.equal(0);
			expect(await DAI.balanceOf(lender.address)).is.equal(0);
			expect(await DAI.balanceOf(PWNVault.address)).is.equal(1200);
			expect(await NFT.ownerOf(42)).to.equal(borrower.address);
		});

		it("Should be possible to claim after deed was paid", async function () {
			const offer = [
				NFT.address, CATEGORY.ERC721, 0, 42,
				DAI.address, 1000,
				1200, 3600, 0, lender.address, nonce,
			];
			const offerHash = getOfferHashBytes(
				getOfferStruct(...offer)
			);
			const signature = await lender.signMessage(offerHash);
			await lDAI.approve(PWNVault.address, 1000);

			await bNFT.approve(PWNVault.address, 42);
			const tx = await bPWN.createDeed(...offer, signature);
			const response = await tx.wait();
			const logDescription = deedEventIface.parseLog(response.logs[1]);
			const did = logDescription.args.did.toNumber();

			await bDAI.approve(PWNVault.address, 1200);
			await bPWN.repayLoan(did);

			await lPWN.claimDeed(did);

			expect(await DAI.balanceOf(borrower.address)).is.equal(0);
			expect(await DAI.balanceOf(lender.address)).is.equal(1200);
			expect(await DAI.balanceOf(PWNVault.address)).is.equal(0);
			expect(await NFT.ownerOf(42)).to.equal(borrower.address);
			expect(await PWNDeed.balanceOf(lender.address, did)).to.equal(0);
		});

		it("Should be possible to claim if deed wasn't paid", async function () {
			const offer = [
				NFT.address, CATEGORY.ERC721, 0, 42,
				DAI.address, 1000,
				1200, 3600, 0, lender.address, nonce,
			];
			const offerHash = getOfferHashBytes(
				getOfferStruct(...offer)
			);
			const signature = await lender.signMessage(offerHash);
			await lDAI.approve(PWNVault.address, 1000);

			await bNFT.approve(PWNVault.address, 42);
			const tx = await bPWN.createDeed(...offer, signature);
			const response = await tx.wait();
			const logDescription = deedEventIface.parseLog(response.logs[1]);
			const did = logDescription.args.did.toNumber();

			await ethers.provider.send("evm_increaseTime", [parseInt(time.duration.days(7)) + 2000]);
			await ethers.provider.send("evm_mine");

			await lPWN.claimDeed(did);

			expect(await DAI.balanceOf(borrower.address)).is.equal(1200);
			expect(await DAI.balanceOf(lender.address)).is.equal(0);
			expect(await DAI.balanceOf(PWNVault.address)).is.equal(0);
			expect(await NFT.ownerOf(42)).to.equal(lender.address);
			expect(await PWNDeed.balanceOf(lender.address, did)).to.equal(0);
		});

	});

});
