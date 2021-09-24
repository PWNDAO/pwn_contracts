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
	let owner, addr1, addr2, addr3, addr4, addr5;

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
		PWN = await ethers.getContractFactory("PWN");
		[owner, addr1, addr2, addr3, addr4, addr5] = await ethers.getSigners();

		pwnEventIface = new ethers.utils.Interface([
		    "event MinDurationChange(uint256 minDuration)",
		]);
	});

	beforeEach(async function() {
		vaultFake = await smock.fake("PWNVault");
		deedFake = await smock.fake("PWNDeed");
		pwn = await PWN.deploy(deedFake.address, vaultFake.address);
		await pwn.changeMinDuration(100);
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
			const deedAddress = await pwn.token();
			expect(vaultAddress).to.equal(vaultFake.address);
			expect(deedAddress).to.equal(deedFake.address);
		});
	});

	describe("New deed", function() {
		it("Should be able to create ERC20 deed", async function() {
			const amount = 10;
			const fakeToken = await smock.fake("Basic20");
			const expiration = await getExpiration(110);

			await pwn.newDeed(fakeToken.address, CATEGORY.ERC20, 0, amount, expiration);
			//TODO: add expected result
		});

		it("Should be able to create ERC721 deed", async function() {
			const tokenId = 10;
			const fakeToken = await smock.fake("Basic721");
			const expiration = await getExpiration(110);

			await pwn.newDeed(fakeToken.address, CATEGORY.ERC721, tokenId, 1, expiration);
			//TODO: add expected result
		});

		it("Should be able to create ERC1155 deed", async function() {
			const tokenId = 10;
			const fakeToken = await smock.fake("Basic1155");
			const expiration = await getExpiration(110);

			await pwn.newDeed(fakeToken.address, CATEGORY.ERC1155, tokenId, 5, expiration);
			//TODO: add expected result
		});

		it("Should fail for unknown asset category", async function() {
			let failed;

			try {
				await pwn.newDeed(addr4.address, CATEGORY.unknown, 0, 10, 1);
			} catch {
				failed = true;
			}

			expect(failed).to.equal(true);
		});

		it("Should fail for expiration duration smaller than min duration", async function() {
			const expiration = getExpiration(90);

			try {
				await pwn.newDeed(addr4.address, CATEGORY.ERC20, 0, 10, expiration);
				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert"); // TODO: Add reason?
			}
		});

		it("Should return newly created deed ID", async function() {
			const fakeToken = await smock.fake("Basic20");
			const expiration = await getExpiration(110);
			const fakeDid = 3;
			deedFake.create.returns(fakeDid);

			const did = await pwn.callStatic.newDeed(fakeToken.address, CATEGORY.ERC20, 0, 10, expiration);

			expect(did).to.equal(fakeDid);
		});

		it("Should send borrower collateral to vault", async function() {
			const amount = 10;
			const fakeToken = await smock.fake("Basic20");
			const expiration = await getExpiration(110);
			deedFake.getDeedAsset.returns({
				cat: 0,
				id: 0,
				amount: amount,
				tokenAddress: fakeToken.address,
			});

			await pwn.connect(addr1).newDeed(fakeToken.address, CATEGORY.ERC20, 0, amount, expiration);

			expect(vaultFake.push).to.have.been.calledOnce;
			const args = vaultFake.push.getCall(0).args;
			expect(args._asset.cat).to.equal(CATEGORY.ERC20);
			expect(args._asset.amount).to.equal(amount);
			expect(args._asset.id).to.equal(0);
			expect(args._asset.tokenAddress).to.equal(fakeToken.address);
			expect(args._origin).to.equal(addr1.address);
		});
	});

	describe("Revoke deed", function() {
		const did = 17;
		const amount = 120;
		let fakeToken;

		before(async function() {
			fakeToken = await smock.fake("Basic20");
		});

		beforeEach(async function() {
			deedFake.getDeedAsset.whenCalledWith(did).returns({
				cat: CATEGORY.ERC20,
				id: 0,
				amount: amount,
				tokenAddress: fakeToken.address,
			});
			vaultFake.pull.returns(true);
		});

		it("Should update deed to revoked state", async function() {
			await pwn.connect(addr1).revokeDeed(did);

			expect(deedFake.revoke).to.have.been.calledOnceWith(did, addr1.address);
		});

		it("Should send deed collateral to borrower from vault", async function() {
			await pwn.connect(addr1).revokeDeed(did);

			expect(vaultFake.pull).to.have.been.calledOnce;
			expect(vaultFake.pull).to.have.been.calledAfter(deedFake.revoke);
			const asset = vaultFake.pull.getCall(0).args._asset;
			expect(asset.cat).to.equal(CATEGORY.ERC20);
			expect(asset.amount).to.equal(amount);
			expect(asset.id).to.equal(0);
			expect(asset.tokenAddress).to.equal(fakeToken.address);
			const beneficiary = vaultFake.pull.getCall(0).args._beneficiary;
			expect(beneficiary).to.equal(addr1.address);
		});

		it("Should burn deed token", async function() {
			await pwn.connect(addr1).revokeDeed(did);

			expect(deedFake.burn).to.have.been.calledOnceWith(did, addr1.address);
			expect(deedFake.burn).to.have.been.calledAfter(vaultFake.pull);
			expect(deedFake.burn).to.have.been.calledAfter(deedFake.revoke);
		});
	});

	describe("Make offer", function() {
		const did = 367;
		const amount = 8;
		const toBePaid = 12;
		const offerHash = "0x0987654321098765432109876543210987654321098765432109876543210000";
		let fakeToken;

		before(async function() {
			fakeToken = await smock.fake("Basic20");
		});

		beforeEach(async function() {
			deedFake.makeOffer.returns(offerHash);
		});

		it("Should be able to make ERC20 offer", async function() {
			await pwn.connect(addr2).makeOffer(fakeToken.address, CATEGORY.ERC20, amount, did, toBePaid);

			expect(deedFake.makeOffer).to.have.been.calledOnceWith(fakeToken.address, CATEGORY.ERC20, amount, addr2.address, did, toBePaid);
		});

		it("Should be able to make ERC721 offer", async function() {
			await pwn.connect(addr2).makeOffer(fakeToken.address, CATEGORY.ERC721, 1, did, 1);

			expect(deedFake.makeOffer).to.have.been.calledOnceWith(fakeToken.address, CATEGORY.ERC721, 1, addr2.address, did, 1);
		});

		it("Should be able to make ERC1155 offer", async function() {
			await pwn.connect(addr2).makeOffer(fakeToken.address, CATEGORY.ERC1155, amount, did, toBePaid);

			expect(deedFake.makeOffer).to.have.been.calledOnceWith(fakeToken.address, CATEGORY.ERC1155, amount, addr2.address, did, toBePaid);
		});

		it("Should fail for unknown asset category", async function() {
			let failed;

			try {
				await pwn.makeOffer(fakeToken.address, CATEGORY.unknown, 1, did, 2);
			} catch {
				failed = true;
			}

			expect(failed).to.equal(true);
		});

		it("Should return new offer hash", async function() {
			const offer = await pwn.callStatic.makeOffer(fakeToken.address, CATEGORY.ERC20, 9, did, 10);

			expect(offer).to.equal(offerHash);
		});
	});

	describe("Revoke offer", function() {
		const offerHash = "0x6732801029378ddf837210000397c68129387fd887839708320980942102910a";

		it("Should revoke offer on deed", async function() {
			await pwn.connect(addr3).revokeOffer(offerHash);

			expect(deedFake.revokeOffer).to.have.been.calledOnceWith(offerHash, addr3.address);
		});
	});

	describe("Accept offer", function() {
		const did = 3456789;
		const amount = 1000;
		const offerHash = "0xaaa7654321098765abcde98765432109876543210987eff32109f76543a100cc";
		let fakeToken;

		before(async function() {
			fakeToken = await smock.fake("Basic20");
		});

		beforeEach(async function() {
			deedFake.getDeedID.whenCalledWith(offerHash).returns(did);
			deedFake.getLender.whenCalledWith(offerHash).returns(addr4.address);
			deedFake.getOfferAsset.whenCalledWith(offerHash).returns({
				cat: CATEGORY.ERC20,
				id: 0,
				amount: amount,
				tokenAddress: fakeToken.address,
			});
			vaultFake.pullProxy.returns(true);
		});

		it("Should update deed to accepted offer state", async function() {
			await pwn.connect(addr3).acceptOffer(offerHash);

			expect(deedFake.acceptOffer).to.have.been.calledOnceWith(did, offerHash, addr3.address);
		});

		it("Should send lender asset to borrower", async function() {
			await pwn.connect(addr3).acceptOffer(offerHash);

			const args = vaultFake.pullProxy.getCall(0).args;
			expect(args._asset.cat).to.equal(CATEGORY.ERC20);
			expect(args._asset.id).to.equal(0);
			expect(args._asset.amount).to.equal(amount);
			expect(args._asset.tokenAddress).to.equal(fakeToken.address);
			expect(args._origin).to.equal(addr4.address);
			expect(args._beneficiary).to.equal(addr3.address);
			expect(vaultFake.pullProxy).to.have.been.calledAfter(deedFake.acceptOffer);
		});

		it("Should send deed token to lender", async function() {
			await pwn.connect(addr3).acceptOffer(offerHash);

			const args = vaultFake.pullProxy.getCall(1).args;
			expect(args._asset.cat).to.equal(CATEGORY.ERC1155);
			expect(args._asset.id).to.equal(did);
			expect(args._asset.amount).to.equal(0);
			expect(args._asset.tokenAddress).to.equal(deedFake.address);
			expect(args._origin).to.equal(addr3.address);
			expect(args._beneficiary).to.equal(addr4.address);
			expect(vaultFake.pullProxy).to.have.been.calledAfter(deedFake.acceptOffer);
		});

		it("Should return true if successful", async function() {
			const success = await pwn.connect(addr3).callStatic.acceptOffer(offerHash);

			expect(success).to.equal(true);
		});
	});

	describe("Pay back", function() {
		const did = 536;
		const amount = 1000;
		const toBePaid = 1200;
		const offerHash = "0xaaa7654321098765abcdeabababababababababa0987eff32109f76543a1aacc";
		let fakeCreditToken;
		let fakeCollateralToken;
		let credit;
		let collateral;

		before(async function() {
			fakeCreditToken = await smock.fake("Basic20");
			fakeCollateralToken = await smock.fake("Basic721");
			credit = {
				cat: CATEGORY.ERC20,
				id: 0,
				amount: amount,
				tokenAddress: fakeCreditToken.address,
			};
			collateral = {
				cat: CATEGORY.ERC721,
				id: 123,
				amount: 1,
				tokenAddress: fakeCollateralToken.address,
			};
		});

		beforeEach(async function() {
			deedFake.getAcceptedOffer.whenCalledWith(did).returns(offerHash);
			deedFake.toBePaid.whenCalledWith(offerHash).returns(toBePaid);
			deedFake.getOfferAsset.whenCalledWith(offerHash).returns(credit);
			deedFake.getDeedAsset.returns(collateral);
			deedFake.getBorrower.whenCalledWith(did).returns(addr3.address);
			vaultFake.pull.returns(true);
			vaultFake.push.returns(true);
		});

		it("Should update deed to paid back state", async function() {
			await pwn.connect(addr3).payBack(did);

			expect(deedFake.payBack).to.have.been.calledOnceWith(did);
		});

		it("Should send deed collateral from vault to borrower", async function() {
			await pwn.connect(addr3).payBack(did);

			const args = vaultFake.pull.getCall(0).args;
			expect(args._asset.cat).to.equal(collateral.cat);
			expect(args._asset.id).to.equal(collateral.id);
			expect(args._asset.amount).to.equal(collateral.amount);
			expect(args._asset.tokenAddress).to.equal(collateral.tokenAddress);
			expect(args._beneficiary).to.equal(addr3.address);
			expect(vaultFake.pull).to.have.been.calledAfter(deedFake.payBack);
		});

		it("Should send paid back amount from borrower to vault", async function() {
			await pwn.connect(addr3).payBack(did);

			const args = vaultFake.push.getCall(0).args;
			expect(args._asset.cat).to.equal(credit.cat);
			expect(args._asset.id).to.equal(credit.id);
			expect(args._asset.amount).to.equal(toBePaid);
			expect(args._asset.tokenAddress).to.equal(credit.tokenAddress);
			expect(args._origin).to.equal(addr3.address);
			expect(vaultFake.push).to.have.been.calledAfter(deedFake.payBack);
		});

		it("Should return true if successful", async function() {
			const success = await pwn.connect(addr3).callStatic.payBack(did);

			expect(success).to.equal(true);
		});
	});

	describe("Claim deed", function() {
		const did = 987;
		const amount = 1234;
		const toBePaid = 4321;
		const offerHash = "0xaaa7654321098765abcdeabababababababababa0987eff32109f76543a1aacc";
		let fakeCreditToken;
		let fakeCollateralToken;
		let credit;
		let collateral;

		before(async function() {
			fakeCreditToken = await smock.fake("Basic20");
			fakeCollateralToken = await smock.fake("Basic721");
			credit = {
				cat: CATEGORY.ERC20,
				id: 0,
				amount: amount,
				tokenAddress: fakeCreditToken.address,
			};
			collateral = {
				cat: CATEGORY.ERC721,
				id: 123,
				amount: 1,
				tokenAddress: fakeCollateralToken.address,
			};
		});

		beforeEach(async function() {
			deedFake.getDeedStatus.whenCalledWith(did).returns(3);
			deedFake.getAcceptedOffer.whenCalledWith(did).returns(offerHash);
			deedFake.toBePaid.whenCalledWith(offerHash).returns(toBePaid);
			deedFake.getOfferAsset.whenCalledWith(offerHash).returns(credit);
			deedFake.getDeedAsset.returns(collateral);
			vaultFake.pull.returns(true);
		});

		it("Should update deed to claimed state", async function() {
			await pwn.connect(addr3).claimDeed(did);

			expect(deedFake.claim).to.have.been.calledOnceWith(did, addr3.address);
		});

		it("Should send collateral from vault to lender when deed is expired", async function() {
			deedFake.getDeedStatus.whenCalledWith(did).returns(4);

			await pwn.connect(addr3).claimDeed(did);

			expect(vaultFake.pull).to.have.been.calledOnce;
			expect(vaultFake.pull).to.have.been.calledAfter(deedFake.claim);
			const args = vaultFake.pull.getCall(0).args;
			expect(args._asset.cat).to.equal(collateral.cat);
			expect(args._asset.id).to.equal(collateral.id);
			expect(args._asset.amount).to.equal(collateral.amount);
			expect(args._asset.tokenAddress).to.equal(collateral.tokenAddress);
			expect(args._beneficiary).to.equal(addr3.address);
		});

		it("Should send paid back amount from vault to lender when deed is paid back", async function() {
			deedFake.getDeedStatus.whenCalledWith(did).returns(3);

			await pwn.connect(addr3).claimDeed(did);

			expect(vaultFake.pull).to.have.been.calledOnce;
			expect(vaultFake.pull).to.have.been.calledAfter(deedFake.claim);
			const args = vaultFake.pull.getCall(0).args;
			expect(args._asset.cat).to.equal(credit.cat);
			expect(args._asset.id).to.equal(credit.id);
			expect(args._asset.amount).to.equal(toBePaid);
			expect(args._asset.tokenAddress).to.equal(credit.tokenAddress);
		});

		it("Should burn deed token", async function() {
			await pwn.connect(addr3).claimDeed(did);

			expect(deedFake.burn).to.have.been.calledOnceWith(did, addr3.address);
			expect(deedFake.burn).to.have.been.calledAfter(vaultFake.pull);
		});

		it("Should return true if successful", async function() {
			const success = await pwn.connect(addr3).callStatic.claimDeed(did);

			expect(success).to.equal(true);
		});
	});

	describe("Change min duration", function() {
		it("Should fail when sender is not owner", async function() {
			try {
				await pwn.connect(addr1).changeMinDuration(1);
				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Ownable: caller is not the owner");
			}
		});

		it("Should set new min duration", async function() {
			const newMinDuration = 76543;

			await pwn.connect(owner).changeMinDuration(newMinDuration);

			const minDuration = await pwn.minDuration();
			expect(minDuration).to.equal(newMinDuration);
		});

		it("Should emit MinDurationChange event", async function() {
			const minDuration = 76543;

			const tx = await pwn.connect(owner).changeMinDuration(minDuration);
			const response = await tx.wait();

			expect(response.logs.length).to.equal(1);
			const logDescription = pwnEventIface.parseLog(response.logs[0]);
			expect(logDescription.name).to.equal("MinDurationChange");
			const args = logDescription.args;
			expect(args.minDuration).to.equal(minDuration);
		});
	});

});
