const chai = require("chai");
const { ethers } = require("hardhat");
const { smock } = require("@defi-wonderland/smock");
const { time } = require('@openzeppelin/test-helpers');
const { CATEGORY, timestampFromNow } = require("./test-helpers");

const expect = chai.expect;
chai.use(smock.matchers);


describe("PWN contract", function() {

	let vaultFake, deedFake;

	let PWN, pwn;
	let owner, lender, borrower, asset1, asset2, addr1;
	let offer, loan, collateral;

	const duration = 31323;
	const loanRepayAmount = 2222;
	const offerExpiration = 33333333;
	const nonce = ethers.utils.solidityKeccak256([ "string" ], [ "nonce" ]);
	const signature = "0x6732801029378ddf837210000397c68129387fd887839708320980942102910a6732801029378ddf837210000397c68129387fd887839708320980942102910a00";

	before(async function() {
		PWN = await ethers.getContractFactory("PWN");
		[owner, lender, borrower, asset1, asset2, addr1] = await ethers.getSigners();

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
		vaultFake = await smock.fake("PWNVault");
		deedFake = await smock.fake("PWNDeed");
		pwn = await PWN.deploy(deedFake.address, vaultFake.address);

		offer = [
			collateral.assetAddress,
			collateral.category,
			collateral.amount,
			collateral.id,
			loan.assetAddress,
			loan.amount,
			loanRepayAmount,
			duration,
			offerExpiration,
			lender.address,
			nonce,
			signature,
		];
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


	describe("Revoke offer", function() {

		const offerHash = "0x6732801029378ddf837210000397c68129387fd887839708320980942102910a";

		it("Should revoke offer on deed", async function() {
			await pwn.connect(lender).revokeOffer(offerHash, signature);

			expect(deedFake.revokeOffer).to.have.been.calledOnceWith(offerHash, signature, lender.address);
		});

		it("Should return true if successful", async function() {
			const success = await pwn.connect(borrower).callStatic.revokeOffer(offerHash, signature);

			expect(success).to.equal(true);
		});

	});


	describe("Create deed", function() {

		beforeEach(async function() {
			vaultFake.push.returns(true);
			vaultFake.pullProxy.returns(true);
		});


		it("Should fail for unknown asset category", async function() {
			let failed;
			offer[1] = CATEGORY.unknown;

			try {
				await pwn.connect(borrower).createDeed(...offer);
			} catch {
				failed = true;
			}

			expect(failed).to.equal(true);
		});

		it("Should mint deed token for offer signer", async function() {
			await pwn.connect(borrower).createDeed(...offer);

			expect(deedFake.create).to.have.been.calledOnce;
			const args = deedFake.create.getCall(0).args;
			expect(args._offer.collateral.assetAddress).to.equal(collateral.assetAddress);
			expect(args._offer.collateral.category).to.equal(collateral.category);
			expect(args._offer.collateral.id).to.equal(collateral.id);
			expect(args._offer.collateral.amount).to.equal(collateral.amount);
			expect(args._offer.loan.assetAddress).to.equal(loan.assetAddress);
			expect(args._offer.loan.amount).to.equal(loan.amount);
			expect(args._offer.loanRepayAmount).to.equal(loanRepayAmount);
			expect(args._offer.duration).to.equal(duration);
			expect(args._offer.expiration).to.equal(offerExpiration);
			expect(args._offer.lender).to.equal(lender.address);
			expect(args._offer.nonce).to.equal(nonce);
			expect(args._signature).to.equal(signature);
			expect(args._sender).to.equal(borrower.address);
			expect(vaultFake.pullProxy).to.have.been.calledAfter(deedFake.create);
		});

		it("Should send borrower collateral to vault", async function() {
			await pwn.connect(borrower).createDeed(...offer);

			expect(vaultFake.push).to.have.been.calledOnce;
			const args = vaultFake.push.getCall(0).args;
			expect(args._asset.assetAddress).to.equal(collateral.assetAddress);
			expect(args._asset.category).to.equal(collateral.category);
			expect(args._asset.id).to.equal(collateral.id);
			expect(args._asset.amount).to.equal(collateral.amount);
			expect(args._origin).to.equal(borrower.address);
			expect(vaultFake.pullProxy).to.have.been.calledAfter(deedFake.create);
		});

		it("Should send lender asset to borrower", async function() {
			await pwn.connect(borrower).createDeed(...offer);

			expect(vaultFake.pullProxy).to.have.been.calledOnce;
			const args = vaultFake.pullProxy.getCall(0).args;
			expect(args._asset.assetAddress).to.equal(loan.assetAddress);
			expect(args._asset.category).to.equal(loan.category);
			expect(args._asset.id).to.equal(loan.id);
			expect(args._asset.amount).to.equal(loan.amount);
			expect(args._origin).to.equal(lender.address);
			expect(args._beneficiary).to.equal(borrower.address);
			expect(vaultFake.pullProxy).to.have.been.calledAfter(deedFake.create);
		});

		it("Should return true if successful", async function() {
			const success = await pwn.connect(borrower).callStatic.createDeed(...offer);

			expect(success).to.equal(true);
		});

	});

	describe("Repay loan", function() {

		const did = 536;

		beforeEach(async function() {
			deedFake.getLoanRepayAmount.whenCalledWith(did).returns(loanRepayAmount);
			deedFake.getLoan.whenCalledWith(did).returns(loan);
			deedFake.getCollateral.whenCalledWith(did).returns(collateral);
			deedFake.getBorrower.whenCalledWith(did).returns(borrower.address);
			vaultFake.pull.returns(true);
			vaultFake.push.returns(true);
		});


		it("Should update deed to paid back state", async function() {
			await pwn.connect(borrower).repayLoan(did);

			expect(deedFake.repayLoan).to.have.been.calledOnceWith(did);
		});

		it("Should send deed collateral from vault to borrower", async function() {
			await pwn.connect(borrower).repayLoan(did);

			const args = vaultFake.pull.getCall(0).args;
			expect(args._asset.assetAddress).to.equal(collateral.assetAddress);
			expect(args._asset.category).to.equal(collateral.category);
			expect(args._asset.id).to.equal(collateral.id);
			expect(args._asset.amount).to.equal(collateral.amount);
			expect(args._beneficiary).to.equal(borrower.address);
			expect(vaultFake.pull).to.have.been.calledAfter(deedFake.repayLoan);
		});

		it("Should send paid back amount from borrower to vault", async function() {
			await pwn.connect(borrower).repayLoan(did);

			const args = vaultFake.push.getCall(0).args;
			expect(args._asset.assetAddress).to.equal(loan.assetAddress);
			expect(args._asset.category).to.equal(loan.category);
			expect(args._asset.id).to.equal(loan.id);
			expect(args._asset.amount).to.equal(loanRepayAmount);
			expect(args._origin).to.equal(borrower.address);
			expect(vaultFake.push).to.have.been.calledAfter(deedFake.repayLoan);
		});

		it("Should be possible for anybody to repay a loan", async function() {
			const success = await pwn.connect(lender).callStatic.repayLoan(did);

			expect(success).to.equal(true);
		});

		it("Should return true if successful", async function() {
			const success = await pwn.connect(borrower).callStatic.repayLoan(did);

			expect(success).to.equal(true);
		});

	});


	describe("Claim deed", function() {

		const did = 987;

		beforeEach(async function() {
			deedFake.getStatus.whenCalledWith(did).returns(3);
			deedFake.getLoanRepayAmount.whenCalledWith(did).returns(loanRepayAmount);
			deedFake.getCollateral.whenCalledWith(did).returns(collateral);
			deedFake.getLoan.whenCalledWith(did).returns(loan);
			vaultFake.pull.returns(true);
		});


		it("Should update deed to claimed state", async function() {
			await pwn.connect(lender).claimDeed(did);

			expect(deedFake.claim).to.have.been.calledOnceWith(did, lender.address);
		});

		it("Should send collateral from vault to lender when deed is expired", async function() {
			deedFake.getStatus.whenCalledWith(did).returns(4);

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
			deedFake.getStatus.whenCalledWith(did).returns(3);

			await pwn.connect(lender).claimDeed(did);

			expect(vaultFake.pull).to.have.been.calledOnce;
			expect(vaultFake.pull).to.have.been.calledAfter(deedFake.claim);
			const args = vaultFake.pull.getCall(0).args;
			expect(args._asset.assetAddress).to.equal(loan.assetAddress);
			expect(args._asset.category).to.equal(loan.category);
			expect(args._asset.id).to.equal(loan.id);
			expect(args._asset.amount).to.equal(loanRepayAmount);
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
