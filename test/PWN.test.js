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

	before(async function() {
		PWN = await ethers.getContractFactory("PWN");
		[owner, addr1, addr2, addr3, addr4, addr5] = await ethers.getSigners();

		pwnEventIface = new ethers.utils.Interface([
			"event NewDeed(uint8 cat, uint256 id, uint256 amount, address indexed tokenAddress, uint256 expiration, uint256 indexed did)",
		    "event NewOffer(uint8 cat, uint256 amount, address tokenAddress, address indexed lender, uint256 toBePaid, uint256 indexed did, bytes32 offer)",
		    "event DeedRevoked(uint256 did)",
		    "event OfferRevoked(bytes32 offer)",
		    "event OfferAccepted(uint256 did, bytes32 offer)",
		    "event PaidBack(uint256 did, bytes32 offer)",
		    "event DeedClaimed(uint256 did)",
		    "event MinDurationChange(uint256 minDuration)"
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

			await pwn.newDeed(0, 0, amount, fakeToken.address, expiration);
			//TODO: add expected result
		});

		it("Should be able to create ERC721 deed", async function() {
			const tokenId = 10;
			const fakeToken = await smock.fake("Basic721");
			const expiration = await getExpiration(110);

			await pwn.newDeed(1, tokenId, 1, fakeToken.address, expiration);
			//TODO: add expected result
		});

		it("Should be able to create ERC1155 deed", async function() {
			const tokenId = 10;
			const fakeToken = await smock.fake("Basic1155");
			const expiration = await getExpiration(110);

			await pwn.newDeed(2, tokenId, 5, fakeToken.address, expiration);
			//TODO: add expected result
		});

		it("Should fail for unknown asset category", async function() {
			try {
				await pwn.newDeed(3, 0, 10, addr4.address, 1);
				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Unknown asset type");
			}
		});

		it("Should fail for expiration duration smaller than min duration", async function() {
			const expiration = getExpiration(90);

			try {
				await pwn.newDeed(0, 0, 10, addr4.address, expiration);
				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert"); // TODO: Add reason?
			}
		});

		it("Should emit NewDeed event", async function() {
			const amount = 10;
			const fakeToken = await smock.fake("Basic20");
			const expiration = await getExpiration(110);
			const fakeDid = 3;
			deedFake.mint.returns(fakeDid);

			const tx = await pwn.newDeed(0, 0, amount, fakeToken.address, expiration);
			const response = await tx.wait();

			expect(response.logs.length).to.equal(1);
			const logDescription = pwnEventIface.parseLog(response.logs[0]);
			expect(logDescription.name).to.equal("NewDeed");
			expect(logDescription.args.cat).to.equal(0);
			expect(logDescription.args.id).to.equal(0);
			expect(logDescription.args.amount).to.equal(amount);
			expect(logDescription.args.tokenAddress).to.equal(fakeToken.address);
			expect(logDescription.args.expiration).to.equal(expiration);
			expect(logDescription.args.did).to.equal(fakeDid);
		});

		it("Should return newly created deed ID", async function() {
			const fakeToken = await smock.fake("Basic20");
			const expiration = await getExpiration(110);
			const fakeDid = 3;
			deedFake.mint.returns(fakeDid);

			const did = await pwn.callStatic.newDeed(0, 0, 10, fakeToken.address, expiration);

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

			await pwn.newDeed(0, 0, amount, fakeToken.address, expiration);

			expect(vaultFake.push).to.have.been.calledOnce;
			const asset = vaultFake.push.getCall(0).args._asset;
			expect(asset.cat).to.equal(0);
			expect(asset.amount).to.equal(amount);
			expect(asset.id).to.equal(0);
			expect(asset.tokenAddress).to.equal(fakeToken.address);
		});

		it("Should mint new deed in correct state", async function() {
			const amount = 10;
			const fakeToken = await smock.fake("Basic20");
			const expiration = await getExpiration(110);
			const fakeDid = 3;
			deedFake.mint.returns(fakeDid);

			await pwn.connect(addr1).newDeed(0, 0, amount, fakeToken.address, expiration);

			expect(deedFake.mint).to.have.been.calledOnceWith(0, 0, amount, fakeToken.address, expiration, addr1.address);
			expect(deedFake.changeStatus).to.have.been.calledOnceWith(1, fakeDid);
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
			deedFake.getBorrower.whenCalledWith(did).returns(addr1.address);
			deedFake.getDeedStatus.whenCalledWith(did).returns(1);
			deedFake.getDeedAsset.whenCalledWith(did).returns({
				cat: 0,
				id: 0,
				amount: amount,
				tokenAddress: fakeToken.address,
			});
			vaultFake.pull.returns(true);
		});

		it("Should fail when sender is not borrower", async function() {
			try {
				await pwn.connect(addr2).revokeDeed(did);
				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("The deed doesn't belong to the caller");
			}
		});

		it("Should fail when deed is not in new/open state", async function() {
			deedFake.getDeedStatus.whenCalledWith(did).returns(2);

			try {
				await pwn.connect(addr1).revokeDeed(did);
				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Deed can't be revoked at this stage");
			}
		});

		it("Should send deed collateral to borrower from vault", async function() {
			await pwn.connect(addr1).revokeDeed(did);

			expect(vaultFake.pull).to.have.been.calledOnce;
			const asset = vaultFake.pull.getCall(0).args._asset;
			expect(asset.cat).to.equal(0);
			expect(asset.amount).to.equal(amount);
			expect(asset.id).to.equal(0);
			expect(asset.tokenAddress).to.equal(fakeToken.address);
			const beneficiary = vaultFake.pull.getCall(0).args._beneficiary;
			expect(beneficiary).to.equal(addr1.address);
		});

		it("Should burn deed token", async function() {
			await pwn.connect(addr1).revokeDeed(did);

			expect(deedFake["burn(uint256,address)"]).to.have.been.calledOnceWith(did, addr1.address);
		});

		it("Should emit DeedRevoked event", async function() {
			const tx = await pwn.connect(addr1).revokeDeed(did);
			const response = await tx.wait();

			expect(response.logs.length).to.equal(1);
			const logDescription = pwnEventIface.parseLog(response.logs[0]);
			expect(logDescription.name).to.equal("DeedRevoked");
			expect(logDescription.args.did).to.equal(did);
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
			deedFake.getDeedStatus.whenCalledWith(did).returns(1);
			deedFake.setOffer.returns(offerHash);
		});

		it("Should be able to make ERC20 offer", async function() {
			await pwn.makeOffer(0, amount, fakeToken.address, did, toBePaid);
		});

		it("Should be able to make ERC721 offer", async function() {
			await pwn.makeOffer(1, 1, fakeToken.address, did, 1);
		});

		it("Should be able to make ERC1155 offer", async function() {
			await pwn.makeOffer(2, amount, fakeToken.address, did, toBePaid);
		});

		it("Should fail for unknown asset category", async function() {
			try {
				await pwn.makeOffer(3, 1, fakeToken.address, did, 2);
				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Unknown asset type");
			}
		});

		it("Should fail when deed is not in new/open state", async function() {
			deedFake.getDeedStatus.whenCalledWith(did).returns(2);

			try {
				await pwn.makeOffer(0, 1, fakeToken.address, did, 2);
				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Deed not accepting offers");
			}
		});

		it("Should set new offer to the deed", async function() {
			await pwn.connect(addr4).makeOffer(0, amount, fakeToken.address, did, toBePaid);

			expect(deedFake.setOffer).to.have.been.calledOnceWith(0, amount, fakeToken.address, addr4.address, did, toBePaid);
		});

		it("Should emit NewOffer event", async function() {
			const tx = await pwn.connect(addr4).makeOffer(0, amount, fakeToken.address, did, toBePaid);
			const response = await tx.wait();

			expect(response.logs.length).to.equal(1);
			const logDescription = pwnEventIface.parseLog(response.logs[0]);
			expect(logDescription.name).to.equal("NewOffer");
			const args = logDescription.args;
			expect(args.cat).to.equal(0);
			expect(args.amount).to.equal(amount);
			expect(args.tokenAddress).to.equal(fakeToken.address);
			expect(args.lender).to.equal(addr4.address);
			expect(args.toBePaid).to.equal(toBePaid);
			expect(args.did).to.equal(did);
			expect(args.offer).to.equal(offerHash);
		});

		it("Should return new offer hash", async function() {
			const offer = await pwn.callStatic.makeOffer(0, 9, fakeToken.address, did, 10);

			expect(offer).to.equal(offerHash);
		});
	});

	describe("Revoke offer", function() {
		const did = 333;
		const offerHash = "0x6732801029378ddf837210000397c68129387fd887839708320980942102910a";

		beforeEach(async function() {
			deedFake.getLender.whenCalledWith(offerHash).returns(addr4.address);
			deedFake.getDeedID.whenCalledWith(offerHash).returns(did);
			deedFake.getDeedStatus.whenCalledWith(did).returns(1);
		});

		it("Should fail when sender is not the offer maker", async function() {
			try {
				await pwn.connect(addr2).revokeOffer(offerHash);
				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("This address didn't create the offer");
			}
		});

		it("Should fail when deed of the offer is not in new/open state", async function() {
			deedFake.getDeedStatus.whenCalledWith(did).returns(2);

			try {
				await pwn.connect(addr4).revokeOffer(offerHash);
				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Can only remove offers from open Deeds");
			}
		});

		it("Should remove offer from deed", async function() {
			await pwn.connect(addr4).revokeOffer(offerHash);

			expect(deedFake.deleteOffer).to.have.been.calledOnceWith(offerHash);
		});

		it("Should emit OfferRevoked event", async function() {
			const tx = await pwn.connect(addr4).revokeOffer(offerHash);
			const response = await tx.wait();

			expect(response.logs.length).to.equal(1);
			const logDescription = pwnEventIface.parseLog(response.logs[0]);
			expect(logDescription.name).to.equal("OfferRevoked");
			const args = logDescription.args;
			expect(args.offer).to.equal(offerHash);
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
			deedFake.getBorrower.whenCalledWith(did).returns(addr3.address);
			deedFake.getDeedStatus.whenCalledWith(did).returns(1);
			deedFake.getLender.whenCalledWith(offerHash).returns(addr4.address);
			deedFake.getOfferAsset.whenCalledWith(offerHash).returns({
				cat: 0,
				id: 0,
				amount: amount,
				tokenAddress: fakeToken.address,
			});
			vaultFake.pullProxy.returns(true);
		});

		it("Should fail when sender is not the borrower", async function() {
			try {
				await pwn.connect(addr1).acceptOffer(offerHash);
				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("The deed doesn't belong to the caller");
			}
		});

		it("Should fail when deed is not in new/open state", async function() {
			deedFake.getDeedStatus.whenCalledWith(did).returns(2);

			try {
				await pwn.connect(addr3).acceptOffer(offerHash);
				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Deed can't accept more offers");
			}
		});

		it("Should set offer as accepted in deed", async function() {
			await pwn.connect(addr3).acceptOffer(offerHash);

			expect(deedFake.setCredit).to.have.been.calledOnceWith(did, offerHash);
		});

		it("Should update deed to running state", async function() {
			await pwn.connect(addr3).acceptOffer(offerHash);

			expect(deedFake.changeStatus).to.have.been.calledOnceWith(2, did);
		});

		it("Should send lender asset to borrower", async function() {
			await pwn.connect(addr3).acceptOffer(offerHash);

			const args = vaultFake.pullProxy.getCall(0).args;
			expect(args._asset.cat).to.equal(0);
			expect(args._asset.id).to.equal(0);
			expect(args._asset.amount).to.equal(amount);
			expect(args._asset.tokenAddress).to.equal(fakeToken.address);
			expect(args._origin).to.equal(addr4.address);
			expect(args._beneficiary).to.equal(addr3.address);
		});

		it("Should send deed token to lender", async function() {
			await pwn.connect(addr3).acceptOffer(offerHash);

			const args = vaultFake.pullProxy.getCall(1).args;
			expect(args._asset.cat).to.equal(2);
			expect(args._asset.id).to.equal(did);
			expect(args._asset.amount).to.equal(0);
			expect(args._asset.tokenAddress).to.equal(deedFake.address);
			expect(args._origin).to.equal(addr3.address);
			expect(args._beneficiary).to.equal(addr4.address);
		});

		it("Should emit OfferAccepted event", async function() {
			const tx = await pwn.connect(addr3).acceptOffer(offerHash);
			const response = await tx.wait();

			expect(response.logs.length).to.equal(1);
			const logDescription = pwnEventIface.parseLog(response.logs[0]);
			expect(logDescription.name).to.equal("OfferAccepted");
			const args = logDescription.args;
			expect(args.did).to.equal(did);
			expect(args.offer).to.equal(offerHash);
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
				cat: 0,
				id: 0,
				amount: amount,
				tokenAddress: fakeCreditToken.address,
			};
			collateral = {
				cat: 1,
				id: 123,
				amount: 1,
				tokenAddress: fakeCollateralToken.address,
			};
		});

		beforeEach(async function() {
			deedFake.getDeedStatus.whenCalledWith(did).returns(2);
			deedFake.getAcceptedOffer.whenCalledWith(did).returns(offerHash);
			deedFake.toBePaid.whenCalledWith(offerHash).returns(toBePaid);
			deedFake.getOfferAsset.whenCalledWith(offerHash).returns(credit);
			deedFake.getDeedAsset.returns(collateral);
			deedFake.getBorrower.whenCalledWith(did).returns(addr3.address);
			vaultFake.pull.returns(true);
			vaultFake.push.returns(true);
		});

		it("Should accept when sender is not the borrower", async function() {
			await pwn.connect(addr2).payBack(did);
		});

		it("Should fail when deed is not in running state", async function() {
			deedFake.getDeedStatus.whenCalledWith(did).returns(1);

			try {
				await pwn.connect(addr3).payBack(did);
				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				// This message could be confusing if the deed is in another state than new/open (e.g. expired)
				expect(error.message).to.contain("Deed doesn't have an accepted offer to be paid back");
			}
		});

		it("Should update deed to paid back state", async function() {
			await pwn.connect(addr3).payBack(did);

			expect(deedFake.changeStatus).to.have.been.calledOnceWith(3, did);
		});

		it("Should send deed collateral to borrower from vault", async function() {
			await pwn.connect(addr3).payBack(did);

			const args = vaultFake.pull.getCall(0).args;
			expect(args._asset.cat).to.equal(collateral.cat);
			expect(args._asset.id).to.equal(collateral.id);
			expect(args._asset.amount).to.equal(collateral.amount);
			expect(args._asset.tokenAddress).to.equal(collateral.tokenAddress);
			expect(args._beneficiary).to.equal(addr3.address);
		});

		it("Should send paid back amount to vault", async function() {
			await pwn.connect(addr3).payBack(did);

			const args = vaultFake.push.getCall(0).args;
			expect(args._asset.cat).to.equal(credit.cat);
			expect(args._asset.id).to.equal(credit.id);
			expect(args._asset.amount).to.equal(toBePaid);
			expect(args._asset.tokenAddress).to.equal(credit.tokenAddress);
		});

		it("Should emit PaidBack event", async function() {
			const tx = await pwn.connect(addr3).payBack(did);
			const response = await tx.wait();

			expect(response.logs.length).to.equal(1);
			const logDescription = pwnEventIface.parseLog(response.logs[0]);
			expect(logDescription.name).to.equal("PaidBack");
			const args = logDescription.args;
			expect(args.did).to.equal(did);
			expect(args.offer).to.equal(offerHash);
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
				cat: 0,
				id: 0,
				amount: amount,
				tokenAddress: fakeCreditToken.address,
			};
			collateral = {
				cat: 1,
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
			deedFake.getBorrower.whenCalledWith(did).returns(addr3.address);
			deedFake.balanceOf.whenCalledWith(addr3.address, did).returns(1);
			vaultFake.pull.returns(true);
		});

		it("Should fail when sender is not deed owner", async function() {
			try {
				await pwn.connect(addr1).claimDeed(did);
				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Caller is not the deed owner");
			}
		});

		it("Should fail when deed is not in paid back nor expired state", async function() {
			deedFake.getDeedStatus.whenCalledWith(did).returns(2);

			try {
				await pwn.connect(addr3).claimDeed(did);
				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Deed can't be claimed yet");
			}
		});

		it("Should send collateral from vault to lender when deed is expired", async function() {
			deedFake.getDeedStatus.whenCalledWith(did).returns(4);

			await pwn.connect(addr3).claimDeed(did);

			expect(vaultFake.pull).to.have.been.calledOnce;
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
			const args = vaultFake.pull.getCall(0).args;
			expect(args._asset.cat).to.equal(credit.cat);
			expect(args._asset.id).to.equal(credit.id);
			expect(args._asset.amount).to.equal(toBePaid);
			expect(args._asset.tokenAddress).to.equal(credit.tokenAddress);
		});

		it("Should emit DeedClaimed event", async function() {
			const tx = await pwn.connect(addr3).claimDeed(did);
			const response = await tx.wait();

			expect(response.logs.length).to.equal(1);
			const logDescription = pwnEventIface.parseLog(response.logs[0]);
			expect(logDescription.name).to.equal("DeedClaimed");
			const args = logDescription.args;
			expect(args.did).to.equal(did);
		});

		it("Should burn deed token", async function() {
			await pwn.connect(addr3).claimDeed(did);

			expect(deedFake['burn(uint256,address)']).to.have.been.calledOnceWith(did, addr3.address);
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
