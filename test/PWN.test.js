const chai = require("chai");
const { ethers } = require("hardhat");
const { smock } = require("@defi-wonderland/smock");
const { time } = require('@openzeppelin/test-helpers');

const expect = chai.expect;
chai.use(smock.matchers);

describe("PWN contract", function() {

	const defaultDecimals = ethers.BigNumber.from(10).pow(18);
	const relativeRepayValueTests = [
		{
			vaultBalance: 635241,
			totalRelativeRepayValue: 635241,
		},
		{
			vaultBalance: 1,
			totalRelativeRepayValue: 1,
			relativeRepayValue: 1,
		},
		{
			vaultBalance: ethers.BigNumber.from(1_000_000_000).mul(defaultDecimals),
			totalRelativeRepayValue: ethers.BigNumber.from(1_000_000_000).mul(defaultDecimals),
			relativeRepayValue: ethers.BigNumber.from(1_234_876).mul(defaultDecimals),
		},
		{
			vaultBalance: ethers.constants.MaxUint256.div(ethers.BigNumber.from(10).pow(18)),
			totalRelativeRepayValue: ethers.constants.MaxUint256.div(ethers.BigNumber.from(10).pow(18)),
		},
		{
			vaultBalance: 6326,
			totalRelativeRepayValue: 12652,
		},
		{
			vaultBalance: 843,
			totalRelativeRepayValue: 421,
			relativeRepayValue: 390,
		},
		{
			vaultBalance: 1000,
			totalRelativeRepayValue: 500,
			relativeRepayValue: 322,
		},
		{
			vaultBalance: 300,
			totalRelativeRepayValue: 100,
			relativeRepayValue: 66,
		},
		{
			vaultBalance: 100,
			totalRelativeRepayValue: 300,
			relativeRepayValue: 210,
		},
		{
			vaultBalance: 700,
			totalRelativeRepayValue: 100,
			relativeRepayValue: 100,
		},
		{
			vaultBalance: 100,
			totalRelativeRepayValue: 700,
			relativeRepayValue: 537,
		},
		{
			vaultBalance: 900,
			totalRelativeRepayValue: 100,
			relativeRepayValue: 31,
		},
		{
			vaultBalance: 100,
			totalRelativeRepayValue: 900,
			relativeRepayValue: 53,
		},
		{
			vaultBalance: 1100,
			totalRelativeRepayValue: 100,
			relativeRepayValue: 98,
		},
		{
			vaultBalance: 100,
			totalRelativeRepayValue: 1100,
			relativeRepayValue: 883,
		},
		{
			vaultBalance: 1300,
			totalRelativeRepayValue: 100,
			relativeRepayValue: 23,
		},
		{
			vaultBalance: 100,
			totalRelativeRepayValue: 1300,
			relativeRepayValue: 863,
		},
		{
			vaultBalance: 3700,
			totalRelativeRepayValue: 100,
			relativeRepayValue: 77,
		},
		{
			vaultBalance: 100,
			totalRelativeRepayValue: 3700,
			relativeRepayValue: 2301,
		},
		{
			vaultBalance: 1,
			totalRelativeRepayValue: 100,
			relativeRepayValue: 20,
		},
		{
			vaultBalance: 100,
			totalRelativeRepayValue: 1,
			relativeRepayValue: 1,
		},
		{
			vaultBalance: ethers.BigNumber.from(25_000).mul(defaultDecimals),
			totalRelativeRepayValue: ethers.BigNumber.from(10_000).mul(defaultDecimals),
		},
		{
			vaultBalance: ethers.BigNumber.from(10_000).mul(defaultDecimals),
			totalRelativeRepayValue: ethers.BigNumber.from(25_000).mul(defaultDecimals),
		},
		{
			vaultBalance: ethers.BigNumber.from(10_000_000_000).mul(defaultDecimals),
			totalRelativeRepayValue: ethers.BigNumber.from(10_000_000_000).mul(defaultDecimals),
			relativeRepayValue: ethers.BigNumber.from(10_000_000_000).mul(defaultDecimals),
		},
		{
			vaultBalance: ethers.BigNumber.from(10_000_000_000).mul(defaultDecimals),
			totalRelativeRepayValue: ethers.BigNumber.from(12_000_000_000).mul(defaultDecimals),
			relativeRepayValue: ethers.BigNumber.from(9_000_000_000).mul(defaultDecimals),
		},
	];

	let pwn;
	let vaultFake;
	let deedFake;

	let PWN;
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


	describe("Create deed", function() {

		it("Should be able to create ERC20 deed", async function() {
			let failed = false;

			try {
				await pwn.createDeed(asset1.address, CATEGORY.ERC20, 3600, 0, 10);
			} catch {
				failed = true;
			}

			expect(failed).to.equal(false);
		});

		it("Should be able to create ERC721 deed", async function() {
			let failed = false;

			try {
				await pwn.createDeed(asset1.address, CATEGORY.ERC721, 3600, 10, 1);
			} catch {
				failed = true;
			}

			expect(failed).to.equal(false);
		});

		it("Should be able to create ERC1155 deed", async function() {
			let failed = false;

			try {
				await pwn.createDeed(asset1.address, CATEGORY.ERC1155, 3600, 10, 5);
			} catch {
				failed = true;
			}

			expect(failed).to.equal(false);
		});

		it("Should fail for unknown asset category", async function() {
			let failed;

			try {
				await pwn.createDeed(asset1.address, CATEGORY.unknown, 3600, 0, 10);
			} catch {
				failed = true;
			}

			expect(failed).to.equal(true);
		});

		it("Should call create on deed", async function() {
			const fakeToken = await smock.fake("ERC20");
			const fakeDid = 3;
			deedFake.create.returns(fakeDid);

			await pwn.connect(borrower).createDeed(asset1.address, CATEGORY.ERC20, 3600, 0, 10);

			expect(deedFake.create).to.have.been.calledOnceWith(asset1.address, CATEGORY.ERC20, 3600, 0, 10, borrower.address);
		});

		it("Should return newly created deed ID", async function() {
			const fakeDid = 3;
			deedFake.create.returns(fakeDid);

			const did = await pwn.callStatic.createDeed(asset1.address, CATEGORY.ERC20, 3600, 0, 10);

			expect(did).to.equal(fakeDid);
		});

		it("Should send borrower collateral to vault", async function() {
			const amount = 10;
			const collateral = {
				assetAddress: asset1.address,
				category: CATEGORY.ERC20,
				id: 1,
				amount: 10,
			};
			deedFake.getDeedCollateral.returns(collateral);

			await pwn.connect(borrower).createDeed(collateral.assetAddress, CATEGORY.ERC20, 3600, 0, amount);

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


		it("Should be able to make offer", async function() {
			await pwn.connect(lender).makeOffer(asset2.address, amount, did, toBePaid);

			expect(deedFake.makeOffer).to.have.been.calledOnceWith(asset2.address, amount, lender.address, did, toBePaid);
		});

		it("Should return new offer hash", async function() {
			const offer = await pwn.callStatic.makeOffer(asset1.address, 9, did, 10);

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
			deedFake.getOfferLoan.whenCalledWith(offerHash).returns({
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

	describe("Repay loan", function() {

		const did = 536;
		const amount = 1000;
		const toBePaid = 3700;
		const offerHash = "0xaaa7654321098765abcdeabababababababababa0987eff32109f76543a1aacc";
		let loan;
		let collateral;
		let fakeToken;
		let mockPwn;

		before(function() {
			collateral = {
				assetAddress: asset2.address,
				category: CATEGORY.ERC721,
				id: 123,
				amount: 1,
			};
		});

		beforeEach(async function() {
			const factory = await smock.mock("PWN");
			mockPwn = await factory.deploy(deedFake.address, vaultFake.address);

			fakeToken = await smock.fake("ERC20", {
				address: "0x0341dD503C5E633a4Cb7367709B60F072D6c7008"
			});
			fakeToken.balanceOf.whenCalledWith(vaultFake.address).returns(0);

			loan = {
				assetAddress: fakeToken.address,
				category: CATEGORY.ERC20,
				id: 0,
				amount: amount,
			};

			deedFake.getAcceptedOffer.whenCalledWith(did).returns(offerHash);
			deedFake.toBePaid.whenCalledWith(offerHash).returns(toBePaid);
			deedFake.getOfferLoan.whenCalledWith(offerHash).returns(loan);
			deedFake.getDeedCollateral.whenCalledWith(did).returns(collateral);
			deedFake.getBorrower.whenCalledWith(did).returns(borrower.address);

			vaultFake.pull.returns(true);
			vaultFake.push.returns(true);
		});


		it("Should update deed to paid back state", async function() {
			await mockPwn.connect(borrower).repayLoan(did);

			expect(deedFake.repayLoan).to.have.been.calledOnceWith(did);
		});

		it("Should send deed collateral from vault to borrower", async function() {
			await mockPwn.connect(borrower).repayLoan(did);

			const args = vaultFake.pull.getCall(0).args;
			expect(args._asset.assetAddress).to.equal(collateral.assetAddress);
			expect(args._asset.category).to.equal(collateral.category);
			expect(args._asset.id).to.equal(collateral.id);
			expect(args._asset.amount).to.equal(collateral.amount);
			expect(args._beneficiary).to.equal(borrower.address);
			expect(vaultFake.pull).to.have.been.calledAfter(deedFake.repayLoan);
		});

		it("Should send paid back amount from borrower to vault", async function() {
			await mockPwn.connect(borrower).repayLoan(did);

			const args = vaultFake.push.getCall(0).args;
			expect(args._asset.assetAddress).to.equal(loan.assetAddress);
			expect(args._asset.category).to.equal(loan.category);
			expect(args._asset.id).to.equal(loan.id);
			expect(args._asset.amount).to.equal(toBePaid);
			expect(args._origin).to.equal(borrower.address);
			expect(vaultFake.push).to.have.been.calledAfter(deedFake.repayLoan);
		});

		describe("Should set correct relative repay value", function() {

			const testsFirstLiq = [
				{
					vaultBalance: 0,
					totalRelativeRepayValue: 0,
				},
				{
					vaultBalance: 1,
					totalRelativeRepayValue: 0,
				},
				{
					vaultBalance: 0,
					totalRelativeRepayValue: 1,
				},
			];

			relativeRepayValueTests.concat(testsFirstLiq).forEach((test) => {
				it(`when total relative repay amount is ${test.totalRelativeRepayValue} and vault balance is ${test.vaultBalance}`, async function() {
					await mockPwn.setVariable("totalRelativeRepayValue", {
						"0x0341dD503C5E633a4Cb7367709B60F072D6c7008": test.totalRelativeRepayValue
					});
					fakeToken.balanceOf.whenCalledWith(vaultFake.address).returns(test.vaultBalance);

					await mockPwn.connect(borrower).repayLoan(did);

					// Set relative repay value
					let expectedRelativeRepayValue;
					if (test.totalRelativeRepayValue == 0 || test.vaultBalance == 0) {
						expectedRelativeRepayValue = toBePaid;
					} else {
						expectedRelativeRepayValue = Math.floor(toBePaid * (test.totalRelativeRepayValue / test.vaultBalance));
					}
					const relativeRepayValue = await mockPwn.relativeRepayValue(did);
					expect(relativeRepayValue.toNumber()).to.equal(expectedRelativeRepayValue);

					// Increase total relative repay value
					const totalRelativeRepayValue = await mockPwn.totalRelativeRepayValue(fakeToken.address);
					expect(totalRelativeRepayValue.toString()).to.equal(ethers.BigNumber.from(expectedRelativeRepayValue).add(test.totalRelativeRepayValue).toString());
				});
			});

		});

		it("Should return true if successful", async function() {
			const success = await mockPwn.connect(borrower).callStatic.repayLoan(did);

			expect(success).to.equal(true);
		});

	});


	describe("Claim deed", function() {

		const did = 987;
		const amount = 1234;
		const toBePaid = 4321;
		const offerHash = "0xaaa7654321098765abcdeabababababababababa0987eff32109f76543a1aacc";
		let loan;
		let collateral;
		let fakeToken;
		let mockPwn;

		before(function() {
			collateral = {
				assetAddress: asset2.address,
				category: CATEGORY.ERC721,
				id: 123,
				amount: 1,
			};
		});

		beforeEach(async function() {
			const factory = await smock.mock("PWN");
			mockPwn = await factory.deploy(deedFake.address, vaultFake.address);
			await mockPwn.setVariable("relativeRepayValue", {
				987: toBePaid
			});
			await mockPwn.setVariable("totalRelativeRepayValue", {
				"0x0341dD503C5E633a4Cb7367709B60F072D6c7008": toBePaid
			});

			fakeToken = await smock.fake("ERC20", {
				address: "0x0341dD503C5E633a4Cb7367709B60F072D6c7008"
			});
			fakeToken.balanceOf.whenCalledWith(vaultFake.address).returns(toBePaid);

			loan = {
				assetAddress: fakeToken.address,
				category: CATEGORY.ERC20,
				id: 0,
				amount: amount,
			};

			deedFake.getDeedStatus.whenCalledWith(did).returns(3);
			deedFake.getAcceptedOffer.whenCalledWith(did).returns(offerHash);
			deedFake.toBePaid.whenCalledWith(offerHash).returns(toBePaid);
			deedFake.getOfferLoan.whenCalledWith(offerHash).returns(loan);
			deedFake.getDeedCollateral.whenCalledWith(did).returns(collateral);

			vaultFake.pull.returns(true);
		});


		it("Should update deed to claimed state", async function() {
			await mockPwn.connect(lender).claimDeed(did);

			expect(deedFake.claim).to.have.been.calledOnceWith(did, lender.address);
		});

		it("Should send collateral from vault to lender when deed is expired", async function() {
			deedFake.getDeedStatus.whenCalledWith(did).returns(4);

			await mockPwn.connect(lender).claimDeed(did);

			expect(vaultFake.pull).to.have.been.calledOnce;
			expect(vaultFake.pull).to.have.been.calledAfter(deedFake.claim);
			const args = vaultFake.pull.getCall(0).args;
			expect(args._asset.assetAddress).to.equal(collateral.assetAddress);
			expect(args._asset.category).to.equal(collateral.category);
			expect(args._asset.id).to.equal(collateral.id);
			expect(args._asset.amount).to.equal(collateral.amount);
			expect(args._beneficiary).to.equal(lender.address);
		});

		it("Should send loan asset from vault to lender when deed is paid back", async function() {
			deedFake.getDeedStatus.whenCalledWith(did).returns(3);

			await mockPwn.connect(lender).claimDeed(did);

			expect(vaultFake.pull).to.have.been.calledOnce;
			expect(vaultFake.pull).to.have.been.calledAfter(deedFake.claim);
			const args = vaultFake.pull.getCall(0).args;
			expect(args._asset.assetAddress).to.equal(loan.assetAddress);
			expect(args._asset.category).to.equal(loan.category);
			expect(args._asset.id).to.equal(loan.id);
		});

		describe("Should send correct amount from vault to lender when deed is paid back", function() {

			relativeRepayValueTests.forEach((test) => {
				it(`when total relative repay amount is ${test.totalRelativeRepayValue} and vault balance is ${test.vaultBalance}`, async function() {
					await mockPwn.setVariable("relativeRepayValue", {
						987: test.relativeRepayValue || toBePaid
					});
					await mockPwn.setVariable("totalRelativeRepayValue", {
						"0x0341dD503C5E633a4Cb7367709B60F072D6c7008": test.totalRelativeRepayValue
					});
					fakeToken.balanceOf.whenCalledWith(vaultFake.address).returns(test.vaultBalance);

					await mockPwn.connect(lender).claimDeed(did);

					// Claimable amount
					let expectedCreditAmount;
					if (ethers.BigNumber.isBigNumber(test.relativeRepayValue)) {
						expectedCreditAmount = test.relativeRepayValue.mul(test.vaultBalance).div(test.totalRelativeRepayValue).toString();
					} else {
						expectedCreditAmount = Math.floor((test.relativeRepayValue || toBePaid) * test.vaultBalance / test.totalRelativeRepayValue).toString();
					}
					const args = vaultFake.pull.getCall(0).args;
					expect(args._asset.amount.toString()).to.equal(expectedCreditAmount);

					// Decrease total relative repay value
					const totalRelativeRepayValue = await mockPwn.totalRelativeRepayValue(fakeToken.address);
					expect(totalRelativeRepayValue.toString()).to.equal(ethers.BigNumber.from(test.totalRelativeRepayValue).sub(test.relativeRepayValue || toBePaid).toString());

					// Reset relative repay value
					const relativeRepayValue = await mockPwn.relativeRepayValue(did);
					expect(relativeRepayValue.toNumber()).to.equal(0);
				});
			});

		});

		it("Should burn deed token", async function() {
			await mockPwn.connect(lender).claimDeed(did);

			expect(deedFake.burn).to.have.been.calledOnceWith(did, lender.address);
			expect(deedFake.burn).to.have.been.calledAfter(vaultFake.pull);
		});

		it("Should return true if successful", async function() {
			const success = await mockPwn.connect(lender).callStatic.claimDeed(did);

			expect(success).to.equal(true);
		});

	});

});
