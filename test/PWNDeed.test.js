const chai = require("chai");
const { ethers } = require("hardhat");
const { smock } = require("@defi-wonderland/smock");
const { time } = require('@openzeppelin/test-helpers');

const expect = chai.expect;
chai.use(smock.matchers);

describe("PWNDeed contract", function() {

	let deed;

	let Deed;
	let pwn, addr1, addr2, addr3, addr4, addr5;

	before(async function() {
		Deed = await ethers.getContractFactory("PWNDeed");
		[pwn, addr1, addr2, addr3, addr4, addr5] = await ethers.getSigners();
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

	describe("Mint", function() { // -> PWN is trusted source so we believe that it would not send invalid data
		it("Should fail when sender is not PWN contract", async function() {
			try {
				await deed.connect(addr1).mint(0, 0, 0, addr2.address, 0, addr3.address);

				expect().fail();
			} catch(error) {
				expect(error.message).to.contain("revert"); // TODO: Add reason?
			}
		});

		it("Should mint deed ERC1155 token", async function () {
			await deed.mint(0, 1, 100, addr2.address, 54, addr3.address);
			const tokenId = await deed.id();

			const balance = await deed.balanceOf(addr3.address, tokenId);
			expect(balance).to.equal(1);
		});

		it("Should save deed data", async function () {
			await deed.mint(0, 1, 100, addr2.address, 54, addr3.address);
			const tokenId = await deed.id();

			const deedToken = await deed.deeds(tokenId);
			expect(deedToken.expiration).to.equal(54);
			expect(deedToken.borrower).to.equal(addr3.address);
			expect(deedToken.asset.cat).to.equal(0);
			expect(deedToken.asset.id).to.equal(1);
			expect(deedToken.asset.amount).to.equal(100);
			expect(deedToken.asset.tokenAddress).to.equal(addr2.address);
		});

		it("Should return minted deed ID", async function() {
			const tokenId = await deed.callStatic.mint(0, 1, 100, addr2.address, 54, addr3.address);

			expect(ethers.BigNumber.isBigNumber(tokenId)).to.equal(true);
		});

		it("Should increase global deed ID", async function() {
			await deed.mint(0, 1, 100, addr2.address, 54, addr3.address);
			const tokenId1 = await deed.id();

			await deed.mint(0, 1, 100, addr2.address, 54, addr3.address);
			const tokenId2 = await deed.id();

			expect(tokenId2).to.equal(tokenId1.add(1));
		});
	});

	describe("Burn", function() { // -> PWN is trusted source so we believe that it would not send invalid data
		it("Should fail when sender is not PWN contract", async function() {
			try {
				await deed.mint(0, 1, 100, addr2.address, 54, addr3.address);
				const tokenId = await deed.id();

				await deed.connect(addr1)['burn(uint256,address)'](tokenId, addr3.address);
				expect().fail();
			} catch(error) {
				expect(error.message).to.contain("revert"); // TODO: Add reason?
			}
		});

		it("Should burn deed ERC1155 token", async function() {
			await deed.mint(0, 1, 100, addr2.address, 54, addr3.address);
			const tokenId = await deed.id();

			await deed['burn(uint256,address)'](tokenId, addr3.address);

			const balance = await deed.balanceOf(addr3.address, tokenId);
			expect(balance).to.equal(0);
		});

		it("Should delete deed data", async function() {
			await deed.mint(0, 1, 100, addr2.address, 54, addr3.address);
			const tokenId = await deed.id();

			await deed['burn(uint256,address)'](tokenId, addr3.address);

			const deedToken = await deed.deeds(tokenId);
			expect(deedToken.expiration).to.equal(0);
			expect(deedToken.borrower).to.equal(ethers.constants.AddressZero);
			expect(deedToken.asset.cat).to.equal(0);
			expect(deedToken.asset.id).to.equal(0);
			expect(deedToken.asset.amount).to.equal(0);
			expect(deedToken.asset.tokenAddress).to.equal(ethers.constants.AddressZero);
		});
	});

	describe("Set offer", function() { // -> PWN is trusted source so we believe that it would not send invalid data
		const makeOfferHash = function(address, nonce) {
			return ethers.utils.solidityKeccak256(["address", "uint256"], [address, nonce]);
		};

		it("Should fail when sender is not PWN contract", async function() {
			try {
				await deed.mint(0, 1, 100, addr2.address, 54, addr3.address);
				const tokenId = await deed.id();

				await deed.connect(addr1).setOffer(0, 100, addr3.address, addr4.address, tokenId, 70);

				expect().fail();
			} catch(error) {
				expect(error.message).to.contain("revert"); // TODO: Add reason?
			}
		});

		it("Should set offer to deed", async function() {
			await deed.mint(0, 1, 100, addr2.address, 54, addr3.address);
			const tokenId = await deed.id();

			await deed.setOffer(0, 100, addr3.address, addr4.address, tokenId, 70);

			// Cannot get pendingOffers from deed.pendingOffers because `solc` generates incorrect ABI for implicit property getters with dynamic array
			// GH issue: https://github.com/ethereum/solidity/issues/4244
			const pendingOffers = await deed.callStatic.getOffers(tokenId);
			expect(pendingOffers.length).to.equal(1);
		});

		it("Should save offer data", async function() {
			await deed.mint(0, 1, 100, addr2.address, 54, addr3.address);
			const tokenId = await deed.id();

			await deed.setOffer(0, 100, addr3.address, addr4.address, tokenId, 70);

			const pendingOffers = await deed.callStatic.getOffers(tokenId);
			const offerHash = pendingOffers[0];
			const offer = await deed.offers(offerHash);
			expect(offer.asset.cat).to.equal(0);
			expect(offer.asset.amount).to.equal(100);
			expect(offer.asset.tokenAddress).to.equal(addr3.address);
			expect(offer.toBePaid).to.equal(70);
			expect(offer.lender).to.equal(addr4.address);
			expect(offer.deedID).to.equal(tokenId);
		});

		it("Should return offer hash as bytes", async function() {
			await deed.mint(0, 1, 100, addr2.address, 54, addr3.address);
			const tokenId = await deed.id();

			const offerHash = await deed.callStatic.setOffer(0, 100, addr3.address, addr4.address, tokenId, 70);

			const expectedOfferHash = makeOfferHash(pwn.address, 0);
			expect(ethers.utils.isBytesLike(offerHash)).to.equal(true);
			expect(offerHash).to.equal(expectedOfferHash);
		});

		it("Should increase global nonce", async function() {
			await deed.mint(0, 1, 100, addr2.address, 54, addr3.address);
			const tokenId = await deed.id();

			await deed.setOffer(0, 100, addr3.address, addr4.address, tokenId, 70);
			await deed.setOffer(0, 101, addr3.address, addr4.address, tokenId, 70);

			const expectedFirstOfferHash = makeOfferHash(pwn.address, 0);
			const expectedSecondOfferHash = makeOfferHash(pwn.address, 1);
			const pendingOffers = await deed.callStatic.getOffers(tokenId);
			expect(pendingOffers.length).to.equal(2);
			expect(pendingOffers[0]).to.equal(expectedFirstOfferHash);
			expect(pendingOffers[1]).to.equal(expectedSecondOfferHash);
		});
	});

	describe("Delete offer", function() { // -> PWN is trusted source so we believe that it would not send invalid data
		it("Should fail when sender is not PWN contract", async function() {
			try {
				await deed.mint(0, 1, 100, addr2.address, 54, addr3.address);
				const tokenId = await deed.id();
				await deed.setOffer(0, 100, addr3.address, addr4.address, tokenId, 70);
				const pendingOffers = await deed.callStatic.getOffers(tokenId);

				await deed.connect(addr1).deleteOffer(pendingOffers[0]);

				expect().fail();
			} catch(error) {
				expect(error.message).to.contain("revert"); // TODO: Add reason?
			}
		});

		it("Should delete offer", async function() {
			await deed.mint(1, 1, 100, addr2.address, 54, addr3.address);
			const tokenId = await deed.id();
			await deed.setOffer(0, 100, addr3.address, addr4.address, tokenId, 70);
			const pendingOffers = await deed.callStatic.getOffers(tokenId);
			const offerHash = pendingOffers[0]

			await deed.deleteOffer(offerHash);

			const offer = await deed.offers(offerHash);
			expect(offer.asset.cat).to.equal(0);
			expect(offer.asset.amount).to.equal(0);
			expect(offer.asset.tokenAddress).to.equal(ethers.constants.AddressZero);
			expect(offer.toBePaid).to.equal(0);
			expect(offer.lender).to.equal(ethers.constants.AddressZero);
			expect(offer.deedID).to.equal(0);
		});

		it("Should delete pending offer"); // Not implemented yet
	});

	describe("Set credit", function() { // -> PWN is trusted source so we believe that it would not send invalid data
		it("Should fail when sender is not PWN contract", async function() {
			try {
				await deed.mint(0, 1, 100, addr2.address, 54, addr3.address);
				const tokenId = await deed.id();
				await deed.setOffer(0, 100, addr3.address, addr4.address, tokenId, 70);
				const pendingOffers = await deed.callStatic.getOffers(tokenId);

				await deed.connect(addr1).setCredit(tokenId, pendingOffers[0]);

				expect().fail();
			} catch(error) {
				expect(error.message).to.contain("revert"); // TODO: Add reason?
			}
		});

		it("Should set offer as accepted in deed", async function() {
			await deed.mint(0, 1, 100, addr2.address, 54, addr3.address);
			const tokenId = await deed.id();
			await deed.setOffer(0, 100, addr3.address, addr4.address, tokenId, 70);
			const pendingOffers = await deed.callStatic.getOffers(tokenId);

			await deed.setCredit(tokenId, pendingOffers[0]);

			const deedToken = await deed.deeds(tokenId);
			expect(deedToken.acceptedOffer).to.equal(pendingOffers[0]);
		});

		it("Should delete deed pending offers", async function() {
			await deed.mint(0, 1, 100, addr2.address, 54, addr3.address);
			const tokenId = await deed.id();
			await deed.setOffer(0, 100, addr3.address, addr4.address, tokenId, 70);
			const formerPendingOffers = await deed.callStatic.getOffers(tokenId);

			await deed.setCredit(tokenId, formerPendingOffers[0]);

			const latterPendingOffers = await deed.callStatic.getOffers(tokenId);
			expect(latterPendingOffers.length).to.equal(0);
		});
	});

	describe("Change status", function() { // -> PWN is trusted source so we believe that it would not send invalid data
		it("Should fail when sender is not PWN contract", async function() {
			try {
				await deed.mint(0, 1, 100, addr2.address, 54, addr3.address);
				const tokenId = await deed.id();

				await deed.connect(addr1).changeStatus(0, tokenId);

				expect().fail();
			} catch(error) {
				expect(error.message).to.contain("revert"); // TODO: Add reason?
			}
		});

		it("Should set deed state", async function() {
			await deed.mint(0, 1, 100, addr2.address, 54, addr3.address);
			const tokenId = await deed.id();

			await deed.changeStatus(8, tokenId);

			const deedToken = await deed.deeds(tokenId);
			expect(deedToken.status).to.equal(8);
		});
	});

	// should we test function beforeTokenTransfer??

	// VIEW FUNCTIONS - DEEDS

	describe("Get deed status", function() {
		it("Should return none/dead state", async function() {
			const lastBlockNumber = await ethers.provider.getBlockNumber();
			const lastBlock = await ethers.provider.getBlock(lastBlockNumber);
			const expiration = lastBlock.timestamp + parseInt(time.duration.days(7));
			await deed.mint(0, 1, 100, addr2.address, expiration, addr3.address);
			const tokenId = await deed.id();
			await deed.changeStatus(0, tokenId);

			const status = await deed.getDeedStatus(tokenId);

			expect(status).to.equal(0);
		});

		it("Should return new/open state", async function() {
			const lastBlockNumber = await ethers.provider.getBlockNumber();
			const lastBlock = await ethers.provider.getBlock(lastBlockNumber);
			const expiration = lastBlock.timestamp + parseInt(time.duration.days(7));
			await deed.mint(0, 1, 100, addr2.address, expiration, addr3.address);
			const tokenId = await deed.id();
			await deed.changeStatus(1, tokenId);

			const status = await deed.getDeedStatus(tokenId);

			expect(status).to.equal(1);
		});

		it("Should return running state", async function() {
			const lastBlockNumber = await ethers.provider.getBlockNumber();
			const lastBlock = await ethers.provider.getBlock(lastBlockNumber);
			const expiration = lastBlock.timestamp + parseInt(time.duration.days(7));
			await deed.mint(0, 1, 100, addr2.address, expiration, addr3.address);
			const tokenId = await deed.id();
			await deed.changeStatus(2, tokenId);

			const status = await deed.getDeedStatus(tokenId);

			expect(status).to.equal(2);
		});

		it("Should return paid back state when not expired", async function() {
			const lastBlockNumber = await ethers.provider.getBlockNumber();
			const lastBlock = await ethers.provider.getBlock(lastBlockNumber);
			const expiration = lastBlock.timestamp + parseInt(time.duration.days(7));
			await deed.mint(0, 1, 100, addr2.address, expiration, addr3.address);
			const tokenId = await deed.id();
			await deed.changeStatus(3, tokenId);

			const status = await deed.getDeedStatus(tokenId);

			expect(status).to.equal(3);
		});

		it("Should return paid back state when expired", async function() {
			await deed.mint(0, 1, 100, addr2.address, 54, addr3.address);
			const tokenId = await deed.id();
			await deed.changeStatus(3, tokenId);

			const status = await deed.getDeedStatus(tokenId);

			expect(status).to.equal(3);
		});

		it("Should return expired state", async function() {
			await deed.mint(0, 1, 100, addr2.address, 54, addr3.address);
			const tokenId = await deed.id();
			await deed.changeStatus(2, tokenId);

			const status = await deed.getDeedStatus(tokenId);

			expect(status).to.equal(4);
		});
	});

	describe("Get expiration", function() {
		it("Should return deed expiration", async function() {
			await deed.mint(0, 1, 100, addr2.address, 54, addr3.address);
			const tokenId = await deed.id();

			const expiration = await deed.getExpiration(tokenId);

			const deedToken = await deed.deeds(tokenId);
			expect(expiration).to.equal(deedToken.expiration);
		});
	});
	
	describe("Get borrower", function() {
		it("Should return borrower address", async function() {
			await deed.mint(0, 1, 100, addr2.address, 54, addr3.address);
			const tokenId = await deed.id();

			const borrower = await deed.getBorrower(tokenId);

			const deedToken = await deed.deeds(tokenId);
			expect(borrower).to.equal(deedToken.borrower);
		});
	});
	
	describe("Get deed asset", function() {
		it("Should return deed asset", async function() {
			await deed.mint(0, 1, 100, addr2.address, 54, addr3.address);
			const tokenId = await deed.id();

			const asset = await deed.getDeedAsset(tokenId);

			const deedToken = await deed.deeds(tokenId);
			expect(asset.cat).to.equal(deedToken.asset.cat);
			expect(asset.amount).to.equal(deedToken.asset.amount);
			expect(asset.id).to.equal(deedToken.asset.id);
			expect(asset.tokenAddress).to.equal(deedToken.asset.tokenAddress);
		});
	});

	describe("Get offers", function() {
		// Cannot get pendingOffers from deed.pendingOffers because `solc` generates incorrect ABI for implicit property getters with dynamic array
		// GH issue: https://github.com/ethereum/solidity/issues/4244
		it("Should return deed pending offers byte array");
	});

	describe("Get accepted offer", function() {
		it("Should return deed accepted offer", async function() {
			await deed.mint(0, 1, 100, addr2.address, 54, addr3.address);
			const tokenId = await deed.id();

			const acceptedOffer = await deed.getAcceptedOffer(tokenId);

			const deedToken = await deed.deeds(tokenId);
			expect(acceptedOffer).to.equal(deedToken.acceptedOffer);
		});
	});

	// VIEW FUNCTIONS - OFFERS

	describe("Get deed ID", function() {
		it("Should return deed ID", async function() {
			await deed.mint(0, 1, 100, addr2.address, 54, addr3.address);
			const tokenId = await deed.id();
			await deed.setOffer(0, 100, addr3.address, addr4.address, tokenId, 70);
			const pendingOffers = await deed.callStatic.getOffers(tokenId);
			const offerHash = pendingOffers[0];

			const deedId = await deed.getDeedID(offerHash);

			const offer = await deed.offers(offerHash)
			expect(deedId).to.equal(offer.deedID);
			expect(deedId).to.equal(tokenId);
		});
	});

	describe("Get offer asset", function() {
		it("Should return offer asset", async function() {
			await deed.mint(0, 1, 100, addr2.address, 54, addr3.address);
			const tokenId = await deed.id();
			await deed.setOffer(0, 100, addr3.address, addr4.address, tokenId, 70);
			const pendingOffers = await deed.callStatic.getOffers(tokenId);
			const offerHash = pendingOffers[0];

			const asset = await deed.getOfferAsset(offerHash);

			const offer = await deed.offers(offerHash);
			expect(asset.cat).to.equal(offer.asset.cat);
			expect(asset.amount).to.equal(offer.asset.amount);
			expect(asset.id).to.equal(offer.asset.id);
			expect(asset.tokenAddress).to.equal(offer.asset.tokenAddress);
		});
	});

	describe("To be paid", function() {
		it("Should return offer to be paid value", async function() {
			await deed.mint(0, 1, 100, addr2.address, 54, addr3.address);
			const tokenId = await deed.id();
			await deed.setOffer(0, 100, addr3.address, addr4.address, tokenId, 70);
			const pendingOffers = await deed.callStatic.getOffers(tokenId);
			const offerHash = pendingOffers[0];

			const toBePaid = await deed.toBePaid(offerHash);

			const offer = await deed.offers(offerHash);
			expect(toBePaid).to.equal(offer.toBePaid);
		});
	});

	describe("Get lender", function() {
		it("Should return lender address", async function() {
			await deed.mint(0, 1, 100, addr2.address, 54, addr3.address);
			const tokenId = await deed.id();
			await deed.setOffer(0, 100, addr3.address, addr4.address, tokenId, 70);
			const pendingOffers = await deed.callStatic.getOffers(tokenId);
			const offerHash = pendingOffers[0];

			const lender = await deed.getLender(offerHash);

			const offer = await deed.offers(offerHash);
			expect(lender).to.equal(offer.lender);
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
