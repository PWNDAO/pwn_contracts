const chai = require("chai");
const { ethers } = require("hardhat");
const { smock } = require("@defi-wonderland/smock");
const { time } = require('@openzeppelin/test-helpers');
const { CATEGORY, timestampFromNow, getOfferHashBytes, signOffer } = require("./test-helpers");

const expect = chai.expect;
chai.use(smock.matchers);


describe("PWNDeed contract", function() {

	let Deed, deed, deedEventIface;
	let pwn, lender, borrower, asset1, asset2, addr1, addr2, addr3, addr4, addr5;
	let offer, flexibleOffer, flexibleOfferValues, offerHash, signature, loan, collateral;

	const loanAmountMax = 2_000;
	const loanAmountMin = 1_000;
	const durationMax = 100_000;
	const durationMin = 10_000;
	const duration = 100_000;
	const loanYield = 1_000;
	const offerExpiration = 0;
	const nonce = ethers.utils.solidityKeccak256([ "string" ], [ "nonce" ]);

	before(async function() {
		Deed = await ethers.getContractFactory("PWNDeed");
		[pwn, lender, borrower, asset1, asset2, addr1, addr2, addr3, addr4, addr5] = await ethers.getSigners();

		deedEventIface = new ethers.utils.Interface([
			"event DeedCreated(uint256 indexed did, address indexed lender, bytes32 indexed offerHash)",
			"event OfferRevoked(bytes32 indexed offerHash)",
			"event PaidBack(uint256 did)",
			"event DeedClaimed(uint256 did)",
		]);

		loan = {
			assetAddress: asset1.address,
			category: CATEGORY.ERC20,
			amount: 1234,
			id: 0,
		};

		collateral = {
			assetAddress: asset2.address,
			category: CATEGORY.ERC721,
			amount: 10,
			id: 123,
		};
	});

	beforeEach(async function() {
		deed = await Deed.deploy("https://test.uri");
		await deed.setPWN(pwn.address);

		offer = [
			collateral.assetAddress, collateral.category, collateral.amount, collateral.id,
			loan.assetAddress, loan.amount,
			loanYield, duration, offerExpiration, lender.address, nonce,
		];

		flexibleOffer = [
			collateral.assetAddress, collateral.category, collateral.amount, [],
			loan.assetAddress, loanAmountMax, loanAmountMin, loanYield,
			durationMax, durationMin, offerExpiration, lender.address, nonce,
		];

		flexibleOfferValues = [
			collateral.id, loan.amount, duration,
		];

		offerHash = getOfferHashBytes(offer, deed.address);
		signature = await signOffer(offer, deed.address, lender);
	});


	describe("Constructor", function() {

		it("Should set correct owner", async function() {
			const factory = await ethers.getContractFactory("PWNDeed", addr1);

			deed = await factory.deploy("https://test.uri");

			const contractOwner = await deed.owner();
			expect(addr1.address).to.equal(contractOwner, "deed owner should be the deed deployer");
		});

		it("Should set correct uri", async function() {
			const factory = await ethers.getContractFactory("PWNDeed");

			deed = await factory.deploy("xyz123");

			const uri = await deed.uri(1);
			expect(uri).to.equal("xyz123");
		});

	});


	describe("Revoke offer", function() { // -> PWN is trusted source so we believe that it would not send invalid data

		it("Should fail when sender is not PWN contract", async function() {
			await expect(
				deed.connect(addr1).revokeOffer(offerHash, signature, lender.address)
			).to.be.revertedWith("Caller is not the PWN");
		});

		it("Should fail when lender is not the offer signer", async function() {
			await expect(
				deed.revokeOffer(offerHash, signature, borrower.address)
			).to.be.revertedWith("Sender is not an offer signer");
		});

		it("Should fail with invalid signature", async function() {
			const fakeSignature = "0x6732801029378ddf837210000397c68129387fd887839708320980942102910a6732801029378ddf837210000397c68129387fd887839708320980942102910a00";

			await expect(
				deed.revokeOffer(offerHash, fakeSignature, lender.address)
			).to.be.revertedWith("ECDSA: invalid signature");
		});

		it("Should fail if offer is already revoked", async function() {
			await deed.revokeOffer(offerHash, signature, lender.address);

			await expect(
				deed.revokeOffer(offerHash, signature, lender.address)
			).to.be.revertedWith("Offer is already revoked or has been accepted");
		});

		it("Should set offer as revoked", async function() {
			await deed.revokeOffer(offerHash, signature, lender.address);

			const isRevoked = await deed.revokedOffers(offerHash);
			expect(isRevoked).to.equal(true);
		});

		it("Should emit OfferRevoked event", async function() {
			await expect(
				deed.revokeOffer(offerHash, signature, lender.address)
			).to.emit(deed, "OfferRevoked").withArgs(
				ethers.utils.hexValue(offerHash)
			);
		});

	});


	describe("Create", function() { // -> PWN is trusted source so we believe that it would not send invalid data

		it("Should fail when sender is not PWN contract", async function() {
			await expect(
				deed.connect(addr1).create(offer, signature, borrower.address)
			).to.be.revertedWith("Caller is not the PWN");
		});

		it("Should fail when offer lender is not offer signer", async function() {
			offer[9] = addr1.address;

			await expect(
				deed.create(offer, signature, borrower.address)
			).to.be.revertedWith("Lender address didn't sign the offer");
		});

		it("Should pass when offer is signed on behalf of a contract wallet", async function() {
			const fakeContractWallet = await smock.fake("ContractWallet");
			offer[9] = fakeContractWallet.address;
			offerHash = getOfferHashBytes(offer, deed.address);
			signature = await signOffer(offer, deed.address, addr1);
			fakeContractWallet.isValidSignature.whenCalledWith(offerHash, signature).returns("0x1626ba7e");
			fakeContractWallet.onERC1155Received.returns("0xf23a6e61");

			await expect(
				deed.create(offer, signature, borrower.address)
			).to.not.be.reverted;
		});

		it("Should fail when contract wallet returns that offer signed on behalf of a contract wallet is invalid", async function() {
			const fakeContractWallet = await smock.fake("ContractWallet");
			offer[9] = fakeContractWallet.address;
			signature = await signOffer(offer, deed.address, addr1);
			fakeContractWallet.isValidSignature.returns("0xffffffff");
			fakeContractWallet.onERC1155Received.returns("0xf23a6e61");

			await expect(
				deed.create(offer, signature, borrower.address)
			).to.be.revertedWith("Signature on behalf of contract is invalid");
		});

		it("Should fail when given invalid signature", async function() {
			const fakeSignature = "0x6732801029378ddf837210000397c68129387fd887839708320980942102910a6732801029378ddf837210000397c68129387fd887839708320980942102910a00";

			await expect(
				deed.create(offer, fakeSignature, borrower.address)
			).to.be.revertedWith("ECDSA: invalid signature");
		});

		it("Should fail when offer is expired", async function() {
			offer[8] = 1;
			signature = await signOffer(offer, deed.address, lender);

			await expect(
				deed.create(offer, signature, borrower.address)
			).to.be.revertedWith("Offer is expired");
		});

		it("Should pass when offer has expiration but is not expired", async function() {
			const expiration = await timestampFromNow(100);
			offer[8] = expiration;
			signature = await signOffer(offer, deed.address, lender);

			await expect(
				deed.create(offer, signature, borrower.address)
			).to.not.be.reverted;
		});

		it("Should fail when offer is revoked", async function() {
			await deed.revokeOffer(offerHash, signature, lender.address);

			await expect(
				deed.create(offer, signature, borrower.address)
			).to.be.revertedWith("Offer is revoked or has been accepted");
		});

		it("Should revoke accepted offer", async function() {
			await deed.create(offer, signature, borrower.address);

			const isRevoked = await deed.revokedOffers(offerHash);
			expect(isRevoked).to.equal(true);
		});

		it("Should mint deed ERC1155 token", async function () {
			await deed.create(offer, signature, borrower.address);
			const did = await deed.id();

			const balance = await deed.balanceOf(lender.address, did);
			expect(balance).to.equal(1);
		});

		it("Should save deed data", async function () {
			await deed.create(offer, signature, borrower.address);
			const expiration = await timestampFromNow(duration);
			const did = await deed.id();

			const deedToken = await deed.deeds(did);
			expect(deedToken.status).to.equal(2);
			expect(deedToken.borrower).to.equal(borrower.address);
			expect(deedToken.duration).to.equal(duration);
			expect(deedToken.expiration).to.equal(expiration);
			expect(deedToken.collateral.assetAddress).to.equal(collateral.assetAddress);
			expect(deedToken.collateral.category).to.equal(collateral.category);
			expect(deedToken.collateral.id).to.equal(collateral.id);
			expect(deedToken.collateral.amount).to.equal(collateral.amount);
			expect(deedToken.loan.assetAddress).to.equal(loan.assetAddress);
			expect(deedToken.loan.category).to.equal(loan.category);
			expect(deedToken.loan.id).to.equal(loan.id);
			expect(deedToken.loan.amount).to.equal(loan.amount);
			expect(deedToken.loanRepayAmount).to.equal(loan.amount + loanYield);
		});

		it("Should increase global deed ID", async function() {
			await deed.create(offer, signature, borrower.address);
			const did1 = await deed.id();

			offer[10] = ethers.utils.solidityKeccak256([ "string" ], [ "nonce_2" ]);
			signature = await signOffer(offer, deed.address, lender);

			await deed.create(offer, signature, borrower.address);
			const did2 = await deed.id();

			expect(did2).to.equal(did1.add(1));
		});

		it("Should emit DeedCreated event", async function() {
			const did = await deed.id();

			await expect(
				deed.create(offer, signature, borrower.address)
			).to.emit(deed, "DeedCreated").withArgs(
				did + 1, lender.address, ethers.utils.hexValue(offerHash)
			);
		});

	});


	describe("Create flexible", function() { // -> PWN is trusted source so we believe that it would not send invalid data

		beforeEach(async function() {
			offerHash = getOfferHashBytes(flexibleOffer, deed.address);
			signature = await signOffer(flexibleOffer, deed.address, lender);
		});


		it("Should fail when sender is not PWN contract", async function() {
			await expect(
				deed.connect(addr1).createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address)
			).to.be.revertedWith("Caller is not the PWN");
		});

		it("Should fail when offer lender is not offer signer", async function() {
			flexibleOffer[11] = addr1.address;

			await expect(
				deed.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address)
			).to.be.revertedWith("Lender address didn't sign the offer");
		});

		it("Should pass when offer is signed on behalf of a contract wallet", async function() {
			const fakeContractWallet = await smock.fake("ContractWallet");
			flexibleOffer[11] = fakeContractWallet.address;
			offerHash = getOfferHashBytes(flexibleOffer, deed.address);
			signature = await signOffer(flexibleOffer, deed.address, addr1);
			fakeContractWallet.isValidSignature.whenCalledWith(offerHash, signature).returns("0x1626ba7e");
			fakeContractWallet.onERC1155Received.returns("0xf23a6e61");

			await expect(
				deed.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address)
			).to.not.be.reverted;
		});

		it("Should fail when contract wallet returns that offer signed on behalf of a contract wallet is invalid", async function() {
			const fakeContractWallet = await smock.fake("ContractWallet");
			flexibleOffer[11] = fakeContractWallet.address;
			signature = await signOffer(flexibleOffer, deed.address, addr1);
			fakeContractWallet.isValidSignature.returns("0xffffffff");
			fakeContractWallet.onERC1155Received.returns("0xf23a6e61");

			await expect(
				deed.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address)
			).to.be.revertedWith("Signature on behalf of contract is invalid");
		});

		it("Should fail when given invalid signature", async function() {
			const fakeSignature = "0x6732801029378ddf837210000397c68129387fd887839708320980942102910a6732801029378ddf837210000397c68129387fd887839708320980942102910a00";

			await expect(
				deed.createFlexible(flexibleOffer, flexibleOfferValues, fakeSignature, borrower.address)
			).to.be.revertedWith("ECDSA: invalid signature");
		});

		it("Should fail when offer is expired", async function() {
			flexibleOffer[10] = 1;
			signature = await signOffer(flexibleOffer, deed.address, lender);

			await expect(
				deed.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address)
			).to.be.revertedWith("Offer is expired");
		});

		it("Should pass when offer has expiration but is not expired", async function() {
			const expiration = await timestampFromNow(100);
			flexibleOffer[10] = expiration;
			signature = await signOffer(flexibleOffer, deed.address, lender);

			await expect(
				deed.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address)
			).to.not.be.reverted;
		});

		it("Should fail when offer is revoked", async function() {
			await deed.revokeOffer(offerHash, signature, lender.address);

			await expect(
				deed.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address)
			).to.be.revertedWith("Offer is revoked or has been accepted");
		});

		it("Should fail when selected collateral ID is not whitelisted", async function() {
			flexibleOffer[3] = [1, 2, 3];
			signature = await signOffer(flexibleOffer, deed.address, lender);

			await expect(
				deed.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address)
			).to.be.revertedWith("Selected collateral id is not contained in whitelist");
		});

		it("Should pass when selected collateral ID is whitelisted", async function() {
			flexibleOffer[3] = [1, 2, 3, 123, 4, 5, 6];
			signature = await signOffer(flexibleOffer, deed.address, lender);

			await expect(
				deed.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address)
			).to.not.be.reverted;
		});

		it("Should pass with any selected collateral ID when is whitelist empty", async function() {
			flexibleOffer[3] = [];
			signature = await signOffer(flexibleOffer, deed.address, lender);

			await expect(
				deed.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address)
			).to.not.be.reverted;
		});

		it("Should fail when given amount is above offered range", async function() {
			flexibleOfferValues[1] = loanAmountMax + 1;

			await expect(
				deed.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address)
			).to.be.revertedWith("Loan amount is not in offered range");
		});

		it("Should fail when given amount is below offered range", async function() {
			flexibleOfferValues[1] = loanAmountMin - 1;

			await expect(
				deed.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address)
			).to.be.revertedWith("Loan amount is not in offered range");
		});

		it("Should fail when given duration is above offered range", async function() {
			flexibleOfferValues[2] = durationMax + 1;

			await expect(
				deed.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address)
			).to.be.revertedWith("Loan duration is not in offered range");
		});

		it("Should fail when given duration is below offered range", async function() {
			flexibleOfferValues[2] = durationMin - 1;

			await expect(
				deed.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address)
			).to.be.revertedWith("Loan duration is not in offered range");
		});

		it("Should revoke accepted offer", async function() {
			await deed.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address);

			const isRevoked = await deed.revokedOffers(offerHash);
			expect(isRevoked).to.equal(true);
		});

		it("Should mint deed ERC1155 token", async function () {
			await deed.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address);
			const did = await deed.id();

			const balance = await deed.balanceOf(lender.address, did);
			expect(balance).to.equal(1);
		});

		it("Should save deed data", async function () {
			await deed.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address);
			const expiration = await timestampFromNow(duration);
			const did = await deed.id();

			const deedToken = await deed.deeds(did);
			expect(deedToken.status).to.equal(2);
			expect(deedToken.borrower).to.equal(borrower.address);
			expect(deedToken.duration).to.equal(duration);
			expect(deedToken.expiration).to.equal(expiration);
			expect(deedToken.collateral.assetAddress).to.equal(collateral.assetAddress);
			expect(deedToken.collateral.category).to.equal(collateral.category);
			expect(deedToken.collateral.id).to.equal(collateral.id);
			expect(deedToken.collateral.amount).to.equal(collateral.amount);
			expect(deedToken.loan.assetAddress).to.equal(loan.assetAddress);
			expect(deedToken.loan.category).to.equal(loan.category);
			expect(deedToken.loan.id).to.equal(loan.id);
			expect(deedToken.loan.amount).to.equal(loan.amount);
			expect(deedToken.loanRepayAmount).to.equal(loan.amount + loanYield);
		});

		// Waiting on smock to fix mocking functions calls on a same contract
		// https://github.com/defi-wonderland/smock/issues/109
		xit("Should call `countLoanRepayAmount` for loan repay amount value", async function() {
			const deedMockFactory = await smock.mock("PWNDeed");
			const deedMock = await deedMockFactory.deploy("https://test.uri");
			await deedMock.setPWN(pwn.address);
			deedMock.countLoanRepayAmount.returns(1);
			signature = await signOffer(flexibleOffer, deedMock.address, lender);

			await deedMock.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address);

			const did = await deedMock.id();
			const deedToken = await deedMock.deeds(did);
			expect(deedToken.loanRepayAmount).to.equal(1);
			expect(deedMock.countLoanRepayAmount).to.have.been.calledOnce;
		});

		it("Should increase global deed ID", async function() {
			await deed.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address);
			const did1 = await deed.id();

			flexibleOffer[12] = ethers.utils.solidityKeccak256([ "string" ], [ "nonce_2" ]);
			signature = await signOffer(flexibleOffer, deed.address, lender);

			await deed.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address);
			const did2 = await deed.id();

			expect(did2).to.equal(did1.add(1));
		});

		it("Should emit DeedCreated event", async function() {
			const did = await deed.id();

			await expect(
				deed.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address)
			).to.emit(deed, "DeedCreated").withArgs(
				did + 1, lender.address, ethers.utils.hexValue(offerHash)
			);
		});

	});


	describe("Repay loan", function() {

		let did;

		beforeEach(async function() {
			await deed.create(offer, signature, borrower.address);
			did = await deed.id();
		});


		it("Should fail when sender is not PWN contract", async function() {
			await expect(
				deed.connect(addr1).repayLoan(did)
			).to.be.revertedWith("Caller is not the PWN");
		});

		it("Should fail when deed is not in running state", async function() {
			const deedMockFactory = await smock.mock("PWNDeed");
			const deedMock = await deedMockFactory.deploy("https://test.uri");
			await deedMock.setPWN(pwn.address);
			await deedMock.setVariable("deeds", {
				1: {
					status: 3
				}
			});

			await expect(
				deedMock.repayLoan(did)
			).to.be.revertedWith("Deed is not running and cannot be paid back");
		});

		it("Should update deed to paid back state", async function() {
			await deed.repayLoan(did);

			const status = (await deed.deeds(did)).status;
			expect(status).to.equal(3);
		});

		it("Should emit PaidBack event", async function() {
			await expect(
				deed.repayLoan(did)
			).to.emit(deed, "PaidBack").withArgs(
				did
			);
		});

	});


	describe("Claim", function() {

		let deedMockFactory, deedMock;
		let did;

		before(async function() {
			deedMockFactory = await smock.mock("PWNDeed");
		});

		beforeEach(async function() {
			deedMock = await deedMockFactory.deploy("https://test.uri");
			await deedMock.setPWN(pwn.address);

			offerHash = getOfferHashBytes(offer, deedMock.address);
			signature = await signOffer(offer, deedMock.address, lender);

			await deedMock.create(offer, signature, borrower.address);
			did = await deedMock.id();
		});


		it("Should fail when sender is not PWN contract", async function() {
			await expect(
				deedMock.connect(addr1).claim(did, lender.address)
			).to.be.revertedWith("Caller is not the PWN");
		});

		it("Should fail when sender is not deed owner", async function() {
			await expect(
				deedMock.claim(did, addr4.address)
			).to.be.revertedWith("Caller is not the deed owner");
		});

		it("Should fail when deed is not in paid back nor expired state", async function() {
			await deedMock.setVariable("deeds", {
				1: {
					status: 2
				}
			});

			await expect(
				deedMock.claim(did, lender.address)
			).to.be.revertedWith("Deed can't be claimed yet");
		});

		it("Should be possible to claim expired deed", async function() {
			await deedMock.setVariable("deeds", {
				1: {
					status: 4
				}
			});

			await deedMock.claim(did, lender.address);

			expect(true);
		});

		it("Should be possible to claim paid back deed", async function() {
			await deedMock.setVariable("deeds", {
				1: {
					status: 3
				}
			});

			await deedMock.claim(did, lender.address);

			expect(true);
		});

		it("Should update deed to dead state", async function() {
			await deedMock.repayLoan(did);

			await deedMock.claim(did, lender.address);

			const status = (await deedMock.deeds(did)).status;
			expect(status).to.equal(0);
		});

		it("Should emit DeedClaimed event", async function() {
			await deedMock.repayLoan(did);

			await expect(
				deedMock.claim(did, lender.address)
			).to.emit(deedMock, "DeedClaimed").withArgs(
				did
			);
		});

	});


	describe("Burn", function() { // -> PWN is trusted source so we believe that it would not send invalid data

		let deedMockFactory, deedMock;
		let did;

		before(async function() {
			deedMockFactory = await smock.mock("PWNDeed");
		});

		beforeEach(async function() {
			deedMock = await deedMockFactory.deploy("https://test.uri");
			await deedMock.setPWN(pwn.address);

			offerHash = getOfferHashBytes(offer, deedMock.address);
			signature = await signOffer(offer, deedMock.address, lender);

			await deedMock.create(offer, signature, borrower.address);
			did = await deedMock.id();
		});


		it("Should fail when sender is not PWN contract", async function() {
			await expect(
				deedMock.connect(addr1).burn(did, lender.address)
			).to.be.revertedWith("Caller is not the PWN");
		});

		it("Should fail when passing address is not deed owner", async function() {
			await expect(
				deedMock.burn(did, addr4.address)
			).to.be.revertedWith("Caller is not the deed owner");
		});

		it("Should fail when deed is not in dead state", async function() {
			await deedMock.setVariable("deeds", {
				1: {
					status: 2
				}
			});

			await expect(
				deedMock.burn(did, lender.address)
			).to.be.revertedWith("Deed can't be burned at this stage");
		});

		it("Should delete deed data", async function() {
			await deedMock.setVariable("deeds", {
				1: {
					status: 0
				}
			});

			await deedMock.burn(did, lender.address);

			const deedToken = await deedMock.deeds(did);
			expect(deedToken.expiration).to.equal(0);
			expect(deedToken.duration).to.equal(0);
			expect(deedToken.borrower).to.equal(ethers.constants.AddressZero);
			expect(deedToken.collateral.assetAddress).to.equal(ethers.constants.AddressZero);
			expect(deedToken.collateral.category).to.equal(0);
			expect(deedToken.collateral.id).to.equal(0);
			expect(deedToken.collateral.amount).to.equal(0);
		});

		it("Should burn deed ERC1155 token", async function() {
			await deedMock.setVariable("deeds", {
				1: {
					status: 0
				}
			});

			await deedMock.burn(did, lender.address);

			const balance = await deedMock.balanceOf(lender.address, did);
			expect(balance).to.equal(0);
		});

	});


	describe("Count loan repay amount", function() {

		// durationMax: 100,000
		// durationMin: 10,000
		// loanYield: 1_000 (max yield)

		const durations = [ 100_000, 99_999, 90_000, 83_102, 50_000, 47_773, 33_333, 10_001, 10_000 ];

		durations.forEach((duration) => {

			it(`Should count correct loan repay amount for duration ${duration}`, async function() {
				const loanRepayAmount = await deed.countLoanRepayAmount(loan.amount, duration, loanYield, durationMax);

				expect(loanRepayAmount).to.equal(loan.amount + Math.floor(loanYield * duration / durationMax));
			});

		});

	});


	describe("View functions", function() {

		let deedMockFactory, deedMock;
		const did = 1;

		before(async function() {
			deedMockFactory = await smock.mock("PWNDeed");
		});

		beforeEach(async function() {
			deedMock = await deedMockFactory.deploy("https://test.uri");
			await deedMock.setPWN(pwn.address);
		});


		// VIEW FUNCTIONS - DEEDS

		describe("Get deed status", function() {

			it("Should return none/dead state", async function() {
				await deedMock.setVariable("deeds", {
					1: {
						status: 0
					}
				});

				const status = await deedMock.getStatus(did);

				expect(status).to.equal(0);
			});

			it("Should return running state when not expired", async function() {
				await deedMock.setVariable("deeds", {
					1: {
						status: 2,
						expiration: await timestampFromNow(100)
					}
				});

				const status = await deedMock.getStatus(did);

				expect(status).to.equal(2);
			});

			it("Should return expired state when in running state", async function() {
				await deedMock.setVariable("deeds", {
					1: {
						status: 2,
						expiration: 1
					}
				});

				const status = await deedMock.getStatus(did);

				expect(status).to.equal(4);
			});

			it("Should return paid back state when not expired", async function() {
				await deedMock.setVariable("deeds", {
					1: {
						status: 3,
						expiration: await timestampFromNow(100)
					}
				});

				const status = await deedMock.getStatus(did);

				expect(status).to.equal(3);
			});

			it("Should return paid back state when expired", async function() {
				await deedMock.setVariable("deeds", {
					1: {
						status: 3,
						expiration: 1
					}
				});

				const status = await deedMock.getStatus(did);

				expect(status).to.equal(3);
			});

		});


		describe("Get expiration", function() {

			it("Should return deed expiration", async function() {
				await deedMock.setVariable("deeds", {
					1: {
						expiration: 3123
					}
				});

				const expiration = await deedMock.getExpiration(did);

				expect(expiration).to.equal(3123);
			});

		});

		describe("Get duration", function() {

			it("Should return deed duration", async function() {
				await deedMock.setVariable("deeds", {
					1: {
						duration: 1111
					}
				});

				const deedDuration = await deedMock.getDuration(did);

				expect(deedDuration).to.equal(1111);
			});

		});


		describe("Get borrower", function() {

			it("Should return deed borrower address", async function() {
				await deedMock.setVariable("deeds", {
					1: {
						borrower: borrower.address
					}
				});

				const borrowerAddress = await deedMock.getBorrower(did);

				expect(borrowerAddress).to.equal(borrower.address);
			});

		});


		describe("Get collateral asset", function() {

			// Smock doesn't support updating enums in storage
			xit("Should return deed collateral asset", async function() {
				await deedMock.setVariable("deeds", {
					1: {
						collateral: {
							assetAddress: asset1.address,
							category: 1,
							amount: 123123,
							id: 9537
						}
					}
				});

				const collateral = await deedMock.getCollateral(did);

				expect(collateral.assetAddress).to.equal(asset1.address);
				expect(collateral.category).to.equal(1);
				expect(collateral.amount).to.equal(123123);
				expect(collateral.id).to.equal(9537);
			});

		});


		describe("Get loan asset", function() {

			// Smock doesn't support updating enums in storage
			xit("Should return deed loan asset", async function() {
				await deedMock.setVariable("deeds", {
					1: {
						loan: {
							assetAddress: asset2.address,
							category: 0,
							amount: 8838,
							id: 0
						}
					}
				});

				const loan = await deedMock.getLoan(did);

				expect(loan.assetAddress).to.equal(asset2.address);
				expect(loan.category).to.equal(0);
				expect(loan.amount).to.equal(8838);
				expect(loan.id).to.equal(0);
			});

		});


		describe("Get loan repay amount", function() {

			it("Should return deed loan repay amount", async function() {
				await deedMock.setVariable("deeds", {
					1: {
						loanRepayAmount: 88393993
					}
				});

				const loanRepayAmount = await deedMock.getLoanRepayAmount(did);

				expect(loanRepayAmount).to.equal(88393993);
			});

		});


		describe("Is offer revoked", function() {

			it("Should return true if offer is revoked", async function() {
				await deedMock.setVariable("revokedOffers", {
					"1d9c0a4fa5589519086c908b1a5f492d770c0fd4208dd36e9a84f5b2dab97ad9": true
				});

				const isRevoked = await deedMock.isRevoked("0x1d9c0a4fa5589519086c908b1a5f492d770c0fd4208dd36e9a84f5b2dab97ad9");

				expect(isRevoked).to.equal(true);
			});

		});

	});


	describe("Set PWN", function() {

		it("Should fail when sender is not owner", async function() {
			await expect(
				deed.connect(addr1).setPWN(addr2.address)
			).to.be.revertedWith("Ownable: caller is not the owner");
		});

		it("Should set PWN address", async function() {
			const formerPWN = await deed.PWN();

			await deed.connect(pwn).setPWN(addr1.address);

			const latterPWN = await deed.PWN();
			expect(formerPWN).to.not.equal(latterPWN);
			expect(latterPWN).to.equal(addr1.address);
		});

	});

	describe("Set new URI", function() {

		it("Should fail when sender is not owner", async function() {
			await expect(
				deed.connect(addr1).setUri("https://new.uri.com/deed/{id}")
			).to.be.revertedWith("Ownable: caller is not the owner");
		});

		it("Should set a new URI", async function() {
			const formerURI = await deed.uri(1);

			await deed.connect(pwn).setUri("https://new.uri.com/deed/{id}");

			const latterURI = await deed.uri(1);
			expect(formerURI).to.not.equal(latterURI);
			expect(latterURI).to.equal("https://new.uri.com/deed/{id}");
		});

	});
});
