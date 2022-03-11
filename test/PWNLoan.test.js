const chai = require("chai");
const { ethers } = require("hardhat");
const { smock } = require("@defi-wonderland/smock");
const { time } = require('@openzeppelin/test-helpers');
const { CATEGORY, timestampFromNow, getOfferHashBytes, signOffer } = require("./test-helpers");

const expect = chai.expect;
chai.use(smock.matchers);


describe("PWNLoan contract", function() {

	let PWNLOAN, loan, loanEventIface;
	let pwn, lender, borrower, asset1, asset2, addr1, addr2, addr3, addr4, addr5;
	let offer, flexibleOffer, flexibleOfferValues, offerHash, signature, loanAsset, collateral;

	const loanAmountMax = 2_000;
	const loanAmountMin = 1_000;
	const durationMax = 100_000;
	const durationMin = 10_000;
	const duration = 100_000;
	const loanYield = 1_000;
	const offerExpiration = 0;
	const nonce = ethers.utils.solidityKeccak256([ "string" ], [ "nonce" ]);

	before(async function() {
		PWNLOAN = await ethers.getContractFactory("PWNLOAN");
		[pwn, lender, borrower, asset1, asset2, addr1, addr2, addr3, addr4, addr5] = await ethers.getSigners();

		loanEventIface = new ethers.utils.Interface([
			"event LOANCreated(uint256 indexed loanId, address indexed lender, bytes32 indexed offerHash)",
			"event OfferRevoked(bytes32 indexed offerHash)",
			"event PaidBack(uint256 loanId)",
			"event LOANClaimed(uint256 loanId)",
		]);

		loanAsset = {
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
		loan = await PWNLOAN.deploy("https://test.uri");
		await loan.setPWN(pwn.address);

		offer = [
			collateral.assetAddress, collateral.category, collateral.amount, collateral.id,
			loanAsset.assetAddress, loanAsset.amount,
			loanYield, duration, offerExpiration, lender.address, nonce,
		];

		flexibleOffer = [
			collateral.assetAddress, collateral.category, collateral.amount, [],
			loanAsset.assetAddress, loanAmountMax, loanAmountMin, loanYield,
			durationMax, durationMin, offerExpiration, lender.address, nonce,
		];

		flexibleOfferValues = [
			collateral.id, loanAsset.amount, duration,
		];

		offerHash = getOfferHashBytes(offer, loan.address);
		signature = await signOffer(offer, loan.address, lender);
	});


	describe("Constructor", function() {

		it("Should set correct owner", async function() {
			const factory = await ethers.getContractFactory("PWNLOAN", addr1);

			loan = await factory.deploy("https://test.uri");

			const contractOwner = await loan.owner();
			expect(addr1.address).to.equal(contractOwner);
		});

		it("Should set correct uri", async function() {
			const factory = await ethers.getContractFactory("PWNLOAN");

			loan = await factory.deploy("xyz123");

			const uri = await loan.uri(1);
			expect(uri).to.equal("xyz123");
		});

	});


	describe("Revoke offer", function() { // -> PWN is trusted source so we believe that it would not send invalid data

		it("Should fail when sender is not PWN contract", async function() {
			await expect(
				loan.connect(addr1).revokeOffer(offerHash, signature, lender.address)
			).to.be.revertedWith("Caller is not the PWN");
		});

		it("Should fail when lender is not the offer signer", async function() {
			await expect(
				loan.revokeOffer(offerHash, signature, borrower.address)
			).to.be.revertedWith("Sender is not an offer signer");
		});

		it("Should fail with invalid signature", async function() {
			const fakeSignature = "0x6732801029378ddf837210000397c68129387fd887839708320980942102910a6732801029378ddf837210000397c68129387fd887839708320980942102910a00";

			await expect(
				loan.revokeOffer(offerHash, fakeSignature, lender.address)
			).to.be.revertedWith("ECDSA: invalid signature");
		});

		it("Should fail if offer is already revoked", async function() {
			await loan.revokeOffer(offerHash, signature, lender.address);

			await expect(
				loan.revokeOffer(offerHash, signature, lender.address)
			).to.be.revertedWith("Offer is already revoked or has been accepted");
		});

		it("Should set offer as revoked", async function() {
			await loan.revokeOffer(offerHash, signature, lender.address);

			const isRevoked = await loan.revokedOffers(offerHash);
			expect(isRevoked).to.equal(true);
		});

		it("Should emit `OfferRevoked` event", async function() {
			await expect(
				loan.revokeOffer(offerHash, signature, lender.address)
			).to.emit(loan, "OfferRevoked").withArgs(
				ethers.utils.hexValue(offerHash)
			);
		});

	});


	describe("Create", function() { // -> PWN is trusted source so we believe that it would not send invalid data

		it("Should fail when sender is not PWN contract", async function() {
			await expect(
				loan.connect(addr1).create(offer, signature, borrower.address)
			).to.be.revertedWith("Caller is not the PWN");
		});

		it("Should fail when offer lender is not offer signer", async function() {
			offer[9] = addr1.address;

			await expect(
				loan.create(offer, signature, borrower.address)
			).to.be.revertedWith("Lender address didn't sign the offer");
		});

		it("Should pass when offer is signed on behalf of a contract wallet", async function() {
			const fakeContractWallet = await smock.fake("ContractWallet");
			offer[9] = fakeContractWallet.address;
			offerHash = getOfferHashBytes(offer, loan.address);
			signature = await signOffer(offer, loan.address, addr1);
			fakeContractWallet.isValidSignature.whenCalledWith(offerHash, signature).returns("0x1626ba7e");
			fakeContractWallet.onERC1155Received.returns("0xf23a6e61");

			await expect(
				loan.create(offer, signature, borrower.address)
			).to.not.be.reverted;
		});

		it("Should fail when contract wallet returns that offer signed on behalf of a contract wallet is invalid", async function() {
			const fakeContractWallet = await smock.fake("ContractWallet");
			offer[9] = fakeContractWallet.address;
			signature = await signOffer(offer, loan.address, addr1);
			fakeContractWallet.isValidSignature.returns("0xffffffff");
			fakeContractWallet.onERC1155Received.returns("0xf23a6e61");

			await expect(
				loan.create(offer, signature, borrower.address)
			).to.be.revertedWith("Signature on behalf of contract is invalid");
		});

		it("Should fail when given invalid signature", async function() {
			const fakeSignature = "0x6732801029378ddf837210000397c68129387fd887839708320980942102910a6732801029378ddf837210000397c68129387fd887839708320980942102910a00";

			await expect(
				loan.create(offer, fakeSignature, borrower.address)
			).to.be.revertedWith("ECDSA: invalid signature");
		});

		it("Should fail when offer is expired", async function() {
			offer[8] = 1;
			signature = await signOffer(offer, loan.address, lender);

			await expect(
				loan.create(offer, signature, borrower.address)
			).to.be.revertedWith("Offer is expired");
		});

		it("Should pass when offer has expiration but is not expired", async function() {
			const expiration = await timestampFromNow(100);
			offer[8] = expiration;
			signature = await signOffer(offer, loan.address, lender);

			await expect(
				loan.create(offer, signature, borrower.address)
			).to.not.be.reverted;
		});

		it("Should fail when offer is revoked", async function() {
			await loan.revokeOffer(offerHash, signature, lender.address);

			await expect(
				loan.create(offer, signature, borrower.address)
			).to.be.revertedWith("Offer is revoked or has been accepted");
		});

		it("Should revoke accepted offer", async function() {
			await loan.create(offer, signature, borrower.address);

			const isRevoked = await loan.revokedOffers(offerHash);
			expect(isRevoked).to.equal(true);
		});

		it("Should mint loan ERC1155 token", async function () {
			await loan.create(offer, signature, borrower.address);
			const loanId = await loan.id();

			const balance = await loan.balanceOf(lender.address, loanId);
			expect(balance).to.equal(1);
		});

		it("Should save loan data", async function () {
			await loan.create(offer, signature, borrower.address);
			const expiration = await timestampFromNow(duration);
			const loanId = await loan.id();

			const loanToken = await loan.LOANs(loanId);
			expect(loanToken.status).to.equal(2);
			expect(loanToken.borrower).to.equal(borrower.address);
			expect(loanToken.duration).to.equal(duration);
			expect(loanToken.expiration).to.equal(expiration);
			expect(loanToken.collateral.assetAddress).to.equal(collateral.assetAddress);
			expect(loanToken.collateral.category).to.equal(collateral.category);
			expect(loanToken.collateral.id).to.equal(collateral.id);
			expect(loanToken.collateral.amount).to.equal(collateral.amount);
			expect(loanToken.asset.assetAddress).to.equal(loanAsset.assetAddress);
			expect(loanToken.asset.category).to.equal(loanAsset.category);
			expect(loanToken.asset.id).to.equal(loanAsset.id);
			expect(loanToken.asset.amount).to.equal(loanAsset.amount);
			expect(loanToken.loanRepayAmount).to.equal(loanAsset.amount + loanYield);
		});

		it("Should increase global loan ID", async function() {
			await loan.create(offer, signature, borrower.address);
			const loanId1 = await loan.id();

			offer[10] = ethers.utils.solidityKeccak256([ "string" ], [ "nonce_2" ]);
			signature = await signOffer(offer, loan.address, lender);

			await loan.create(offer, signature, borrower.address);
			const loanId2 = await loan.id();

			expect(loanId2).to.equal(loanId1.add(1));
		});

		it("Should emit `LOANCreated` event", async function() {
			const loanId = await loan.id();

			await expect(
				loan.create(offer, signature, borrower.address)
			).to.emit(loan, "LOANCreated").withArgs(
				loanId + 1, lender.address, ethers.utils.hexValue(offerHash)
			);
		});

	});


	describe("Create flexible", function() { // -> PWN is trusted source so we believe that it would not send invalid data

		beforeEach(async function() {
			offerHash = getOfferHashBytes(flexibleOffer, loan.address);
			signature = await signOffer(flexibleOffer, loan.address, lender);
		});


		it("Should fail when sender is not PWN contract", async function() {
			await expect(
				loan.connect(addr1).createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address)
			).to.be.revertedWith("Caller is not the PWN");
		});

		it("Should fail when offer lender is not offer signer", async function() {
			flexibleOffer[11] = addr1.address;

			await expect(
				loan.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address)
			).to.be.revertedWith("Lender address didn't sign the offer");
		});

		it("Should pass when offer is signed on behalf of a contract wallet", async function() {
			const fakeContractWallet = await smock.fake("ContractWallet");
			flexibleOffer[11] = fakeContractWallet.address;
			offerHash = getOfferHashBytes(flexibleOffer, loan.address);
			signature = await signOffer(flexibleOffer, loan.address, addr1);
			fakeContractWallet.isValidSignature.whenCalledWith(offerHash, signature).returns("0x1626ba7e");
			fakeContractWallet.onERC1155Received.returns("0xf23a6e61");

			await expect(
				loan.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address)
			).to.not.be.reverted;
		});

		it("Should fail when contract wallet returns that offer signed on behalf of a contract wallet is invalid", async function() {
			const fakeContractWallet = await smock.fake("ContractWallet");
			flexibleOffer[11] = fakeContractWallet.address;
			signature = await signOffer(flexibleOffer, loan.address, addr1);
			fakeContractWallet.isValidSignature.returns("0xffffffff");
			fakeContractWallet.onERC1155Received.returns("0xf23a6e61");

			await expect(
				loan.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address)
			).to.be.revertedWith("Signature on behalf of contract is invalid");
		});

		it("Should fail when given invalid signature", async function() {
			const fakeSignature = "0x6732801029378ddf837210000397c68129387fd887839708320980942102910a6732801029378ddf837210000397c68129387fd887839708320980942102910a00";

			await expect(
				loan.createFlexible(flexibleOffer, flexibleOfferValues, fakeSignature, borrower.address)
			).to.be.revertedWith("ECDSA: invalid signature");
		});

		it("Should fail when offer is expired", async function() {
			flexibleOffer[10] = 1;
			signature = await signOffer(flexibleOffer, loan.address, lender);

			await expect(
				loan.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address)
			).to.be.revertedWith("Offer is expired");
		});

		it("Should pass when offer has expiration but is not expired", async function() {
			const expiration = await timestampFromNow(100);
			flexibleOffer[10] = expiration;
			signature = await signOffer(flexibleOffer, loan.address, lender);

			await expect(
				loan.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address)
			).to.not.be.reverted;
		});

		it("Should fail when offer is revoked", async function() {
			await loan.revokeOffer(offerHash, signature, lender.address);

			await expect(
				loan.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address)
			).to.be.revertedWith("Offer is revoked or has been accepted");
		});

		it("Should fail when selected collateral ID is not whitelisted", async function() {
			flexibleOffer[3] = [1, 2, 3];
			signature = await signOffer(flexibleOffer, loan.address, lender);

			await expect(
				loan.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address)
			).to.be.revertedWith("Selected collateral id is not contained in whitelist");
		});

		it("Should pass when selected collateral ID is whitelisted", async function() {
			flexibleOffer[3] = [1, 2, 3, 123, 4, 5, 6];
			signature = await signOffer(flexibleOffer, loan.address, lender);

			await expect(
				loan.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address)
			).to.not.be.reverted;
		});

		it("Should pass with any selected collateral ID when is whitelist empty", async function() {
			flexibleOffer[3] = [];
			signature = await signOffer(flexibleOffer, loan.address, lender);

			await expect(
				loan.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address)
			).to.not.be.reverted;
		});

		it("Should fail when given amount is above offered range", async function() {
			flexibleOfferValues[1] = loanAmountMax + 1;

			await expect(
				loan.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address)
			).to.be.revertedWith("Loan amount is not in offered range");
		});

		it("Should fail when given amount is below offered range", async function() {
			flexibleOfferValues[1] = loanAmountMin - 1;

			await expect(
				loan.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address)
			).to.be.revertedWith("Loan amount is not in offered range");
		});

		it("Should fail when given duration is above offered range", async function() {
			flexibleOfferValues[2] = durationMax + 1;

			await expect(
				loan.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address)
			).to.be.revertedWith("Loan duration is not in offered range");
		});

		it("Should fail when given duration is below offered range", async function() {
			flexibleOfferValues[2] = durationMin - 1;

			await expect(
				loan.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address)
			).to.be.revertedWith("Loan duration is not in offered range");
		});

		it("Should revoke accepted offer", async function() {
			await loan.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address);

			const isRevoked = await loan.revokedOffers(offerHash);
			expect(isRevoked).to.equal(true);
		});

		it("Should mint loan ERC1155 token", async function () {
			await loan.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address);
			const loanId = await loan.id();

			const balance = await loan.balanceOf(lender.address, loanId);
			expect(balance).to.equal(1);
		});

		it("Should save loan data", async function () {
			await loan.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address);
			const expiration = await timestampFromNow(duration);
			const loanId = await loan.id();

			const loanToken = await loan.LOANs(loanId);
			expect(loanToken.status).to.equal(2);
			expect(loanToken.borrower).to.equal(borrower.address);
			expect(loanToken.duration).to.equal(duration);
			expect(loanToken.expiration).to.equal(expiration);
			expect(loanToken.collateral.assetAddress).to.equal(collateral.assetAddress);
			expect(loanToken.collateral.category).to.equal(collateral.category);
			expect(loanToken.collateral.id).to.equal(collateral.id);
			expect(loanToken.collateral.amount).to.equal(collateral.amount);
			expect(loanToken.asset.assetAddress).to.equal(loanAsset.assetAddress);
			expect(loanToken.asset.category).to.equal(loanAsset.category);
			expect(loanToken.asset.id).to.equal(loanAsset.id);
			expect(loanToken.asset.amount).to.equal(loanAsset.amount);
			expect(loanToken.loanRepayAmount).to.equal(loanAsset.amount + loanYield);
		});

		// Waiting on smock to fix mocking functions calls on a same contract
		// https://github.com/defi-wonderland/smock/issues/109
		xit("Should call `countLoanRepayAmount` for loan repay amount value", async function() {
			const loanMockFactory = await smock.mock("PWNLOAN");
			const loanMock = await loanMockFactory.deploy("https://test.uri");
			await loanMock.setPWN(pwn.address);
			loanMock.countLoanRepayAmount.returns(1);
			signature = await signOffer(flexibleOffer, loanMock.address, lender);

			await loanMock.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address);

			const loanId = await loanMock.id();
			const loanToken = await loanMock.LOANs(loanId);
			expect(loanToken.loanRepayAmount).to.equal(1);
			expect(loanMock.countLoanRepayAmount).to.have.been.calledOnce;
		});

		it("Should increase global loan ID", async function() {
			await loan.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address);
			const loanId1 = await loan.id();

			flexibleOffer[12] = ethers.utils.solidityKeccak256([ "string" ], [ "nonce_2" ]);
			signature = await signOffer(flexibleOffer, loan.address, lender);

			await loan.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address);
			const loanId2 = await loan.id();

			expect(loanId2).to.equal(loanId1.add(1));
		});

		it("Should emit `LOANCreated` event", async function() {
			const loanId = await loan.id();

			await expect(
				loan.createFlexible(flexibleOffer, flexibleOfferValues, signature, borrower.address)
			).to.emit(loan, "LOANCreated").withArgs(
				loanId + 1, lender.address, ethers.utils.hexValue(offerHash)
			);
		});

	});


	describe("Repay loan", function() {

		let loanId;

		beforeEach(async function() {
			await loan.create(offer, signature, borrower.address);
			loanId = await loan.id();
		});


		it("Should fail when sender is not PWN contract", async function() {
			await expect(
				loan.connect(addr1).repayLoan(loanId)
			).to.be.revertedWith("Caller is not the PWN");
		});

		it("Should fail when loan is not in running state", async function() {
			const loanMockFactory = await smock.mock("PWNLOAN");
			const loanMock = await loanMockFactory.deploy("https://test.uri");
			await loanMock.setPWN(pwn.address);
			await loanMock.setVariable("LOANs", {
				1: {
					status: 3
				}
			});

			await expect(
				loanMock.repayLoan(loanId)
			).to.be.revertedWith("Loan is not running and cannot be paid back");
		});

		it("Should update loan to paid back state", async function() {
			await loan.repayLoan(loanId);

			const status = (await loan.LOANs(loanId)).status;
			expect(status).to.equal(3);
		});

		it("Should emit `PaidBack` event", async function() {
			await expect(
				loan.repayLoan(loanId)
			).to.emit(loan, "PaidBack").withArgs(
				loanId
			);
		});

	});


	describe("Claim", function() {

		let loanMockFactory, loanMock;
		let loanId;

		before(async function() {
			loanMockFactory = await smock.mock("PWNLOAN");
		});

		beforeEach(async function() {
			loanMock = await loanMockFactory.deploy("https://test.uri");
			await loanMock.setPWN(pwn.address);

			offerHash = getOfferHashBytes(offer, loanMock.address);
			signature = await signOffer(offer, loanMock.address, lender);

			await loanMock.create(offer, signature, borrower.address);
			loanId = await loanMock.id();
		});


		it("Should fail when sender is not PWN contract", async function() {
			await expect(
				loanMock.connect(addr1).claim(loanId, lender.address)
			).to.be.revertedWith("Caller is not the PWN");
		});

		it("Should fail when sender is not loan owner", async function() {
			await expect(
				loanMock.claim(loanId, addr4.address)
			).to.be.revertedWith("Caller is not the loan owner");
		});

		it("Should fail when loan is not in paid back nor expired state", async function() {
			await loanMock.setVariable("LOANs", {
				1: {
					status: 2
				}
			});

			await expect(
				loanMock.claim(loanId, lender.address)
			).to.be.revertedWith("Loan can't be claimed yet");
		});

		it("Should be possible to claim expired loan", async function() {
			await loanMock.setVariable("LOANs", {
				1: {
					status: 4
				}
			});

			await loanMock.claim(loanId, lender.address);

			expect(true);
		});

		it("Should be possible to claim paid back loan", async function() {
			await loanMock.setVariable("LOANs", {
				1: {
					status: 3
				}
			});

			await loanMock.claim(loanId, lender.address);

			expect(true);
		});

		it("Should update loan to dead state", async function() {
			await loanMock.repayLoan(loanId);

			await loanMock.claim(loanId, lender.address);

			const status = (await loanMock.LOANs(loanId)).status;
			expect(status).to.equal(0);
		});

		it("Should emit `LOANClaimed` event", async function() {
			await loanMock.repayLoan(loanId);

			await expect(
				loanMock.claim(loanId, lender.address)
			).to.emit(loanMock, "LOANClaimed").withArgs(
				loanId
			);
		});

	});


	describe("Burn", function() { // -> PWN is trusted source so we believe that it would not send invalid data

		let loanMockFactory, loanMock;
		let loanId;

		before(async function() {
			loanMockFactory = await smock.mock("PWNLOAN");
		});

		beforeEach(async function() {
			loanMock = await loanMockFactory.deploy("https://test.uri");
			await loanMock.setPWN(pwn.address);

			offerHash = getOfferHashBytes(offer, loanMock.address);
			signature = await signOffer(offer, loanMock.address, lender);

			await loanMock.create(offer, signature, borrower.address);
			loanId = await loanMock.id();
		});


		it("Should fail when sender is not PWN contract", async function() {
			await expect(
				loanMock.connect(addr1).burn(loanId, lender.address)
			).to.be.revertedWith("Caller is not the PWN");
		});

		it("Should fail when passing address is not loan owner", async function() {
			await expect(
				loanMock.burn(loanId, addr4.address)
			).to.be.revertedWith("Caller is not the loan owner");
		});

		it("Should fail when loan is not in dead state", async function() {
			await loanMock.setVariable("LOANs", {
				1: {
					status: 2
				}
			});

			await expect(
				loanMock.burn(loanId, lender.address)
			).to.be.revertedWith("Loan can't be burned at this stage");
		});

		it("Should delete loan data", async function() {
			await loanMock.setVariable("LOANs", {
				1: {
					status: 0
				}
			});

			await loanMock.burn(loanId, lender.address);

			const loanToken = await loanMock.LOANs(loanId);
			expect(loanToken.expiration).to.equal(0);
			expect(loanToken.duration).to.equal(0);
			expect(loanToken.borrower).to.equal(ethers.constants.AddressZero);
			expect(loanToken.collateral.assetAddress).to.equal(ethers.constants.AddressZero);
			expect(loanToken.collateral.category).to.equal(0);
			expect(loanToken.collateral.id).to.equal(0);
			expect(loanToken.collateral.amount).to.equal(0);
		});

		it("Should burn loan ERC1155 token", async function() {
			await loanMock.setVariable("LOANs", {
				1: {
					status: 0
				}
			});

			await loanMock.burn(loanId, lender.address);

			const balance = await loanMock.balanceOf(lender.address, loanId);
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
				const loanRepayAmount = await loan.countLoanRepayAmount(loanAsset.amount, duration, loanYield, durationMax);

				expect(loanRepayAmount).to.equal(loanAsset.amount + Math.floor(loanYield * duration / durationMax));
			});

		});

	});


	describe("View functions", function() {

		let loanMockFactory, loanMock;
		const loanId = 1;

		before(async function() {
			loanMockFactory = await smock.mock("PWNLOAN");
		});

		beforeEach(async function() {
			loanMock = await loanMockFactory.deploy("https://test.uri");
			await loanMock.setPWN(pwn.address);
		});


		// VIEW FUNCTIONS - LOANS

		describe("Get loan status", function() {

			it("Should return none/dead state", async function() {
				await loanMock.setVariable("LOANs", {
					1: {
						status: 0
					}
				});

				const status = await loanMock.getStatus(loanId);

				expect(status).to.equal(0);
			});

			it("Should return running state when not expired", async function() {
				await loanMock.setVariable("LOANs", {
					1: {
						status: 2,
						expiration: await timestampFromNow(100)
					}
				});

				const status = await loanMock.getStatus(loanId);

				expect(status).to.equal(2);
			});

			it("Should return expired state when in running state", async function() {
				await loanMock.setVariable("LOANs", {
					1: {
						status: 2,
						expiration: 1
					}
				});

				const status = await loanMock.getStatus(loanId);

				expect(status).to.equal(4);
			});

			it("Should return paid back state when not expired", async function() {
				await loanMock.setVariable("LOANs", {
					1: {
						status: 3,
						expiration: await timestampFromNow(100)
					}
				});

				const status = await loanMock.getStatus(loanId);

				expect(status).to.equal(3);
			});

			it("Should return paid back state when expired", async function() {
				await loanMock.setVariable("LOANs", {
					1: {
						status: 3,
						expiration: 1
					}
				});

				const status = await loanMock.getStatus(loanId);

				expect(status).to.equal(3);
			});

		});


		describe("Get expiration", function() {

			it("Should return loan expiration", async function() {
				await loanMock.setVariable("LOANs", {
					1: {
						expiration: 3123
					}
				});

				const expiration = await loanMock.getExpiration(loanId);

				expect(expiration).to.equal(3123);
			});

		});

		describe("Get duration", function() {

			it("Should return loan duration", async function() {
				await loanMock.setVariable("LOANs", {
					1: {
						duration: 1111
					}
				});

				const loanDuration = await loanMock.getDuration(loanId);

				expect(loanDuration).to.equal(1111);
			});

		});


		describe("Get borrower", function() {

			it("Should return loan borrower address", async function() {
				await loanMock.setVariable("LOANs", {
					1: {
						borrower: borrower.address
					}
				});

				const borrowerAddress = await loanMock.getBorrower(loanId);

				expect(borrowerAddress).to.equal(borrower.address);
			});

		});


		describe("Get collateral asset", function() {

			// Smock doesn't support updating enums in storage
			xit("Should return loan collateral asset", async function() {
				await loanMock.setVariable("LOANs", {
					1: {
						collateral: {
							assetAddress: asset1.address,
							category: 1,
							amount: 123123,
							id: 9537
						}
					}
				});

				const collateral = await loanMock.getCollateral(loanId);

				expect(collateral.assetAddress).to.equal(asset1.address);
				expect(collateral.category).to.equal(1);
				expect(collateral.amount).to.equal(123123);
				expect(collateral.id).to.equal(9537);
			});

		});


		describe("Get loan asset", function() {

			// Smock doesn't support updating enums in storage
			xit("Should return loan loan asset", async function() {
				await loanMock.setVariable("LOANs", {
					1: {
						loan: {
							assetAddress: asset2.address,
							category: 0,
							amount: 8838,
							id: 0
						}
					}
				});

				const loanAsset = await loanMock.getLoanAsset(loanId);

				expect(loanAsset.assetAddress).to.equal(asset2.address);
				expect(loanAsset.category).to.equal(0);
				expect(loanAsset.amount).to.equal(8838);
				expect(loanAsset.id).to.equal(0);
			});

		});


		describe("Get loan repay amount", function() {

			it("Should return loan loan repay amount", async function() {
				await loanMock.setVariable("LOANs", {
					1: {
						loanRepayAmount: 88393993
					}
				});

				const loanRepayAmount = await loanMock.getLoanRepayAmount(loanId);

				expect(loanRepayAmount).to.equal(88393993);
			});

		});


		describe("Is offer revoked", function() {

			it("Should return true if offer is revoked", async function() {
				await loanMock.setVariable("revokedOffers", {
					"1d9c0a4fa5589519086c908b1a5f492d770c0fd4208dd36e9a84f5b2dab97ad9": true
				});

				const isRevoked = await loanMock.isRevoked("0x1d9c0a4fa5589519086c908b1a5f492d770c0fd4208dd36e9a84f5b2dab97ad9");

				expect(isRevoked).to.equal(true);
			});

		});

	});


	describe("Set PWN", function() {

		it("Should fail when sender is not owner", async function() {
			await expect(
				loan.connect(addr1).setPWN(addr2.address)
			).to.be.revertedWith("Ownable: caller is not the owner");
		});

		it("Should set PWN address", async function() {
			const formerPWN = await loan.PWN();

			await loan.connect(pwn).setPWN(addr1.address);

			const latterPWN = await loan.PWN();
			expect(formerPWN).to.not.equal(latterPWN);
			expect(latterPWN).to.equal(addr1.address);
		});

	});

	describe("Set new URI", function() {

		it("Should fail when sender is not owner", async function() {
			await expect(
				loan.connect(addr1).setUri("https://new.uri.com/loan/{id}")
			).to.be.revertedWith("Ownable: caller is not the owner");
		});

		it("Should set a new URI", async function() {
			const formerURI = await loan.uri(1);

			await loan.connect(pwn).setUri("https://new.uri.com/loan/{id}");

			const latterURI = await loan.uri(1);
			expect(formerURI).to.not.equal(latterURI);
			expect(latterURI).to.equal("https://new.uri.com/loan/{id}");
		});

	});
});
