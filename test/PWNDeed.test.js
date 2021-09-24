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
	let pwn, addr1, addr2, addr3, addr4, addr5;

	const getExpiration = async function(delta) {
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
		[pwn, addr1, addr2, addr3, addr4, addr5] = await ethers.getSigners();

		deedEventIface = new ethers.utils.Interface([
			"event NewDeed(address indexed tokenAddress, uint8 cat, uint256 id, uint256 amount, uint256 expiration, uint256 indexed did)",
		    "event NewOffer(address tokenAddress, uint8 cat, uint256 amount, address indexed lender, uint256 toBePaid, uint256 indexed did, bytes32 offer)",
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
				await deed.connect(addr1).create(addr2.address, CATEGORY.ERC20, 0, 0, 0, addr3.address);
				expect().fail();
			} catch(error) {
				expect(error.message).to.contain("revert"); // TODO: Add reason?
			}
		});

		it("Should mint deed ERC1155 token", async function () {
			await deed.create(addr2.address, CATEGORY.ERC20, 1, 100, 54, addr3.address);
			const tokenId = await deed.id();

			const balance = await deed.balanceOf(addr3.address, tokenId);
			expect(balance).to.equal(1);
		});

		it("Should save deed data", async function () {
			await deed.create(addr2.address, CATEGORY.ERC20, 1, 100, 54, addr3.address);
			const tokenId = await deed.id();

			const deedToken = await deed.deeds(tokenId);
			expect(deedToken.status).to.equal(1);
			expect(deedToken.expiration).to.equal(54);
			expect(deedToken.borrower).to.equal(addr3.address);
			expect(deedToken.asset.cat).to.equal(0);
			expect(deedToken.asset.id).to.equal(1);
			expect(deedToken.asset.amount).to.equal(100);
			expect(deedToken.asset.tokenAddress).to.equal(addr2.address);
		});

		it("Should return minted deed ID", async function() {
			const tokenId = await deed.callStatic.create(addr2.address, CATEGORY.ERC20, 1, 100, 54, addr3.address);

			expect(ethers.BigNumber.isBigNumber(tokenId)).to.equal(true);
		});

		it("Should increase global deed ID", async function() {
			await deed.create(addr2.address, CATEGORY.ERC20, 1, 100, 54, addr3.address);
			const tokenId1 = await deed.id();

			await deed.create(addr2.address, CATEGORY.ERC20, 1, 100, 54, addr3.address);
			const tokenId2 = await deed.id();

			expect(tokenId2).to.equal(tokenId1.add(1));
		});

		it("Should emit NewDeed event", async function() {
			const amount = 10;
			const fakeToken = await smock.fake("Basic20");
			const expiration = 110;

			const did = await deed.callStatic.create(addr2.address, CATEGORY.ERC20, 1, amount, expiration, addr3.address);
			const tx = await deed.create(addr2.address, CATEGORY.ERC20, 1, amount, expiration, addr3.address);
			const response = await tx.wait();

			expect(response.logs.length).to.equal(2);
			const logDescription = deedEventIface.parseLog(response.logs[1]);
			expect(logDescription.name).to.equal("NewDeed");
			expect(logDescription.args.tokenAddress).to.equal(addr2.address);
			expect(logDescription.args.cat).to.equal(CATEGORY.ERC20);
			expect(logDescription.args.id).to.equal(1);
			expect(logDescription.args.amount).to.equal(amount);
			expect(logDescription.args.expiration).to.equal(expiration);
			expect(logDescription.args.did).to.equal(did);
		});

	});


	describe("Revoke", function() {

		let did;
		let expiration;

		beforeEach(async function() {
			expiration = await getExpiration(54);
			await deed.create(addr1.address, CATEGORY.ERC20, 1, 100, expiration, addr3.address);
			did = await deed.id();
		});


		it("Shuold fail when sender is not PWN contract", async function() {
			try {
				await deed.connect(addr1).revoke(did, addr3.address);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert"); // TODO: Add reason?
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
			await deed.revoke(did, addr3.address);

			try {
				await deed.revoke(did, addr3.address);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Deed can't be revoked at this stage");
			}
		});

		it("Should update deed to dead state", async function() {
			await deed.revoke(did, addr3.address);

			const status = (await deed.deeds(did)).status
			expect(status).to.equal(0);
		});

		it("Should emit DeedRevoked event", async function() {
			const tx = await deed.revoke(did, addr3.address);
			const response = await tx.wait();

			expect(response.logs.length).to.equal(1);
			const logDescription = deedEventIface.parseLog(response.logs[0]);
			expect(logDescription.name).to.equal("DeedRevoked");
			expect(logDescription.args.did).to.equal(did);
		});

	});


	describe("Make offer", function() { // -> PWN is trusted source so we believe that it would not send invalid data

		let did;
		let expiration;

		const makeOfferHash = function(address, nonce) {
			return ethers.utils.solidityKeccak256(["address", "uint256"], [address, nonce]);
		};

		beforeEach(async function() {
			expiration = await getExpiration(54);
			await deed.create(addr1.address, CATEGORY.ERC20, 1, 100, expiration, addr3.address);
			did = await deed.id();
		});


		it("Should fail when sender is not PWN contract", async function() {
			try {
				await deed.connect(addr1).makeOffer(addr3.address, CATEGORY.ERC20, 100, addr4.address, did, 70);

				expect().fail();
			} catch(error) {
				expect(error.message).to.contain("revert"); // TODO: Add reason?
			}
		});

		it("Should fail when deed is not in new/open state", async function() {
			await deed.revoke(did, addr3.address);

			try {
				await deed.makeOffer(addr3.address, CATEGORY.ERC20, 100, addr4.address, did, 70);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Deed not accepting offers");
			}
		});

		it("Should save offer data", async function() {
			const amount = 100;
			const toBePaid = 70;

			await deed.makeOffer(addr3.address, CATEGORY.ERC20, amount, addr4.address, did, toBePaid);

			const pendingOffers = await deed.getOffers(did);
			const offerHash = pendingOffers[0];
			const offer = await deed.offers(offerHash);
			expect(offer.asset.cat).to.equal(CATEGORY.ERC20);
			expect(offer.asset.amount).to.equal(amount);
			expect(offer.asset.tokenAddress).to.equal(addr3.address);
			expect(offer.lender).to.equal(addr4.address);
			expect(offer.deedID).to.equal(did);
			expect(offer.toBePaid).to.equal(toBePaid);
		});

		it("Should set offer to deed", async function() {
			await deed.makeOffer(addr3.address, CATEGORY.ERC20, 100, addr4.address, did, 70);

			// Cannot get pendingOffers from deed.pendingOffers because `solc` generates incorrect ABI for implicit property getters with dynamic array
			// GH issue: https://github.com/ethereum/solidity/issues/4244
			const pendingOffers = await deed.getOffers(did);
			expect(pendingOffers.length).to.equal(1);
		});

		it("Should return offer hash as bytes", async function() {
			const offerHash = await deed.callStatic.makeOffer(addr3.address, CATEGORY.ERC20, 100, addr4.address, did, 70);

			const expectedOfferHash = makeOfferHash(pwn.address, 0);
			expect(ethers.utils.isBytesLike(offerHash)).to.equal(true);
			expect(offerHash).to.equal(expectedOfferHash);
		});

		it("Should increase global nonce", async function() {
			await deed.makeOffer(addr3.address, CATEGORY.ERC20, 100, addr4.address, did, 70);
			await deed.makeOffer(addr3.address, CATEGORY.ERC20, 101, addr4.address, did, 70);

			const expectedFirstOfferHash = makeOfferHash(pwn.address, 0);
			const expectedSecondOfferHash = makeOfferHash(pwn.address, 1);
			const pendingOffers = await deed.getOffers(did);
			expect(pendingOffers.length).to.equal(2);
			expect(pendingOffers[0]).to.equal(expectedFirstOfferHash);
			expect(pendingOffers[1]).to.equal(expectedSecondOfferHash);
		});

		it("Should emit NewOffer event", async function() {
			const amount = 100;
			const toBePaid = 70;

			const offerHash = await deed.callStatic.makeOffer(addr3.address, CATEGORY.ERC20, amount, addr4.address, did, toBePaid);
			const tx = await deed.makeOffer(addr3.address, CATEGORY.ERC20, amount, addr4.address, did, toBePaid);
			const response = await tx.wait();

			expect(response.logs.length).to.equal(1);
			const logDescription = deedEventIface.parseLog(response.logs[0]);
			expect(logDescription.name).to.equal("NewOffer");
			const args = logDescription.args;
			expect(args.tokenAddress).to.equal(addr3.address);
			expect(args.cat).to.equal(CATEGORY.ERC20);
			expect(args.amount).to.equal(amount);
			expect(args.lender).to.equal(addr4.address);
			expect(args.toBePaid).to.equal(toBePaid);
			expect(args.did).to.equal(did);
			expect(args.offer).to.equal(offerHash);
		});

	});


	describe("Revoke offer", function() { // -> PWN is trusted source so we believe that it would not send invalid data

		let did;
		let offerHash;
		let expiration;

		beforeEach(async function() {
			expiration = await getExpiration(54);
			await deed.create(addr1.address, CATEGORY.ERC20, 1, 100, expiration, addr3.address);
			did = await deed.id();

			offerHash = await deed.callStatic.makeOffer(addr3.address, CATEGORY.ERC20, 100, addr4.address, did, 101);
			await deed.makeOffer(addr3.address, CATEGORY.ERC20, 100, addr4.address, did, 101);
		});


		it("Should fail when sender is not PWN contract", async function() {
			try {
				await deed.connect(addr1).revokeOffer(offerHash, addr4.address);

				expect().fail();
			} catch(error) {
				expect(error.message).to.contain("revert"); // TODO: Add reason?
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

		it("Should fail when deed of the offer is not in new/open state", async function() {
			await deed.revoke(did, addr3.address);

			try {
				await deed.revokeOffer(offerHash, addr4.address);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Can only remove offers from open Deeds");
			}
		});

		it("Should delete offer", async function() {
			await deed.revokeOffer(offerHash, addr4.address);

			const offer = await deed.offers(offerHash);
			expect(offer.asset.cat).to.equal(0);
			expect(offer.asset.amount).to.equal(0);
			expect(offer.asset.tokenAddress).to.equal(ethers.constants.AddressZero);
			expect(offer.toBePaid).to.equal(0);
			expect(offer.lender).to.equal(ethers.constants.AddressZero);
			expect(offer.deedID).to.equal(0);
		});

		it("Should delete pending offer"); // Not implemented yet

		it("Should emit OfferRevoked event", async function() {
			const tx = await deed.revokeOffer(offerHash, addr4.address);
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
		let expiration;

		beforeEach(async function() {
			expiration = await getExpiration(54);
			await deed.create(addr1.address, CATEGORY.ERC20, 1, 100, expiration, addr3.address);
			did = await deed.id();

			offerHash = await deed.callStatic.makeOffer(addr3.address, CATEGORY.ERC20, 100, addr4.address, did, 101);
			await deed.makeOffer(addr3.address, CATEGORY.ERC20, 100, addr4.address, did, 101);
		});


		it("Should fail when sender is not PWN contract", async function() {
			try {
				await deed.connect(addr1).acceptOffer(did, offerHash, addr3.address);

				expect().fail();
			} catch(error) {
				expect(error.message).to.contain("revert"); // TODO: Add reason?
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

		it("Should fail when deed is not in new/open state", async function() {
			await deed.revoke(did, addr3.address);

			try {
				await deed.acceptOffer(did, offerHash, addr3.address);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Deed can't accept more offers");
			}
		});

		it("Should set offer as accepted in deed", async function() {
			await deed.acceptOffer(did, offerHash, addr3.address);

			const acceptedOffer = (await deed.deeds(did)).acceptedOffer;
			expect(acceptedOffer).to.equal(offerHash);
		});

		it("Should delete deed pending offers", async function() {
			await deed.acceptOffer(did, offerHash, addr3.address);

			const pendingOffers = await deed.getOffers(did);
			expect(pendingOffers.length).to.equal(0);
		});

		it("Should update deed to running state", async function() {
			await deed.acceptOffer(did, offerHash, addr3.address);

			const status = (await deed.deeds(did)).status;
			expect(status).to.equal(2);
		});

		it("Should emit OfferAccepted event", async function() {
			const tx = await deed.acceptOffer(did, offerHash, addr3.address);
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
		let expiration;

		beforeEach(async function() {
			expiration = await getExpiration(54);
			await deed.create(addr1.address, CATEGORY.ERC20, 1, 100, expiration, addr3.address);
			did = await deed.id();

			offerHash = await deed.callStatic.makeOffer(addr3.address, CATEGORY.ERC20, 100, addr4.address, did, 101);
			await deed.makeOffer(addr3.address, CATEGORY.ERC20, 100, addr4.address, did, 101);

			await deed.acceptOffer(did, offerHash, addr3.address);
		});


		it("Should fail when sender is not PWN contract", async function() {
			try {
				await deed.connect(addr1).payBack(did);

				expect().fail();
			} catch(error) {
				expect(error.message).to.contain("revert"); // TODO: Add reason?
			}
		});

		it("Should fail when deed is not in running state", async function() {
			await deed.create(addr1.address, CATEGORY.ERC20, 1, 100, expiration, addr3.address);
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

		const duration = 110;
		let did;
		let offerHash;

		beforeEach(async function() {
			await deed.create(addr1.address, CATEGORY.ERC20, 1, 100, getExpiration(duration), addr3.address);
			did = await deed.id();

			offerHash = await deed.callStatic.makeOffer(addr3.address, CATEGORY.ERC20, 100, addr4.address, did, 101);
			await deed.makeOffer(addr3.address, CATEGORY.ERC20, 100, addr4.address, did, 101);

			await deed.acceptOffer(did, offerHash, addr3.address);
		});


		it("Should fail when sender is not PWN contract", async function() {
			try {
				await deed.connect(addr1).claim(did, addr3.address);

				expect().fail();
			} catch(error) {
				expect(error.message).to.contain("revert"); // TODO: Add reason?
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

		it("Should fail when deed is not in paid back nor expired state", async function() {
			await deed.create(addr1.address, CATEGORY.ERC20, 1, 100, getExpiration(duration), addr3.address);
			did = await deed.id();

			try {
				await deed.claim(did, addr3.address);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Deed can't be claimed yet");
			}
		});

		it("Should be possible to claim expired deed", async function() {
			await deed.create(addr1.address, CATEGORY.ERC20, 1, 100, 54, addr3.address);
			did = await deed.id();

			await deed.claim(did, addr3.address);

			expect(true);
		});

		it("Should be possible to claim paid back deed", async function() {
			await deed.payBack(did);

			await deed.claim(did, addr3.address);

			expect(true);
		});

		it("Should update deed to dead state", async function() {
			await deed.payBack(did);

			await deed.claim(did, addr3.address);

			const status = (await deed.deeds(did)).status;
			expect(status).to.equal(0);
		});

		it("Should emit DeedClaimed event", async function() {
			await deed.payBack(did);

			const tx = await deed.claim(did, addr3.address);
			const response = await tx.wait();

			expect(response.logs.length).to.equal(1);
			const logDescription = deedEventIface.parseLog(response.logs[0]);
			expect(logDescription.name).to.equal("DeedClaimed");
			const args = logDescription.args;
			expect(args.did).to.equal(did);
		});

	});


	describe("Burn", function() { // -> PWN is trusted source so we believe that it would not send invalid data

		const duration = 110;
		let did;

		beforeEach(async function() {
			await deed.create(addr1.address, CATEGORY.ERC20, 1, 100, getExpiration(duration), addr3.address);
			did = await deed.id();
		});


		it("Should fail when sender is not PWN contract", async function() {
			try {
				await deed.connect(addr1).burn(did, addr3.address);

				expect().fail();
			} catch(error) {
				expect(error.message).to.contain("revert"); // TODO: Add reason?
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

		it("Should fail when deed is not in dead state", async function() {
			try {
				await deed.burn(did, addr3.address);

				expect().fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Deed can't be burned at this stage");
			}
		});

		it("Should delete deed data", async function() {
			await deed.revoke(did, addr3.address);

			await deed.burn(did, addr3.address);

			const deedToken = await deed.deeds(did);
			expect(deedToken.expiration).to.equal(0);
			expect(deedToken.borrower).to.equal(ethers.constants.AddressZero);
			expect(deedToken.asset.cat).to.equal(0);
			expect(deedToken.asset.id).to.equal(0);
			expect(deedToken.asset.amount).to.equal(0);
			expect(deedToken.asset.tokenAddress).to.equal(ethers.constants.AddressZero);
		});

		it("Should burn deed ERC1155 token", async function() {
			await deed.revoke(did, addr3.address);

			await deed.burn(did, addr3.address);

			const balance = await deed.balanceOf(addr3.address, did);
			expect(balance).to.equal(0);
		});

	});

	// should we test function beforeTokenTransfer??

	describe("View functions", function() {

		const cTokenId = 1;
		const cAmount = 100;

		const lAmount = 110;
		const lToBePaid = 111;

		let did;
		let offerHash;
		let expiration;

		beforeEach(async function() {
			expiration = await getExpiration(parseInt(time.duration.days(7)));

			await deed.create(addr1.address, CATEGORY.ERC20, cTokenId, cAmount, expiration, addr3.address);
			did = await deed.id();

			offerHash = await deed.callStatic.makeOffer(addr2.address, CATEGORY.ERC20, lAmount, addr4.address, did, lToBePaid);
			await deed.makeOffer(addr2.address, CATEGORY.ERC20, lAmount, addr4.address, did, lToBePaid);
		});

		// VIEW FUNCTIONS - DEEDS

		describe("Get deed status", function() {

			it("Should return none/dead state", async function() {
				await deed.revoke(did, addr3.address);


				const status = await deed.getDeedStatus(did);

				expect(status).to.equal(0);
			});

			it("Should return new/open state when not expired", async function() {
				const status = await deed.getDeedStatus(did);

				expect(status).to.equal(1);
			});

			it("Should return expired state when in new/open state", async function() {
				await ethers.provider.send("evm_increaseTime", [parseInt(time.duration.days(7)) + 10]);
      			await ethers.provider.send("evm_mine");

				const status = await deed.getDeedStatus(did);

				expect(status).to.equal(4);
			});

			it("Should return running state when not expired", async function() {
				await deed.acceptOffer(did, offerHash, addr3.address);

				const status = await deed.getDeedStatus(did);

				expect(status).to.equal(2);
			});

			it("Should return expired state when in running state", async function() {
				await deed.acceptOffer(did, offerHash, addr3.address);

				await ethers.provider.send("evm_increaseTime", [parseInt(time.duration.days(7)) + 10]);
      			await ethers.provider.send("evm_mine");


				const status = await deed.getDeedStatus(did);

				expect(status).to.equal(4);
			});

			it("Should return paid back state when not expired", async function() {
				await deed.acceptOffer(did, offerHash, addr3.address);
				await deed.payBack(did);

				const status = await deed.getDeedStatus(did);

				expect(status).to.equal(3);
			});

			it("Should return paid back state when expired", async function() {
				await deed.acceptOffer(did, offerHash, addr3.address);

				await deed.payBack(did);

				await ethers.provider.send("evm_increaseTime", [parseInt(time.duration.days(7)) + 10]);
      			await ethers.provider.send("evm_mine");


				const status = await deed.getDeedStatus(did);

				expect(status).to.equal(3);
			});

		});


		describe("Get expiration", function() {

			it("Should return deed expiration", async function() {
				const deedExpiration = await deed.getExpiration(did);

				expect(deedExpiration).to.equal(expiration);
			});

		});


		describe("Get borrower", function() {

			it("Should return borrower address", async function() {
				const borrower = await deed.getBorrower(did);

				expect(borrower).to.equal(addr3.address);
			});

		});


		describe("Get deed asset", function() {

			it("Should return deed asset", async function() {
				const asset = await deed.getDeedAsset(did);

				expect(asset.cat).to.equal(CATEGORY.ERC20);
				expect(asset.amount).to.equal(cAmount);
				expect(asset.id).to.equal(cTokenId);
				expect(asset.tokenAddress).to.equal(addr1.address);
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
				await deed.acceptOffer(did, offerHash, addr3.address);

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


		describe("Get offer asset", function() {

			it("Should return offer asset", async function() {
				const asset = await deed.getOfferAsset(offerHash);

				expect(asset.cat).to.equal(CATEGORY.ERC20);
				expect(asset.amount).to.equal(lAmount);
				expect(asset.id).to.equal(0);
				expect(asset.tokenAddress).to.equal(addr2.address);
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
				const lender = await deed.getLender(offerHash);

				expect(lender).to.equal(addr4.address);
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
			}
		});

		it("Should set PWN address", async function() {
			const formerPWN = await deed.PWN();

			deed.connect(pwn).setPWN(addr1.address);

			const latterPWN = await deed.PWN();
			expect(formerPWN).to.not.equal(latterPWN);
			expect(latterPWN).to.equal(addr1.address);
		});

	});

});
