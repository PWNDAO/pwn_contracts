const { expect } = require("chai");
const { time } = require('@openzeppelin/test-helpers');
const { CATEGORY, getOfferHashBytes, signOffer } = require("./test-helpers");


describe("PWN", function () {

	let ERC20, ERC721, ERC1155;
	let NFT, WETH, DAI, GAME;
	let PWN, PWNLoan, PWNVault, ContractWallet;
	let borrower, lender, contractOwner;
	let addr1, addr2, addrs;

	const loanEventIface = new ethers.utils.Interface([
		"event LoanCreated(uint256 indexed loanId, address indexed lender, bytes32 indexed offerHash)",
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
		PWNLoan = await ethers.getContractFactory("PWNLoan");
		PWNVault = await ethers.getContractFactory("PWNVault");
		ContractWallet = await ethers.getContractFactory("ContractWallet");

		[borrower, lender, contractOwner, addr1, addr2, ...addrs] = await ethers.getSigners();

		WETH = await ERC20.deploy("Fake wETH", "WETH");
		DAI = await ERC20.deploy("Fake Dai", "DAI");
		NFT = await ERC721.deploy("Real NFT", "NFT");
		GAME = await ERC1155.deploy("https://pwn.finance/game/")

		PWNLoan = await PWNLoan.deploy("https://pwn.finance/");
		PWNVault = await PWNVault.deploy();
		PWN = await PWN.deploy(PWNLoan.address, PWNVault.address);
		ContractWallet = await ContractWallet.connect(contractOwner).deploy();

		await NFT.deployed();
		await DAI.deployed();
		await GAME.deployed();
		await PWNLoan.deployed();
		await PWNVault.deployed();
		await PWN.deployed();

		await PWNLoan.setPWN(PWN.address);
		await PWNVault.setPWN(PWN.address);

		await DAI.mint(lender.address, lInitialDAI);
		await DAI.mint(ContractWallet.address, lInitialDAI);
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
	});


	describe("Deployment", function () {

		it("Should deploy PWN with links to Loan & Vault", async function () {
			expect(await PWN.loan()).to.equal(PWNLoan.address);
			expect(await PWN.vault()).to.equal(PWNVault.address);
		});

		it("Should deploy Vault with a link to PWN", async function () {
			expect(await PWNVault.PWN()).to.equal(PWN.address);
		});

		it("Should deploy Loan with a link to PWN", async function () {
			expect(await PWNLoan.PWN()).to.equal(PWN.address);
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
			const offer = [
				NFT.address, CATEGORY.ERC721, 0, 42,
				DAI.address, 1000, 200,
				3600, 0, lender.address, nonce,
			];
			const offerHash = getOfferHashBytes(offer, PWNLoan.address);
			const signature = await signOffer(offer, PWNLoan.address, lender);

			await lPWN.revokeOffer(offerHash, signature);

			const isRevoked = await PWNLoan.isRevoked(offerHash);
			expect(isRevoked).to.equal(true);
		});

		it("Should be possible to revoke an offer on behalf of contract wallet", async function() {
			const offer = [
				NFT.address, CATEGORY.ERC721, 0, 42,
				DAI.address, 1000, 200,
				3600, 0, lender.address, nonce,
			];
			const offerHash = getOfferHashBytes(offer, PWNLoan.address);
			const signature = await signOffer(offer, PWNLoan.address, contractOwner);

			await PWN.connect(contractOwner).revokeOffer(offerHash, signature);

			const isRevoked = await PWNLoan.isRevoked(offerHash);
			expect(isRevoked).to.equal(true);
		});

	});


	describe("Workflow - New loans with arbitrary collateral", function () {

		it("Should be possible to create a loan with ERC20 collateral with simple offer", async function () {
			const offer = [
				WETH.address, CATEGORY.ERC20, 100, 0,
				DAI.address, 1000, 200,
				3600, 0, lender.address, nonce,
			];
			const signature = await signOffer(offer, PWNLoan.address, lender);
			await lDAI.approve(PWNVault.address, 1000);

			await bWETH.approve(PWNVault.address, 200);
			const tx = await bPWN.createLoan(offer, signature);
			const response = await tx.wait();
			const logDescription = loanEventIface.parseLog(response.logs[1]);
			const loanId = logDescription.args.loanId.toNumber();

			expect(await PWNLoan.balanceOf(lender.address, loanId)).to.equal(1);
			expect(await WETH.balanceOf(PWNVault.address)).to.equal(bInitialWETH);
			expect(await DAI.balanceOf(borrower.address)).to.equal(bInitialDAI + 1000);
		});

		it("Should be possible to create a loan with ERC20 collateral with flexible offer", async function () {
			const offer = [
				WETH.address, CATEGORY.ERC20, 100, [],
				DAI.address, 1000, 800, 200,
				3600, 3000, 0, lender.address, nonce,
			];
			const offerValues = [
				0, 900, 3300
			];
			const signature = await signOffer(offer, PWNLoan.address, lender);
			await lDAI.approve(PWNVault.address, 1000);

			await bWETH.approve(PWNVault.address, 100);
			const tx = await bPWN.createLoanFlexible(offer, offerValues, signature);
			const response = await tx.wait();
			const logDescription = loanEventIface.parseLog(response.logs[1]);
			const loanId = logDescription.args.loanId.toNumber();

			expect(await PWNLoan.balanceOf(lender.address, loanId)).to.equal(1);
			expect(await WETH.balanceOf(PWNVault.address)).to.equal(100);
			expect(await DAI.balanceOf(borrower.address)).to.equal(bInitialDAI + 900);
		});

		it("Should be possible to create a loan with ERC721 collateral with simple offer", async function () {
			const offer = [
				NFT.address, CATEGORY.ERC721, 0, 42,
				DAI.address, 1000, 200,
				3600, 0, lender.address, nonce,
			];
			const signature = await signOffer(offer, PWNLoan.address, lender);
			await lDAI.approve(PWNVault.address, 1000);

			await bNFT.approve(PWNVault.address, 42);
			const tx = await bPWN.createLoan(offer, signature);
			const response = await tx.wait();
			const logDescription = loanEventIface.parseLog(response.logs[1]);
			const loanId = logDescription.args.loanId.toNumber();

			expect(await PWNLoan.balanceOf(lender.address, loanId)).to.equal(1);
			expect(await NFT.ownerOf(42)).to.equal(PWNVault.address);
			expect(await DAI.balanceOf(borrower.address)).to.equal(bInitialDAI + 1000);
		});

		it("Should be possible to create a loan with ERC721 collateral with flexible offer", async function () {
			const offer = [
				NFT.address, CATEGORY.ERC721, 0, [42],
				DAI.address, 1000, 800, 200,
				3600, 3000, 0, lender.address, nonce,
			];
			const offerValues = [
				42, 900, 3300
			];
			const signature = await signOffer(offer, PWNLoan.address, lender);
			await lDAI.approve(PWNVault.address, 1000);

			await bNFT.approve(PWNVault.address, 42);
			const tx = await bPWN.createLoanFlexible(offer, offerValues, signature);
			const response = await tx.wait();
			const logDescription = loanEventIface.parseLog(response.logs[1]);
			const loanId = logDescription.args.loanId.toNumber();

			expect(await PWNLoan.balanceOf(lender.address, loanId)).to.equal(1);
			expect(await NFT.ownerOf(42)).to.equal(PWNVault.address);
			expect(await DAI.balanceOf(borrower.address)).to.equal(bInitialDAI + 900);
		});

		it("Should be possible to create a loan with ERC721 collateral with flexible collection offer", async function () {
			const offer = [
				NFT.address, CATEGORY.ERC721, 0, [],
				DAI.address, 1000, 800, 200,
				3600, 3000, 0, lender.address, nonce,
			];
			const offerValues = [
				42, 900, 3300
			];
			const signature = await signOffer(offer, PWNLoan.address, lender);
			await lDAI.approve(PWNVault.address, 1000);

			await bNFT.approve(PWNVault.address, 42);
			const tx = await bPWN.createLoanFlexible(offer, offerValues, signature);
			const response = await tx.wait();
			const logDescription = loanEventIface.parseLog(response.logs[1]);
			const loanId = logDescription.args.loanId.toNumber();

			expect(await PWNLoan.balanceOf(lender.address, loanId)).to.equal(1);
			expect(await NFT.ownerOf(42)).to.equal(PWNVault.address);
			expect(await DAI.balanceOf(borrower.address)).to.equal(bInitialDAI + 900);
		});

		it("Should be possible to create a loan with ERC1155 collateral with simple offer", async function () {
			const offer = [
				GAME.address, CATEGORY.ERC1155, 1, 1337,
				DAI.address, 1000, 200,
				3600, 0, lender.address, nonce,
			];
			const signature = await signOffer(offer, PWNLoan.address, lender);
			await lDAI.approve(PWNVault.address, 1000);

			await bGAME.setApprovalForAll(PWNVault.address, true);
			const tx = await bPWN.createLoan(offer, signature);
			const response = await tx.wait();
			const logDescription = loanEventIface.parseLog(response.logs[1]);
			const loanId = logDescription.args.loanId.toNumber();

			expect(await PWNLoan.balanceOf(lender.address, loanId)).to.equal(1);
			expect(await GAME.balanceOf(borrower.address, 1337)).to.equal(0);
			expect(await GAME.balanceOf(PWNVault.address, 1337)).to.equal(1);
			expect(await DAI.balanceOf(borrower.address)).to.equal(bInitialDAI + 1000);
		});

		it("Should be possible to create a loan with ERC1155 collateral with flexible offer", async function () {
			const offer = [
				GAME.address, CATEGORY.ERC1155, 1, [1337],
				DAI.address, 1000, 800, 200,
				3600, 3000, 0, lender.address, nonce,
			];
			const offerValues = [
				1337, 900, 3300
			];
			const signature = await signOffer(offer, PWNLoan.address, lender);
			await lDAI.approve(PWNVault.address, 1000);

			await bGAME.setApprovalForAll(PWNVault.address, true);
			const tx = await bPWN.createLoanFlexible(offer, offerValues, signature);
			const response = await tx.wait();
			const logDescription = loanEventIface.parseLog(response.logs[1]);
			const loanId = logDescription.args.loanId.toNumber();

			expect(await PWNLoan.balanceOf(lender.address, loanId)).to.equal(1);
			expect(await GAME.balanceOf(borrower.address, 1337)).to.equal(0);
			expect(await GAME.balanceOf(PWNVault.address, 1337)).to.equal(1);
			expect(await DAI.balanceOf(borrower.address)).to.equal(bInitialDAI + 900);
		});

		it("Should be possible to create a loan with simple offer signed on behalf of a contract wallet", async function() {
			const offer = [
				NFT.address, CATEGORY.ERC721, 0, 42,
				DAI.address, 1000, 200,
				3600, 0, ContractWallet.address, nonce,
			];
			const signature = await signOffer(offer, PWNLoan.address, contractOwner);
			await ContractWallet.approve(DAI.address, PWNVault.address, 1000);

			await bNFT.approve(PWNVault.address, 42);
			const tx = await bPWN.createLoan(offer, signature);
			const response = await tx.wait();
			const logDescription = loanEventIface.parseLog(response.logs[1]);
			const loanId = logDescription.args.loanId.toNumber();

			expect(await PWNLoan.balanceOf(ContractWallet.address, loanId)).to.equal(1);
			expect(await NFT.ownerOf(42)).to.equal(PWNVault.address);
			expect(await DAI.balanceOf(borrower.address)).to.equal(bInitialDAI + 1000);
		});

		it("Should be possible to create a loan with flexible offer signed on behalf of a contract wallet", async function() {
			const offer = [
				NFT.address, CATEGORY.ERC721, 0, [42],
				DAI.address, 1000, 800, 200,
				3600, 3000, 0, ContractWallet.address, nonce,
			];
			const offerValues = [
				42, 900, 3300
			];
			const signature = await signOffer(offer, PWNLoan.address, contractOwner);
			await ContractWallet.approve(DAI.address, PWNVault.address, 1000);

			await bNFT.approve(PWNVault.address, 42);
			const tx = await bPWN.createLoanFlexible(offer, offerValues, signature);
			const response = await tx.wait();
			const logDescription = loanEventIface.parseLog(response.logs[1]);
			const loanId = logDescription.args.loanId.toNumber();

			expect(await PWNLoan.balanceOf(ContractWallet.address, loanId)).to.equal(1);
			expect(await NFT.ownerOf(42)).to.equal(PWNVault.address);
			expect(await DAI.balanceOf(borrower.address)).to.equal(bInitialDAI + 900);
		});

	});


	describe("Workflow - Settlement", function () {

		it("Should be possible to pay back", async function () {
			const offer = [
				NFT.address, CATEGORY.ERC721, 0, 42,
				DAI.address, 1000, 200,
				3600, 0, lender.address, nonce,
			];
			const signature = await signOffer(offer, PWNLoan.address, lender);
			await lDAI.approve(PWNVault.address, 1000);

			await bNFT.approve(PWNVault.address, 42);
			const tx = await bPWN.createLoan(offer, signature);
			const response = await tx.wait();
			const logDescription = loanEventIface.parseLog(response.logs[1]);
			const loanId = logDescription.args.loanId.toNumber();

			await bDAI.approve(PWNVault.address, 1200);
			await bPWN.repayLoan(loanId);

			expect(await DAI.balanceOf(borrower.address)).is.equal(0);
			expect(await DAI.balanceOf(lender.address)).is.equal(0);
			expect(await DAI.balanceOf(PWNVault.address)).is.equal(1200);
			expect(await NFT.ownerOf(42)).to.equal(borrower.address);
		});

		it("Should be possible to claim after loan was paid", async function () {
			const offer = [
				NFT.address, CATEGORY.ERC721, 0, 42,
				DAI.address, 1000, 200,
				3600, 0, lender.address, nonce,
			];
			const signature = await signOffer(offer, PWNLoan.address, lender);
			await lDAI.approve(PWNVault.address, 1000);

			await bNFT.approve(PWNVault.address, 42);
			const tx = await bPWN.createLoan(offer, signature);
			const response = await tx.wait();
			const logDescription = loanEventIface.parseLog(response.logs[1]);
			const loanId = logDescription.args.loanId.toNumber();

			await bDAI.approve(PWNVault.address, 1200);
			await bPWN.repayLoan(loanId);

			await lPWN.claimLoan(loanId);

			expect(await DAI.balanceOf(borrower.address)).is.equal(0);
			expect(await DAI.balanceOf(lender.address)).is.equal(1200);
			expect(await DAI.balanceOf(PWNVault.address)).is.equal(0);
			expect(await NFT.ownerOf(42)).to.equal(borrower.address);
			expect(await PWNLoan.balanceOf(lender.address, loanId)).to.equal(0);
		});

		it("Should be possible to claim if loan wasn't paid", async function () {
			const offer = [
				NFT.address, CATEGORY.ERC721, 0, 42,
				DAI.address, 1000, 200,
				3600, 0, lender.address, nonce,
			];
			const signature = await signOffer(offer, PWNLoan.address, lender);
			await lDAI.approve(PWNVault.address, 1000);

			await bNFT.approve(PWNVault.address, 42);
			const tx = await bPWN.createLoan(offer, signature);
			const response = await tx.wait();
			const logDescription = loanEventIface.parseLog(response.logs[1]);
			const loanId = logDescription.args.loanId.toNumber();

			await ethers.provider.send("evm_increaseTime", [parseInt(time.duration.days(7)) + 2000]);
			await ethers.provider.send("evm_mine");

			await lPWN.claimLoan(loanId);

			expect(await DAI.balanceOf(borrower.address)).is.equal(1200);
			expect(await DAI.balanceOf(lender.address)).is.equal(0);
			expect(await DAI.balanceOf(PWNVault.address)).is.equal(0);
			expect(await NFT.ownerOf(42)).to.equal(lender.address);
			expect(await PWNLoan.balanceOf(lender.address, loanId)).to.equal(0);
		});

	});

});
