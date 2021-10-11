const chai = require("chai");
const { ethers } = require("hardhat");
const { smock } = require("@defi-wonderland/smock");
const { time } = require('@openzeppelin/test-helpers');

const expect = chai.expect;
chai.use(smock.matchers);

describe("PWNDeed contract", function() {

	let deed;

	let Deed;
	let deedEventIface
	let pwn, lender, borrower, asset1, asset2, addr1, addr2, addr3, addr4, addr5;

	async function timestampFromNow(delta) {
		const lastBlockNumber = await ethers.provider.getBlockNumber();
		const lastBlock = await ethers.provider.getBlock(lastBlockNumber);
		return lastBlock.timestamp + delta;
	}

	const CATEGORY = {
		ERC20: 0,
		ERC721: 1,
		ERC1155: 2,
		unknown: 3,
	};

	before(async function() {
		Deed = await ethers.getContractFactory("PWNDeed");
		[pwn, lender, borrower, asset1, asset2, addr1, addr2, addr3, addr4, addr5] = await ethers.getSigners();

		deedEventIface = new ethers.utils.Interface([
			"event DeedCreated(address indexed assetAddress, uint8 category, uint256 id, uint256 amount, uint32 duration, uint256 indexed did)",
			"event OfferMade(address assetAddress, uint256 amount, address indexed lender, uint256 toBePaid, uint256 indexed did, bytes32 offer)",
			"event DeedRevoked(uint256 did)",
			"event OfferRevoked(bytes32 offer)",
			"event OfferAccepted(uint256 did, bytes32 offer)",
			"event PaidBack(uint256 did, bytes32 offer)",
			"event DeedClaimed(uint256 did)",
		]);
	});

	beforeEach(async function() {
		deed = await Deed.deploy("https://test.uri");
		await deed.setPWN(pwn.address);
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


	describe("Create", function() { // -> PWN is trusted source so we believe that it would not send invalid data

		it("Should fail when sender is not PWN contract", async function() {
			try {
				await deed.connect(addr1).create(asset1.address, CATEGORY.ERC20, 0, 0, 0, borrower.address);

				expect().fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Caller is not the PWN");
			}
		});

		it("Should mint deed ERC1155 token", async function () {
			await deed.create(asset1.address, CATEGORY.ERC20, 3600, 1, 100, borrower.address);
			const did = await deed.id();

			const balance = await deed.balanceOf(borrower.address, did);
			expect(balance).to.equal(1);
		});

		it("Should save deed data", async function () {
			const assetId = 1;
			const amount = 100;
			const duration = 3600;

			await deed.create(asset1.address, CATEGORY.ERC20, duration, assetId, amount, borrower.address);
			const did = await deed.id();

			const deedToken = await deed.deeds(did);
			expect(deedToken.status).to.equal(1);
			expect(deedToken.duration).to.equal(duration);
			expect(deedToken.expiration).to.equal(0);
			expect(deedToken.borrower).to.equal(borrower.address);
			expect(deedToken.collateral.assetAddress).to.equal(asset1.address);
			expect(deedToken.collateral.category).to.equal(CATEGORY.ERC20);
			expect(deedToken.collateral.id).to.equal(assetId);
			expect(deedToken.collateral.amount).to.equal(amount);
		});

		it("Should return minted deed ID", async function() {
			const did = await deed.callStatic.create(asset1.address, CATEGORY.ERC20, 3600, 1, 100, borrower.address);

			expect(ethers.BigNumber.isBigNumber(did)).to.equal(true);
		});

		it("Should increase global deed ID", async function() {
			await deed.create(asset1.address, CATEGORY.ERC20, 3600, 1, 100, borrower.address);
			const did1 = await deed.id();

			await deed.create(asset1.address, CATEGORY.ERC20, 3600, 1, 100, borrower.address);
			const did2 = await deed.id();

			expect(did2).to.equal(did1.add(1));
		});

		it("Should emit DeedCreated event", async function() {
			const assetId = 1;
			const amount = 10;
			const duration = 3600;

			const did = await deed.callStatic.create(asset1.address, CATEGORY.ERC20, duration, 1, amount, borrower.address);
			const tx = await deed.create(asset1.address, CATEGORY.ERC20, duration, 1, amount, borrower.address);
			const response = await tx.wait();

			expect(response.logs.length).to.equal(2);
			const logDescription = deedEventIface.parseLog(response.logs[1]);
			expect(logDescription.name).to.equal("DeedCreated");
			expect(logDescription.args.assetAddress).to.equal(asset1.address);
			expect(logDescription.args.category).to.equal(CATEGORY.ERC20);
			expect(logDescription.args.id).to.equal(assetId);
			expect(logDescription.args.amount).to.equal(amount);
			expect(logDescription.args.duration).to.equal(duration);
			expect(logDescription.args.did).to.equal(did);
		});

	});


	describe("Revoke", function() {

		let did;

		beforeEach(async function() {
			await deed.create(asset1.address, CATEGORY.ERC20, 3600, 1, 100, borrower.address);
			did = await deed.id();
		});


		it("Shuold fail when sender is not PWN contract", async function() {
			try {
				await deed.connect(addr1).revoke(did, borrower.address);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Caller is not the PWN");
			}
		});

		it("Should fail when passing address is not deed owner", async function() {
			try {
				await deed.revoke(did, addr2.address);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("The deed doesn't belong to the caller");
			}
		});

		it("Should fail when deed is not in new/open state", async function() {
			// TODO: Would be nice to create smock and set variable directly.
			await deed.revoke(did, borrower.address);

			try {
				await deed.revoke(did, borrower.address);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Deed can't be revoked at this stage");
			}
		});

		it("Should update deed to dead state", async function() {
			await deed.revoke(did, borrower.address);

			const status = (await deed.deeds(did)).status
			expect(status).to.equal(0);
		});

		it("Should emit DeedRevoked event", async function() {
			const tx = await deed.revoke(did, borrower.address);
			const response = await tx.wait();

			expect(response.logs.length).to.equal(1);
			const logDescription = deedEventIface.parseLog(response.logs[0]);
			expect(logDescription.name).to.equal("DeedRevoked");
			expect(logDescription.args.did).to.equal(did);
		});

	});


	describe("Make offer", function() { // -> PWN is trusted source so we believe that it would not send invalid data

		let did;

		const makeOfferHash = function(address, nonce) {
			return ethers.utils.solidityKeccak256(["address", "uint256"], [address, nonce]);
		};

		beforeEach(async function() {
			await deed.create(asset1.address, CATEGORY.ERC20, 3600, 1, 100, borrower.address);
			did = await deed.id();
		});


		it("Should fail when sender is not PWN contract", async function() {
			try {
				await deed.connect(addr1).makeOffer(asset2.address, 100, lender.address, did, 70);

				expect().fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Caller is not the PWN");
			}
		});

		it("Should fail when deed is not in new/open state", async function() {
			await deed.revoke(did, borrower.address);

			try {
				await deed.makeOffer(asset2.address, 100, lender.address, did, 70);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Deed not accepting offers");
			}
		});

		it("Should save offer data", async function() {
			const amount = 100;
			const toBePaid = 70;

			await deed.makeOffer(asset2.address, amount, lender.address, did, toBePaid);

			const pendingOffers = await deed.getOffers(did);
			const offerHash = pendingOffers[0];
			const offer = await deed.offers(offerHash);
			expect(offer.credit.assetAddress).to.equal(asset2.address);
			expect(offer.credit.category).to.equal(CATEGORY.ERC20);
			expect(offer.credit.amount).to.equal(amount);
			expect(offer.lender).to.equal(lender.address);
			expect(offer.did).to.equal(did);
			expect(offer.toBePaid).to.equal(toBePaid);
		});

		it("Should set offer to deed", async function() {
			await deed.makeOffer(asset2.address, 100, lender.address, did, 70);

			// Cannot get pendingOffers from deed.pendingOffers because `solc` generates incorrect ABI for implicit property getters with dynamic array
			// GH issue: https://github.com/ethereum/solidity/issues/4244
			const pendingOffers = await deed.getOffers(did);
			expect(pendingOffers.length).to.equal(1);
		});

		it("Should return offer hash as bytes", async function() {
			const offerHash = await deed.callStatic.makeOffer(asset2.address, 100, lender.address, did, 70);

			const expectedOfferHash = makeOfferHash(pwn.address, 0);
			expect(ethers.utils.isBytesLike(offerHash)).to.equal(true);
			expect(offerHash).to.equal(expectedOfferHash);
		});

		it("Should increase global nonce", async function() {
			await deed.makeOffer(asset2.address, 100, lender.address, did, 70);
			await deed.makeOffer(asset2.address, 101, lender.address, did, 70);

			const expectedFirstOfferHash = makeOfferHash(pwn.address, 0);
			const expectedSecondOfferHash = makeOfferHash(pwn.address, 1);
			const pendingOffers = await deed.getOffers(did);
			expect(pendingOffers.length).to.equal(2);
			expect(pendingOffers[0]).to.equal(expectedFirstOfferHash);
			expect(pendingOffers[1]).to.equal(expectedSecondOfferHash);
		});

		it("Should emit OfferMade event", async function() {
			const amount = 100;
			const toBePaid = 70;

			const offerHash = await deed.callStatic.makeOffer(asset2.address, amount, lender.address, did, toBePaid);
			const tx = await deed.makeOffer(asset2.address, amount, lender.address, did, toBePaid);
			const response = await tx.wait();

			expect(response.logs.length).to.equal(1);
			const logDescription = deedEventIface.parseLog(response.logs[0]);
			expect(logDescription.name).to.equal("OfferMade");
			const args = logDescription.args;
			expect(args.assetAddress).to.equal(asset2.address);
			expect(args.amount).to.equal(amount);
			expect(args.lender).to.equal(lender.address);
			expect(args.toBePaid).to.equal(toBePaid);
			expect(args.did).to.equal(did);
			expect(args.offer).to.equal(offerHash);
		});

	});


	describe("Revoke offer", function() { // -> PWN is trusted source so we believe that it would not send invalid data

		let did;
		let offerHash;

		beforeEach(async function() {
			await deed.create(asset1.address, CATEGORY.ERC20, 3600, 1, 100, borrower.address);
			did = await deed.id();

			offerHash = await deed.callStatic.makeOffer(asset2.address, 100, lender.address, did, 101);
			await deed.makeOffer(asset2.address, 100, lender.address, did, 101);
		});


		it("Should fail when sender is not PWN contract", async function() {
			try {
				await deed.connect(addr1).revokeOffer(offerHash, lender.address);

				expect().fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Caller is not the PWN");
			}
		});

		it("Should fail when sender is not the offer maker", async function() {
			try {
				await deed.revokeOffer(offerHash, addr2.address);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("This address didn't create the offer");
			}
		});

		// TODO: Would be nice to create smock and set variable directly.
		it("Should fail when deed of the offer is not in new/open state", async function() {
			await deed.revoke(did, borrower.address);

			try {
				await deed.revokeOffer(offerHash, lender.address);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Can only remove offers from open Deeds");
			}
		});

		it("Should delete offer", async function() {
			await deed.revokeOffer(offerHash, lender.address);

			const offer = await deed.offers(offerHash);
			expect(offer.credit.assetAddress).to.equal(ethers.constants.AddressZero);
			expect(offer.credit.category).to.equal(0);
			expect(offer.credit.amount).to.equal(0);
			expect(offer.toBePaid).to.equal(0);
			expect(offer.lender).to.equal(ethers.constants.AddressZero);
			expect(offer.did).to.equal(0);
		});

		it("Should delete pending offer"); // Not implemented yet

		it("Should emit OfferRevoked event", async function() {
			const tx = await deed.revokeOffer(offerHash, lender.address);
			const response = await tx.wait();

			expect(response.logs.length).to.equal(1);
			const logDescription = deedEventIface.parseLog(response.logs[0]);
			expect(logDescription.name).to.equal("OfferRevoked");
			const args = logDescription.args;
			expect(args.offer).to.equal(offerHash);
		});

	});


	describe("Accept offer", function() { // -> PWN is trusted source so we believe that it would not send invalid data

		let did;
		let offerHash;
		const duration = 3600;

		beforeEach(async function() {
			await deed.create(asset1.address, CATEGORY.ERC20, duration, 1, 100, borrower.address);
			did = await deed.id();

			offerHash = await deed.callStatic.makeOffer(asset2.address, 100, lender.address, did, 101);
			await deed.makeOffer(asset2.address, 100, lender.address, did, 101);
		});


		it("Should fail when sender is not PWN contract", async function() {
			try {
				await deed.connect(addr1).acceptOffer(did, offerHash, borrower.address);

				expect().fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Caller is not the PWN");
			}
		});

		it("Should fail when sender is not the deed owner", async function() {
			try {
				await deed.acceptOffer(did, offerHash, addr4.address);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("The deed doesn't belong to the caller");
			}
		});

		// TODO: Would be nice to create smock and set variable directly.
		it("Should fail when deed is not in new/open state", async function() {
			await deed.revoke(did, borrower.address);

			try {
				await deed.acceptOffer(did, offerHash, borrower.address);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Deed can't accept more offers");
			}
		});

		it("Should set correct expiration timestamp", async function() {
			await deed.acceptOffer(did, offerHash, borrower.address);

			const deedExpiration = (await deed.deeds(did)).expiration;
			const expectedExpiration = await timestampFromNow(duration);
			expect(deedExpiration).to.equal(expectedExpiration);
		});

		it("Should set offer as accepted in deed", async function() {
			await deed.acceptOffer(did, offerHash, borrower.address);

			const acceptedOffer = (await deed.deeds(did)).acceptedOffer;
			expect(acceptedOffer).to.equal(offerHash);
		});

		it("Should delete deed pending offers", async function() {
			await deed.acceptOffer(did, offerHash, borrower.address);

			const pendingOffers = await deed.getOffers(did);
			expect(pendingOffers.length).to.equal(0);
		});

		it("Should update deed to running state", async function() {
			await deed.acceptOffer(did, offerHash, borrower.address);

			const status = (await deed.deeds(did)).status;
			expect(status).to.equal(2);
		});

		it("Should emit OfferAccepted event", async function() {
			const tx = await deed.acceptOffer(did, offerHash, borrower.address);
			const response = await tx.wait();

			expect(response.logs.length).to.equal(1);
			const logDescription = deedEventIface.parseLog(response.logs[0]);
			expect(logDescription.name).to.equal("OfferAccepted");
			const args = logDescription.args;
			expect(args.did).to.equal(did);
			expect(args.offer).to.equal(offerHash);
		});

	});


	describe("Pay back", function() {

		let did;
		let offerHash;

		beforeEach(async function() {
			await deed.create(asset1.address, CATEGORY.ERC20, 3600, 1, 100, borrower.address);
			did = await deed.id();

			offerHash = await deed.callStatic.makeOffer(asset2.address, 100, lender.address, did, 101);
			await deed.makeOffer(asset2.address, 100, lender.address, did, 101);

			await deed.acceptOffer(did, offerHash, borrower.address);
		});


		it("Should fail when sender is not PWN contract", async function() {
			try {
				await deed.connect(addr1).payBack(did);

				expect().fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Caller is not the PWN");
			}
		});

		// TODO: Would be nice to create smock and set variable directly.
		it("Should fail when deed is not in running state", async function() {
			await deed.create(asset1.address, CATEGORY.ERC20, 3600, 1, 100, borrower.address);
			did = await deed.id();

			try {
				await deed.payBack(did);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Deed doesn't have an accepted offer to be paid back");
			}
		});

		it("Should update deed to paid back state", async function() {
			await deed.payBack(did);

			const status = (await deed.deeds(did)).status;
			expect(status).to.equal(3);
		});

		it("Should emit PaidBack event", async function() {
			const tx = await deed.payBack(did);
			const response = await tx.wait();

			expect(response.logs.length).to.equal(1);
			const logDescription = deedEventIface.parseLog(response.logs[0]);
			expect(logDescription.name).to.equal("PaidBack");
			const args = logDescription.args;
			expect(args.did).to.equal(did);
			expect(args.offer).to.equal(offerHash);
		});

	});


	describe("Claim", function() {

		const duration = 3600;
		let did;
		let offerHash;

		beforeEach(async function() {
			await deed.create(asset1.address, CATEGORY.ERC20, duration, 1, 100, borrower.address);
			did = await deed.id();

			offerHash = await deed.callStatic.makeOffer(asset2.address, 100, lender.address, did, 101);
			await deed.makeOffer(asset2.address, 100, lender.address, did, 101);

			await deed.acceptOffer(did, offerHash, borrower.address);
		});


		it("Should fail when sender is not PWN contract", async function() {
			try {
				await deed.connect(addr1).claim(did, lender.address);

				expect().fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Caller is not the PWN");
			}
		});

		it("Should fail when sender is not deed owner", async function() {
			try {
				await deed.claim(did, addr4.address);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Caller is not the deed owner");
			}
		});

		// TODO: Would be nice to create smock and set variable directly.
		it("Should fail when deed is not in paid back nor expired state", async function() {
			await deed.create(asset1.address, CATEGORY.ERC20, duration, 1, 100, borrower.address);
			did = await deed.id();

			try {
				await deed.claim(did, borrower.address);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Deed can't be claimed yet");
			}
		});

		// TODO: Would be nice to create smock and set variable directly.
		it("Should be possible to claim expired deed", async function() {
			await ethers.provider.send("evm_increaseTime", [parseInt(time.duration.days(1))]);
      		await ethers.provider.send("evm_mine");

			await deed.claim(did, borrower.address);

			expect(true);
		});

		// TODO: Would be nice to create smock and set variable directly.
		it("Should be possible to claim paid back deed", async function() {
			await deed.payBack(did);

			await deed.claim(did, borrower.address);

			expect(true);
		});

		it("Should update deed to dead state", async function() {
			await deed.payBack(did);

			await deed.claim(did, borrower.address);

			const status = (await deed.deeds(did)).status;
			expect(status).to.equal(0);
		});

		it("Should emit DeedClaimed event", async function() {
			await deed.payBack(did);

			const tx = await deed.claim(did, borrower.address);
			const response = await tx.wait();

			expect(response.logs.length).to.equal(1);
			const logDescription = deedEventIface.parseLog(response.logs[0]);
			expect(logDescription.name).to.equal("DeedClaimed");
			const args = logDescription.args;
			expect(args.did).to.equal(did);
		});

	});


	describe("Burn", function() { // -> PWN is trusted source so we believe that it would not send invalid data

		let did;

		beforeEach(async function() {
			await deed.create(asset1.address, CATEGORY.ERC20, 3600, 1, 100, borrower.address);
			did = await deed.id();
		});


		it("Should fail when sender is not PWN contract", async function() {
			try {
				await deed.connect(addr1).burn(did, borrower.address);

				expect().fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Caller is not the PWN");
			}
		});

		it("Should fail when passing address is not deed owner", async function() {
			try {
				await deed.burn(did, addr4.address);

				expect().fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Caller is not the deed owner");
			}
		});

		// TODO: Would be nice to create smock and set variable directly.
		it("Should fail when deed is not in dead state", async function() {
			try {
				await deed.burn(did, borrower.address);

				expect().fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Deed can't be burned at this stage");
			}
		});

		it("Should delete deed data", async function() {
			await deed.revoke(did, borrower.address);

			await deed.burn(did, borrower.address);

			const deedToken = await deed.deeds(did);
			expect(deedToken.expiration).to.equal(0);
			expect(deedToken.duration).to.equal(0);
			expect(deedToken.borrower).to.equal(ethers.constants.AddressZero);
			expect(deedToken.collateral.assetAddress).to.equal(ethers.constants.AddressZero);
			expect(deedToken.collateral.category).to.equal(0);
			expect(deedToken.collateral.id).to.equal(0);
			expect(deedToken.collateral.amount).to.equal(0);
		});

		it("Should burn deed ERC1155 token", async function() {
			await deed.revoke(did, borrower.address);

			await deed.burn(did, borrower.address);

			const balance = await deed.balanceOf(borrower.address, did);
			expect(balance).to.equal(0);
		});

	});


	describe("Before token transfer", function() {

		let did;

		beforeEach(async function() {
			await deed.create(asset1.address, CATEGORY.ERC20, 3600, 1, 12, borrower.address);
			did = await deed.id();
		});


		it("Should fail when transferring deed in new/open state", async function() {
			try {
				await deed.connect(borrower).safeTransferFrom(borrower.address, lender.address, did, 1, ethers.utils.arrayify("0x"));

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Deed can't be transferred at this stage");
			}
		});

	});


	describe("View functions", function() {

		const cAssetId = 1;
		const cAmount = 100;

		const lAmount = 110;
		const lToBePaid = 111;

		const duration = 3600;
		let did;
		let offerHash;

		beforeEach(async function() {
			await deed.create(asset1.address, CATEGORY.ERC20, duration, cAssetId, cAmount, borrower.address);
			did = await deed.id();

			offerHash = await deed.callStatic.makeOffer(asset2.address, lAmount, lender.address, did, lToBePaid);
			await deed.makeOffer(asset2.address, lAmount, lender.address, did, lToBePaid);
		});

		// VIEW FUNCTIONS - DEEDS

		describe("Get deed status", function() {

			it("Should return none/dead state", async function() {
				await deed.revoke(did, borrower.address);

				const status = await deed.getDeedStatus(did);

				expect(status).to.equal(0);
			});

			it("Should return new/open state", async function() {
				const status = await deed.getDeedStatus(did);

				expect(status).to.equal(1);
			});

			it("Should return running state when not expired", async function() {
				await deed.acceptOffer(did, offerHash, borrower.address);

				const status = await deed.getDeedStatus(did);

				expect(status).to.equal(2);
			});

			it("Should return expired state when in running state", async function() {
				await deed.acceptOffer(did, offerHash, borrower.address);

				await ethers.provider.send("evm_increaseTime", [parseInt(time.duration.days(1))]);
      			await ethers.provider.send("evm_mine");


				const status = await deed.getDeedStatus(did);

				expect(status).to.equal(4);
			});

			it("Should return paid back state when not expired", async function() {
				await deed.acceptOffer(did, offerHash, borrower.address);
				await deed.payBack(did);

				const status = await deed.getDeedStatus(did);

				expect(status).to.equal(3);
			});

			it("Should return paid back state when expired", async function() {
				await deed.acceptOffer(did, offerHash, borrower.address);

				await deed.payBack(did);

				await ethers.provider.send("evm_increaseTime", [parseInt(time.duration.days(1))]);
      			await ethers.provider.send("evm_mine");


				const status = await deed.getDeedStatus(did);

				expect(status).to.equal(3);
			});

		});


		describe("Get expiration", function() {

			it("Should return deed expiration", async function() {
				await deed.acceptOffer(did, offerHash, borrower.address);

				const getterExpiration = await deed.getExpiration(did);

				const deedExpiration = (await deed.deeds(did)).expiration;
				expect(getterExpiration).to.equal(deedExpiration);
			});

		});

		describe("Get duration", function() {

			it("Should return deed duration", async function() {
				const deedDuration = await deed.getDuration(did);

				expect(deedDuration).to.equal(duration);
			});

		});


		describe("Get borrower", function() {

			it("Should return borrower address", async function() {
				const borrowerAddress = await deed.getBorrower(did);

				expect(borrowerAddress).to.equal(borrower.address);
			});

		});


		describe("Get deed collateral asset", function() {

			it("Should return deed collateral asset", async function() {
				const collateral = await deed.getDeedCollateral(did);

				expect(collateral.assetAddress).to.equal(asset1.address);
				expect(collateral.category).to.equal(CATEGORY.ERC20);
				expect(collateral.amount).to.equal(cAmount);
				expect(collateral.id).to.equal(cAssetId);
			});

		});


		describe("Get offers", function() {

			it("Should return deed pending offers byte array", async function() {
				const pendingOffers = await deed.getOffers(did);

				expect(pendingOffers.length).to.equal(1);
				expect(pendingOffers[0]).to.equal(offerHash);
			});

		});


		describe("Get accepted offer", function() {

			it("Should return deed accepted offer", async function() {
				await deed.acceptOffer(did, offerHash, borrower.address);

				const acceptedOffer = await deed.getAcceptedOffer(did);

				expect(acceptedOffer).to.equal(offerHash);
			});

		});

		// VIEW FUNCTIONS - OFFERS

		describe("Get deed ID", function() {

			it("Should return deed ID", async function() {
				const deedId = await deed.getDeedID(offerHash);

				expect(deedId).to.equal(did);
			});

		});


		describe("Get offer credit asset", function() {

			it("Should return offer credit asset", async function() {
				const credit = await deed.getOfferCredit(offerHash);

				expect(credit.assetAddress).to.equal(asset2.address);
				expect(credit.category).to.equal(CATEGORY.ERC20);
				expect(credit.amount).to.equal(lAmount);
				expect(credit.id).to.equal(0);
			});

		});


		describe("To be paid", function() {

			it("Should return offer to be paid value", async function() {
				const toBePaid = await deed.toBePaid(offerHash);

				expect(toBePaid).to.equal(lToBePaid);
			});

		});


		describe("Get lender", function() {

			it("Should return lender address", async function() {
				const lenderAddress = await deed.getLender(offerHash);

				expect(lenderAddress).to.equal(lender.address);
			});

		});

	});


	describe("Set PWN", function() {

		it("Should fail when sender is not owner", async function() {
			try {
				await deed.connect(addr1).setPWN(addr2.address);
				expect().fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Ownable: caller is not the owner");
			}
		});

		it("Should set PWN address", async function() {
			const formerPWN = await deed.PWN();

			await deed.connect(pwn).setPWN(addr1.address);

			const latterPWN = await deed.PWN();
			expect(formerPWN).to.not.equal(latterPWN);
			expect(latterPWN).to.equal(addr1.address);
		});

	});

});
