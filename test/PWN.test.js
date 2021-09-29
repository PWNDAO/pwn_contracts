const chai = require("chai");
const { ethers } = require("hardhat");
const { smock } = require("@defi-wonderland/smock");
const { time } = require('@openzeppelin/test-helpers');

const expect = chai.expect;
chai.use(smock.matchers);

describe("PWN contract", function() {

	let pwn;
	let vaultFake;
	let deedFake;

	let PWN;
	let pwnEventIface;
	let owner, lender, borrower, asset1, asset2, addr1;

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
		PWN = await ethers.getContractFactory("PWN");
		[owner, lender, borrower, asset1, asset2, addr1] = await ethers.getSigners();
	});

	beforeEach(async function() {
		vaultFake = await smock.fake("PWNVault");
		deedFake = await smock.fake("PWNDeed");
		pwn = await PWN.deploy(deedFake.address, vaultFake.address);
	});


	describe("Constructor", function() {

		it("Should set correct owner", async function() {
			const factory = await ethers.getContractFactory("PWN");

			pwn = await factory.connect(addr1).deploy(deedFake.address, vaultFake.address);

			const contractOwner = await pwn.owner();
			expect(addr1.address).to.equal(contractOwner);
		});

		it("Should set correct contract addresses", async function() {
			const factory = await ethers.getContractFactory("PWN");

			pwn = await factory.deploy(deedFake.address, vaultFake.address);

			const vaultAddress = await pwn.vault();
			const deedAddress = await pwn.deed();
			expect(vaultAddress).to.equal(vaultFake.address);
			expect(deedAddress).to.equal(deedFake.address);
		});

	});


	describe("New deed", function() {

		it("Should be able to create ERC20 deed", async function() {
			const expiration = await timestampFromNow(110);
			let failed = false;

			try {
				await pwn.newDeed(asset1.address, CATEGORY.ERC20, 0, 10, expiration);
			} catch {
				failed = true;
			}

			expect(failed).to.equal(false);
		});

		it("Should be able to create ERC721 deed", async function() {
			const expiration = await timestampFromNow(110);
			let failed = false;

			try {
				await pwn.newDeed(asset1.address, CATEGORY.ERC721, 10, 1, expiration);
			} catch {
				failed = true;
			}

			expect(failed).to.equal(false);
		});

		it("Should be able to create ERC1155 deed", async function() {
			const expiration = await timestampFromNow(110);
			let failed = false;

			try {
				await pwn.newDeed(asset1.address, CATEGORY.ERC1155, 10, 5, expiration);
			} catch {
				failed = true;
			}

			expect(failed).to.equal(false);
		});

		it("Should fail for unknown asset category", async function() {
			let failed;

			try {
				await pwn.newDeed(asset1.address, CATEGORY.unknown, 0, 10, 1);
			} catch {
				failed = true;
			}

			expect(failed).to.equal(true);
		});

		it("Should fail for expiration timestamp smaller than current timestamp", async function() {
			const expiration = timestampFromNow(-1);

			try {
				await pwn.newDeed(asset1.address, CATEGORY.ERC20, 0, 10, expiration);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Cannot create expired deed");
			}
		});

		it("Should return newly created deed ID", async function() {
			const expiration = await timestampFromNow(110);
			const fakeDid = 3;
			deedFake.create.returns(fakeDid);

			const did = await pwn.callStatic.newDeed(asset1.address, CATEGORY.ERC20, 0, 10, expiration);

			expect(did).to.equal(fakeDid);
		});

		it("Should send borrower collateral to vault", async function() {
			const expiration = await timestampFromNow(110);
			const collateral = {
				assetAddress: asset1.address,
				category: CATEGORY.ERC20,
				id: 1,
				amount: 10,
			};
			deedFake.getDeedCollateral.returns(collateral);

			await pwn.connect(borrower).newDeed(collateral.assetAddress, collateral.category, collateral.id, collateral.amount, expiration);

			expect(vaultFake.push).to.have.been.calledOnce;
			const args = vaultFake.push.getCall(0).args;
			expect(args._asset.assetAddress).to.equal(collateral.assetAddress);
			expect(args._asset.category).to.equal(collateral.category);
			expect(args._asset.id).to.equal(collateral.id);
			expect(args._asset.amount).to.equal(collateral.amount);
			expect(args._origin).to.equal(borrower.address);
		});

	});


	describe("Revoke deed", function() {

		const did = 17;
		const amount = 120;
		const assetId = 8;

		beforeEach(async function() {
			vaultFake.pull.returns(true);
		});


		it("Should update deed to revoked state", async function() {
			await pwn.connect(borrower).revokeDeed(did);

			expect(deedFake.revoke).to.have.been.calledOnceWith(did, borrower.address);
		});

		it("Should send deed collateral to borrower from vault", async function() {
			const collateral = {
				assetAddress: asset1.address,
				category: CATEGORY.ERC20,
				id: assetId,
				amount: amount,
			};
			deedFake.getDeedCollateral.whenCalledWith(did).returns(collateral);

			await pwn.connect(borrower).revokeDeed(did);

			expect(vaultFake.pull).to.have.been.calledOnce;
			expect(vaultFake.pull).to.have.been.calledAfter(deedFake.revoke);
			const asset = vaultFake.pull.getCall(0).args._asset;
			expect(asset.assetAddress).to.equal(collateral.assetAddress);
			expect(asset.category).to.equal(collateral.category);
			expect(asset.id).to.equal(collateral.id);
			expect(asset.amount).to.equal(collateral.amount);
			const beneficiary = vaultFake.pull.getCall(0).args._beneficiary;
			expect(beneficiary).to.equal(borrower.address);
		});

		it("Should burn deed token", async function() {
			await pwn.connect(borrower).revokeDeed(did);

			expect(deedFake.burn).to.have.been.calledOnceWith(did, borrower.address);
			expect(deedFake.burn).to.have.been.calledAfter(vaultFake.pull);
			expect(deedFake.burn).to.have.been.calledAfter(deedFake.revoke);
		});

	});


	describe("Make offer", function() {

		const did = 367;
		const amount = 8;
		const toBePaid = 12;
		const offerHash = "0x0987654321098765432109876543210987654321098765432109876543210000";

		beforeEach(async function() {
			deedFake.makeOffer.returns(offerHash);
		});


		it("Should be able to make ERC20 offer", async function() {
			await pwn.connect(lender).makeOffer(asset1.address, CATEGORY.ERC20, amount, did, toBePaid);

			expect(deedFake.makeOffer).to.have.been.calledOnceWith(asset1.address, CATEGORY.ERC20, amount, lender.address, did, toBePaid);
		});

		it("Should be able to make ERC721 offer", async function() {
			await pwn.connect(lender).makeOffer(asset1.address, CATEGORY.ERC721, 1, did, 1);

			expect(deedFake.makeOffer).to.have.been.calledOnceWith(asset1.address, CATEGORY.ERC721, 1, lender.address, did, 1);
		});

		it("Should be able to make ERC1155 offer", async function() {
			await pwn.connect(lender).makeOffer(asset1.address, CATEGORY.ERC1155, amount, did, toBePaid);

			expect(deedFake.makeOffer).to.have.been.calledOnceWith(asset1.address, CATEGORY.ERC1155, amount, lender.address, did, toBePaid);
		});

		it("Should fail for unknown asset category", async function() {
			let failed;

			try {
				await pwn.connect(lender).makeOffer(asset1.address, CATEGORY.unknown, 1, did, 2);
			} catch {
				failed = true;
			}

			expect(failed).to.equal(true);
		});

		it("Should return new offer hash", async function() {
			const offer = await pwn.callStatic.makeOffer(asset1.address, CATEGORY.ERC20, 9, did, 10);

			expect(offer).to.equal(offerHash);
		});

	});


	describe("Revoke offer", function() {

		const offerHash = "0x6732801029378ddf837210000397c68129387fd887839708320980942102910a";

		it("Should revoke offer on deed", async function() {
			await pwn.connect(lender).revokeOffer(offerHash);

			expect(deedFake.revokeOffer).to.have.been.calledOnceWith(offerHash, lender.address);
		});

	});


	describe("Accept offer", function() {

		const did = 3456789;
		const amount = 1000;
		const assetId = 32;
		const offerHash = "0xaaa7654321098765abcde98765432109876543210987eff32109f76543a100cc";

		beforeEach(async function() {
			deedFake.getDeedID.whenCalledWith(offerHash).returns(did);
			deedFake.getLender.whenCalledWith(offerHash).returns(lender.address);
			deedFake.getOfferCredit.whenCalledWith(offerHash).returns({
				assetAddress: asset1.address,
				category: CATEGORY.ERC20,
				id: assetId,
				amount: amount,
			});
			vaultFake.pullProxy.returns(true);
		});


		it("Should update deed to accepted offer state", async function() {
			await pwn.connect(borrower).acceptOffer(offerHash);

			expect(deedFake.acceptOffer).to.have.been.calledOnceWith(did, offerHash, borrower.address);
		});

		it("Should send lender asset to borrower", async function() {
			await pwn.connect(borrower).acceptOffer(offerHash);

			const args = vaultFake.pullProxy.getCall(0).args;
			expect(args._asset.assetAddress).to.equal(asset1.address);
			expect(args._asset.category).to.equal(CATEGORY.ERC20);
			expect(args._asset.id).to.equal(assetId);
			expect(args._asset.amount).to.equal(amount);
			expect(args._origin).to.equal(lender.address);
			expect(args._beneficiary).to.equal(borrower.address);
			expect(vaultFake.pullProxy).to.have.been.calledAfter(deedFake.acceptOffer);
		});

		it("Should send deed token to lender", async function() {
			await pwn.connect(borrower).acceptOffer(offerHash);

			const args = vaultFake.pullProxy.getCall(1).args;
			expect(args._asset.assetAddress).to.equal(deedFake.address);
			expect(args._asset.category).to.equal(CATEGORY.ERC1155);
			expect(args._asset.id).to.equal(did);
			expect(args._asset.amount).to.equal(0);
			expect(args._origin).to.equal(borrower.address);
			expect(args._beneficiary).to.equal(lender.address);
			expect(vaultFake.pullProxy).to.have.been.calledAfter(deedFake.acceptOffer);
		});

		it("Should return true if successful", async function() {
			const success = await pwn.connect(borrower).callStatic.acceptOffer(offerHash);

			expect(success).to.equal(true);
		});

	});

	describe("Pay back", function() {

		const did = 536;
		const amount = 1000;
		const toBePaid = 1200;
		const offerHash = "0xaaa7654321098765abcdeabababababababababa0987eff32109f76543a1aacc";
		let credit;
		let collateral;

		before(function() {
			credit = {
				assetAddress: asset1.address,
				category: CATEGORY.ERC20,
				id: 0,
				amount: amount,
			};
			collateral = {
				assetAddress: asset2.address,
				category: CATEGORY.ERC721,
				id: 123,
				amount: 1,
			};
		});

		beforeEach(async function() {
			deedFake.getAcceptedOffer.whenCalledWith(did).returns(offerHash);
			deedFake.toBePaid.whenCalledWith(offerHash).returns(toBePaid);
			deedFake.getOfferCredit.whenCalledWith(offerHash).returns(credit);
			deedFake.getDeedCollateral.whenCalledWith(did).returns(collateral);
			deedFake.getBorrower.whenCalledWith(did).returns(borrower.address);
			vaultFake.pull.returns(true);
			vaultFake.push.returns(true);
		});


		it("Should update deed to paid back state", async function() {
			await pwn.connect(borrower).payBack(did);

			expect(deedFake.payBack).to.have.been.calledOnceWith(did);
		});

		it("Should send deed collateral from vault to borrower", async function() {
			await pwn.connect(borrower).payBack(did);

			const args = vaultFake.pull.getCall(0).args;
			expect(args._asset.assetAddress).to.equal(collateral.assetAddress);
			expect(args._asset.category).to.equal(collateral.category);
			expect(args._asset.id).to.equal(collateral.id);
			expect(args._asset.amount).to.equal(collateral.amount);
			expect(args._beneficiary).to.equal(borrower.address);
			expect(vaultFake.pull).to.have.been.calledAfter(deedFake.payBack);
		});

		it("Should send paid back amount from borrower to vault", async function() {
			await pwn.connect(borrower).payBack(did);

			const args = vaultFake.push.getCall(0).args;
			expect(args._asset.assetAddress).to.equal(credit.assetAddress);
			expect(args._asset.category).to.equal(credit.category);
			expect(args._asset.id).to.equal(credit.id);
			expect(args._asset.amount).to.equal(toBePaid);
			expect(args._origin).to.equal(borrower.address);
			expect(vaultFake.push).to.have.been.calledAfter(deedFake.payBack);
		});

		it("Should return true if successful", async function() {
			const success = await pwn.connect(borrower).callStatic.payBack(did);

			expect(success).to.equal(true);
		});

	});


	describe("Claim deed", function() {

		const did = 987;
		const amount = 1234;
		const toBePaid = 4321;
		const offerHash = "0xaaa7654321098765abcdeabababababababababa0987eff32109f76543a1aacc";
		let credit;
		let collateral;

		before(function() {
			credit = {
				assetAddress: asset1.address,
				category: CATEGORY.ERC20,
				id: 0,
				amount: amount,
			};
			collateral = {
				assetAddress: asset2.address,
				category: CATEGORY.ERC721,
				id: 123,
				amount: 1,
			};
		});


		beforeEach(async function() {
			deedFake.getDeedStatus.whenCalledWith(did).returns(3);
			deedFake.getAcceptedOffer.whenCalledWith(did).returns(offerHash);
			deedFake.toBePaid.whenCalledWith(offerHash).returns(toBePaid);
			deedFake.getOfferCredit.whenCalledWith(offerHash).returns(credit);
			deedFake.getDeedCollateral.whenCalledWith(did).returns(collateral);
			vaultFake.pull.returns(true);
		});


		it("Should update deed to claimed state", async function() {
			await pwn.connect(lender).claimDeed(did);

			expect(deedFake.claim).to.have.been.calledOnceWith(did, lender.address);
		});

		it("Should send collateral from vault to lender when deed is expired", async function() {
			deedFake.getDeedStatus.whenCalledWith(did).returns(4);

			await pwn.connect(lender).claimDeed(did);

			expect(vaultFake.pull).to.have.been.calledOnce;
			expect(vaultFake.pull).to.have.been.calledAfter(deedFake.claim);
			const args = vaultFake.pull.getCall(0).args;
			expect(args._asset.assetAddress).to.equal(collateral.assetAddress);
			expect(args._asset.category).to.equal(collateral.category);
			expect(args._asset.id).to.equal(collateral.id);
			expect(args._asset.amount).to.equal(collateral.amount);
			expect(args._beneficiary).to.equal(lender.address);
		});

		it("Should send paid back amount from vault to lender when deed is paid back", async function() {
			deedFake.getDeedStatus.whenCalledWith(did).returns(3);

			await pwn.connect(lender).claimDeed(did);

			expect(vaultFake.pull).to.have.been.calledOnce;
			expect(vaultFake.pull).to.have.been.calledAfter(deedFake.claim);
			const args = vaultFake.pull.getCall(0).args;
			expect(args._asset.assetAddress).to.equal(credit.assetAddress);
			expect(args._asset.category).to.equal(credit.category);
			expect(args._asset.id).to.equal(credit.id);
			expect(args._asset.amount).to.equal(toBePaid);
		});

		it("Should burn deed token", async function() {
			await pwn.connect(lender).claimDeed(did);

			expect(deedFake.burn).to.have.been.calledOnceWith(did, lender.address);
			expect(deedFake.burn).to.have.been.calledAfter(vaultFake.pull);
		});

		it("Should return true if successful", async function() {
			const success = await pwn.connect(lender).callStatic.claimDeed(did);

			expect(success).to.equal(true);
		});

	});

});
