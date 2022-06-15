const chai = require("chai");
const { ethers } = require("hardhat");
const { smock } = require("@defi-wonderland/smock");
const { time } = require('@openzeppelin/test-helpers');
const { CATEGORY, timestampFromNow, getMerkleRootWithProof } = require("./test-helpers");

const expect = chai.expect;
chai.use(smock.matchers);


describe("PWN contract", function() {

	let vaultFake, loanFake;

	let PWN, pwn;
	let owner, lender, borrower, asset1, asset2, addr1;
	let mTree, mTreeRoot, mTreeProof;
	let offer, flexibleOffer, flexibleOfferValues, loanAsset, collateral;

	const loanAmountMax = 2000;
	const loanAmountMin = 1000;
	const durationMax = 31323;
	const durationMin = 10000;
	const duration = 31323;
	const loanYield = 1000;
	const offerExpiration = 33333333;
	const nonce = ethers.utils.solidityKeccak256([ "string" ], [ "nonce" ]);
	const signature = "0x6732801029378ddf837210000397c68129387fd887839708320980942102910a6732801029378ddf837210000397c68129387fd887839708320980942102910a00";

	before(async function() {
		PWN = await ethers.getContractFactory("PWN");
		[owner, lender, borrower, asset1, asset2, addr1] = await ethers.getSigners();

		loanAsset = {
			assetAddress: asset1.address,
			category: CATEGORY.ERC20,
			amount: 1234,
			id: 0,
		};

		collateral = {
			assetAddress: asset2.address,
			category: CATEGORY.ERC721,
			amount: 1,
			id: 123,
		};
	});

	beforeEach(async function() {
		vaultFake = await smock.fake("PWNVault");
		loanFake = await smock.fake("PWNLOAN");
		pwn = await PWN.deploy(loanFake.address, vaultFake.address);

		offer = [
			collateral.assetAddress, collateral.category, collateral.amount, collateral.id,
			loanAsset.assetAddress, loanAsset.amount, loanYield,
			duration, offerExpiration, lender.address, nonce,
		];

		[mTreeRoot, mTreeProof] = getMerkleRootWithProof([1, 2, 3], 0);

		flexibleOffer = [
			collateral.assetAddress, collateral.category, collateral.amount, mTreeRoot,
			loanAsset.assetAddress, loanAmountMax, loanAmountMin, loanYield,
			durationMax, durationMin, offerExpiration, lender.address, nonce,
		];

		flexibleOfferValues = [
			collateral.id, loanAsset.amount, duration, mTreeProof
		];
	});


	describe("Constructor", function() {

		it("Should set correct owner", async function() {
			const factory = await ethers.getContractFactory("PWN");

			pwn = await factory.connect(addr1).deploy(loanFake.address, vaultFake.address);

			const contractOwner = await pwn.owner();
			expect(addr1.address).to.equal(contractOwner);
		});

		it("Should set correct contract addresses", async function() {
			const factory = await ethers.getContractFactory("PWN");

			pwn = await factory.deploy(loanFake.address, vaultFake.address);

			const vaultAddress = await pwn.vault();
			const loanAddress = await pwn.LOAN();
			expect(vaultAddress).to.equal(vaultFake.address);
			expect(loanAddress).to.equal(loanFake.address);
		});

	});


	describe("Revoke offer", function() {

		const offerHash = "0x6732801029378ddf837210000397c68129387fd887839708320980942102910a";

		it("Should revoke offer on loan", async function() {
			await pwn.connect(lender).revokeOffer(offerHash, signature);

			expect(loanFake.revokeOffer).to.have.been.calledOnceWith(offerHash, signature, lender.address);
		});

		it("Should return true if successful", async function() {
			const success = await pwn.connect(borrower).callStatic.revokeOffer(offerHash, signature);

			expect(success).to.equal(true);
		});

	});


	describe("Create loan", function() {

		beforeEach(async function() {
			vaultFake.pull.returns(true);
			vaultFake.pushFrom.returns(true);
		});


		it("Should fail for unknown asset category", async function() {
			offer[1] = CATEGORY.unknown;

			await expect(
				pwn.connect(borrower).createLoan(offer, signature)
			).to.be.reverted;
		});

		it("Should mint loan token for offer signer", async function() {
			await pwn.connect(borrower).createLoan(offer, signature);

			expect(loanFake.create).to.have.been.calledOnce;
			const args = loanFake.create.getCall(0).args;
			expect(args._offer.collateralAddress).to.equal(collateral.assetAddress);
			expect(args._offer.collateralCategory).to.equal(collateral.category);
			expect(args._offer.collateralAmount).to.equal(collateral.amount);
			expect(args._offer.collateralId).to.equal(collateral.id);
			expect(args._offer.loanAssetAddress).to.equal(loanAsset.assetAddress);
			expect(args._offer.loanAmount).to.equal(loanAsset.amount);
			expect(args._offer.loanYield).to.equal(loanYield);
			expect(args._offer.duration).to.equal(duration);
			expect(args._offer.expiration).to.equal(offerExpiration);
			expect(args._offer.lender).to.equal(lender.address);
			expect(args._offer.nonce).to.equal(nonce);
			expect(args._signature).to.equal(signature);
			expect(args._sender).to.equal(borrower.address);
			expect(vaultFake.pushFrom).to.have.been.calledAfter(loanFake.create);
		});

		it("Should send borrower collateral to vault", async function() {
			await pwn.connect(borrower).createLoan(offer, signature);

			expect(vaultFake.pull).to.have.been.calledOnce;
			const args = vaultFake.pull.getCall(0).args;
			expect(args._asset.assetAddress).to.equal(collateral.assetAddress);
			expect(args._asset.category).to.equal(collateral.category);
			expect(args._asset.amount).to.equal(collateral.amount);
			expect(args._asset.id).to.equal(collateral.id);
			expect(args._origin).to.equal(borrower.address);
			expect(vaultFake.pushFrom).to.have.been.calledAfter(loanFake.create);
		});

		it("Should send lender asset to borrower", async function() {
			await pwn.connect(borrower).createLoan(offer, signature);

			expect(vaultFake.pushFrom).to.have.been.calledOnce;
			const args = vaultFake.pushFrom.getCall(0).args;
			expect(args._asset.assetAddress).to.equal(loanAsset.assetAddress);
			expect(args._asset.category).to.equal(loanAsset.category);
			expect(args._asset.amount).to.equal(loanAsset.amount);
			expect(args._asset.id).to.equal(loanAsset.id);
			expect(args._origin).to.equal(lender.address);
			expect(args._beneficiary).to.equal(borrower.address);
			expect(vaultFake.pushFrom).to.have.been.calledAfter(loanFake.create);
		});

		it("Should return true if successful", async function() {
			const success = await pwn.connect(borrower).callStatic.createLoan(offer, signature);

			expect(success).to.equal(true);
		});

	});


	describe("Create loan flexible", function() {

		beforeEach(async function() {
			vaultFake.pull.returns(true);
			vaultFake.pushFrom.returns(true);
		});


		it("Should fail for unknown asset category", async function() {
			flexibleOffer[1] = CATEGORY.unknown;

			await expect(
				pwn.connect(borrower).createFlexibleLoan(flexibleOffer, flexibleOfferValues, signature)
			).to.be.reverted;
		});

		it("Should mint loan token for offer signer", async function() {
			await pwn.connect(borrower).createFlexibleLoan(flexibleOffer, flexibleOfferValues, signature);

			expect(loanFake.createFlexible).to.have.been.calledOnce;
			const args = loanFake.createFlexible.getCall(0).args;
			expect(args._offer.collateralAddress).to.equal(collateral.assetAddress);
			expect(args._offer.collateralCategory).to.equal(collateral.category);
			expect(args._offer.collateralAmount).to.equal(collateral.amount);
			expect(args._offer.collateralIdsWhitelistMerkleRoot).to.equal(mTreeRoot)
			expect(args._offer.loanAssetAddress).to.equal(loanAsset.assetAddress);
			expect(args._offer.loanAmountMax).to.equal(loanAmountMax);
			expect(args._offer.loanAmountMin).to.equal(loanAmountMin);
			expect(args._offer.loanYieldMax).to.equal(loanYield);
			expect(args._offer.durationMax).to.equal(durationMax);
			expect(args._offer.durationMin).to.equal(durationMin);
			expect(args._offer.expiration).to.equal(offerExpiration);
			expect(args._offer.lender).to.equal(lender.address);
			expect(args._offer.nonce).to.equal(nonce);
			expect(args._offerValues.collateralId).to.equal(collateral.id);
			expect(args._offerValues.loanAmount).to.equal(loanAsset.amount);
			expect(args._offerValues.duration).to.equal(duration);
			expect(args._offerValues.merkleInclusionProof).to.have.lengthOf(mTreeProof.length);
			expect(args._signature).to.equal(signature);
			expect(args._sender).to.equal(borrower.address);
			expect(vaultFake.pushFrom).to.have.been.calledAfter(loanFake.createFlexible);
		});

		it("Should send borrower collateral to vault", async function() {
			await pwn.connect(borrower).createFlexibleLoan(flexibleOffer, flexibleOfferValues, signature);

			expect(vaultFake.pull).to.have.been.calledOnce;
			const args = vaultFake.pull.getCall(0).args;
			expect(args._asset.assetAddress).to.equal(collateral.assetAddress);
			expect(args._asset.category).to.equal(collateral.category);
			expect(args._asset.amount).to.equal(collateral.amount);
			expect(args._asset.id).to.equal(collateral.id);
			expect(args._origin).to.equal(borrower.address);
			expect(vaultFake.pushFrom).to.have.been.calledAfter(loanFake.createFlexible);
		});

		it("Should send lender asset to borrower", async function() {
			await pwn.connect(borrower).createFlexibleLoan(flexibleOffer, flexibleOfferValues, signature);

			expect(vaultFake.pushFrom).to.have.been.calledOnce;
			const args = vaultFake.pushFrom.getCall(0).args;
			expect(args._asset.assetAddress).to.equal(loanAsset.assetAddress);
			expect(args._asset.category).to.equal(loanAsset.category);
			expect(args._asset.amount).to.equal(loanAsset.amount);
			expect(args._asset.id).to.equal(loanAsset.id);
			expect(args._origin).to.equal(lender.address);
			expect(args._beneficiary).to.equal(borrower.address);
			expect(vaultFake.pushFrom).to.have.been.calledAfter(loanFake.createFlexible);
		});

		it("Should return true if successful", async function() {
			const success = await pwn.connect(borrower).callStatic.createFlexibleLoan(flexibleOffer, flexibleOfferValues, signature);

			expect(success).to.equal(true);
		});

	});


	describe("Repay loan", function() {

		const loanId = 536;

		beforeEach(async function() {
			loanFake.getLoanRepayAmount.whenCalledWith(loanId).returns(loanAsset.amount + loanYield);
			loanFake.getLoanAsset.whenCalledWith(loanId).returns(loanAsset);
			loanFake.getCollateral.whenCalledWith(loanId).returns(collateral);
			loanFake.getBorrower.whenCalledWith(loanId).returns(borrower.address);
			vaultFake.push.returns(true);
			vaultFake.pull.returns(true);
		});


		it("Should update loan to paid back state", async function() {
			await pwn.connect(borrower).repayLoan(loanId);

			expect(loanFake.repayLoan).to.have.been.calledOnceWith(loanId);
		});

		it("Should send loan collateral from vault to borrower", async function() {
			await pwn.connect(borrower).repayLoan(loanId);

			const args = vaultFake.push.getCall(0).args;
			expect(args._asset.assetAddress).to.equal(collateral.assetAddress);
			expect(args._asset.category).to.equal(collateral.category);
			expect(args._asset.amount).to.equal(collateral.amount);
			expect(args._asset.id).to.equal(collateral.id);
			expect(args._beneficiary).to.equal(borrower.address);
			expect(vaultFake.push).to.have.been.calledAfter(loanFake.repayLoan);
		});

		it("Should send paid back amount from borrower to vault", async function() {
			await pwn.connect(borrower).repayLoan(loanId);

			const args = vaultFake.pull.getCall(0).args;
			expect(args._asset.assetAddress).to.equal(loanAsset.assetAddress);
			expect(args._asset.category).to.equal(loanAsset.category);
			expect(args._asset.amount).to.equal(loanAsset.amount + loanYield);
			expect(args._asset.id).to.equal(loanAsset.id);
			expect(args._origin).to.equal(borrower.address);
			expect(vaultFake.pull).to.have.been.calledAfter(loanFake.repayLoan);
		});

		it("Should be possible for anybody to repay a loan", async function() {
			const success = await pwn.connect(lender).callStatic.repayLoan(loanId);

			expect(success).to.equal(true);
		});

		it("Should return true if successful", async function() {
			const success = await pwn.connect(borrower).callStatic.repayLoan(loanId);

			expect(success).to.equal(true);
		});

	});


	describe("Claim loan", function() {

		const loanId = 987;

		beforeEach(async function() {
			loanFake.getStatus.whenCalledWith(loanId).returns(3);
			loanFake.getLoanRepayAmount.whenCalledWith(loanId).returns(loanAsset.amount + loanYield);
			loanFake.getCollateral.whenCalledWith(loanId).returns(collateral);
			loanFake.getLoanAsset.whenCalledWith(loanId).returns(loanAsset);
			vaultFake.push.returns(true);
		});


		it("Should update loan to claimed state", async function() {
			await pwn.connect(lender).claimLoan(loanId);

			expect(loanFake.claim).to.have.been.calledOnceWith(loanId, lender.address);
		});

		it("Should send collateral from vault to lender when loan is expired", async function() {
			loanFake.getStatus.whenCalledWith(loanId).returns(4);

			await pwn.connect(lender).claimLoan(loanId);

			expect(vaultFake.push).to.have.been.calledOnce;
			expect(vaultFake.push).to.have.been.calledAfter(loanFake.claim);
			const args = vaultFake.push.getCall(0).args;
			expect(args._asset.assetAddress).to.equal(collateral.assetAddress);
			expect(args._asset.category).to.equal(collateral.category);
			expect(args._asset.amount).to.equal(collateral.amount);
			expect(args._asset.id).to.equal(collateral.id);
			expect(args._beneficiary).to.equal(lender.address);
		});

		it("Should send paid back amount from vault to lender when loan is paid back", async function() {
			loanFake.getStatus.whenCalledWith(loanId).returns(3);

			await pwn.connect(lender).claimLoan(loanId);

			expect(vaultFake.push).to.have.been.calledOnce;
			expect(vaultFake.push).to.have.been.calledAfter(loanFake.claim);
			const args = vaultFake.push.getCall(0).args;
			expect(args._asset.assetAddress).to.equal(loanAsset.assetAddress);
			expect(args._asset.category).to.equal(loanAsset.category);
			expect(args._asset.amount).to.equal(loanAsset.amount + loanYield);
			expect(args._asset.id).to.equal(loanAsset.id);
		});

		it("Should burn loan token", async function() {
			await pwn.connect(lender).claimLoan(loanId);

			expect(loanFake.burn).to.have.been.calledOnceWith(loanId, lender.address);
			expect(loanFake.burn).to.have.been.calledAfter(vaultFake.push);
		});

		it("Should return true if successful", async function() {
			const success = await pwn.connect(lender).callStatic.claimLoan(loanId);

			expect(success).to.equal(true);
		});

	});

});
