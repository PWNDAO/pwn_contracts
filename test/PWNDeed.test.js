const chai = require("chai");
const { ethers } = require("hardhat");
const { smock } = require("@defi-wonderland/smock");
const { time } = require('@openzeppelin/test-helpers');
const { CATEGORY, timestampFromNow, getOfferHashBytes } = require("./test-helpers");

const expect = chai.expect;
chai.use(smock.matchers);


describe("PWNDeed contract", function() {

	let Deed, deed, deedEventIface;
	let pwn, lender, borrower, asset1, asset2, addr1, addr2, addr3, addr4, addr5;
	let offer, offerHash, signature, loan, collateral;

	const duration = 31323;
	const loanRepayAmount = 2222;
	const offerExpiration = 0;
	const nonce = 1;

	before(async function() {
		Deed = await ethers.getContractFactory("PWNDeed");
		[pwn, lender, borrower, asset1, asset2, addr1, addr2, addr3, addr4, addr5] = await ethers.getSigners();

		deedEventIface = new ethers.utils.Interface([
			"event DeedCreated(uint256 indexed did, address indexed lender, bytes32 indexed offerHash)",
			"event OfferRevoked(bytes32 indexed offerHash)",
			"event PaidBack(uint256 did)",
			"event DeedClaimed(uint256 did)",
		]);

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
		deed = await Deed.deploy("https://test.uri");
		await deed.setPWN(pwn.address);

		offer = [
			[collateral.assetAddress, collateral.category, collateral.amount, collateral.id],
			[loan.assetAddress, 0, loan.amount, 0],
			loanRepayAmount,
			duration,
			offerExpiration,
			lender.address,
			nonce,
			31337,
		];

		offerHash = getOfferHashBytes(offer);
		signature = await lender.signMessage(offerHash);
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


	describe("Revoke offer", function() { // -> PWN is trusted source so we believe that it would not send invalid data

		it("Should fail when sender is not PWN contract", async function() {
			try {
				await deed.connect(addr1).revokeOffer(offerHash, signature, lender.address);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Caller is not the PWN");
			}
		});

		it("Should fail when lender is not the offer signer", async function() {
			try {
				await deed.revokeOffer(offerHash, signature, borrower.address);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Sender is not an offer signer");
			}
		});

		it("Should fail with invalid signature", async function() {
			const fakeSignature = "0x6732801029378ddf837210000397c68129387fd887839708320980942102910a6732801029378ddf837210000397c68129387fd887839708320980942102910a00";

			try {
				await deed.revokeOffer(offerHash, fakeSignature, lender.address);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("ECDSA: invalid signature");
			}
		});

		it("Should fail if offer is already revoked", async function() {
			await deed.revokeOffer(offerHash, signature, lender.address);

			try {
				await deed.revokeOffer(offerHash, signature, lender.address);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Offer is already revoked or has been accepted");
			}
		});

		it("Should set offer as revoked", async function() {
			await deed.revokeOffer(offerHash, signature, lender.address);

			const isRevoked = await deed.revokedOffers(offerHash);
			expect(isRevoked).to.equal(true);
		});

		it("Should emit OfferRevoked event", async function() {
			const tx = await deed.revokeOffer(offerHash, signature, lender.address);
			const response = await tx.wait();

			expect(response.logs.length).to.equal(1);
			const logDescription = deedEventIface.parseLog(response.logs[0]);
			expect(logDescription.name).to.equal("OfferRevoked");
			const args = logDescription.args;
			expect(args.offerHash).to.equal(ethers.utils.hexValue(offerHash));
		});

	});


	describe("Create", function() { // -> PWN is trusted source so we believe that it would not send invalid data

		it("Should fail when sender is not PWN contract", async function() {
			try {
				await deed.connect(addr1).create(offer, signature, borrower.address);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Caller is not the PWN");
			}
		});

		it("Should fail when offer lender is not offer signer", async function() {
			offer[5] = addr1.address;

			try {
				await deed.create(offer, signature, borrower.address);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Lender address didn't sign the offer");
			}
		});

		it("Should fail when given invalid signature", async function() {
			const fakeSignature = "0x6732801029378ddf837210000397c68129387fd887839708320980942102910a6732801029378ddf837210000397c68129387fd887839708320980942102910a00";

			try {
				await deed.create(offer, fakeSignature, borrower.address);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("ECDSA: invalid signature");
			}
		});

		it("Should fail when offer is expired", async function() {
			offer[4] = 1;
			offerHash = getOfferHashBytes(offer);
			signature = await lender.signMessage(offerHash);

			try {
				await deed.create(offer, signature, borrower.address);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Offer is expired");
			}
		});

		it("Should pass when offer has expiration but is not expired", async function() {
			const expiration = await timestampFromNow(100);
			offer[4] = expiration;
			offerHash = getOfferHashBytes(offer);
			signature = await lender.signMessage(offerHash);
			let failed = false;

			try {
				await deed.create(offer, signature, borrower.address);
			} catch {
				failed = true;
			}

			expect(failed).to.equal(false);
		});

		it("Should fail when offer is revoked", async function() {
			await deed.revokeOffer(offerHash, signature, lender.address);

			try {
				await deed.create(offer, signature, borrower.address);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Offer is revoked or has been accepted");
			}
		});

		it("Should revoke accepted offer", async function() {
			await deed.create(offer, signature, borrower.address);

			const isRevoked = await deed.revokedOffers(offerHash);
			expect(isRevoked).to.equal(true);
		});

		it("Should mint deed ERC1155 token", async function () {
			await deed.create(offer, signature, borrower.address);
			const did = await deed.id();

			const balance = await deed.balanceOf(lender.address, did);
			expect(balance).to.equal(1);
		});

		it("Should save deed data", async function () {
			await deed.create(offer, signature, borrower.address);
			const expiration = await timestampFromNow(duration);
			const did = await deed.id();

			const deedToken = await deed.deeds(did);
			expect(deedToken.status).to.equal(2);
			expect(deedToken.borrower).to.equal(borrower.address);
			expect(deedToken.duration).to.equal(duration);
			expect(deedToken.expiration).to.equal(expiration);
			expect(deedToken.collateral.assetAddress).to.equal(collateral.assetAddress);
			expect(deedToken.collateral.category).to.equal(collateral.category);
			expect(deedToken.collateral.id).to.equal(collateral.id);
			expect(deedToken.collateral.amount).to.equal(collateral.amount);
			expect(deedToken.loan.assetAddress).to.equal(loan.assetAddress);
			expect(deedToken.loan.category).to.equal(loan.category);
			expect(deedToken.loan.id).to.equal(loan.id);
			expect(deedToken.loan.amount).to.equal(loan.amount);
			expect(deedToken.loanRepayAmount).to.equal(loanRepayAmount);
		});

		it("Should increase global deed ID", async function() {
			await deed.create(offer, signature, borrower.address);
			const did1 = await deed.id();

			offer[6] = 2;
			offerHash = getOfferHashBytes(offer);
			signature = await lender.signMessage(offerHash);

			await deed.create(offer, signature, borrower.address);
			const did2 = await deed.id();

			expect(did2).to.equal(did1.add(1));
		});

		it("Should emit DeedCreated event", async function() {
			const tx = await deed.create(offer, signature, borrower.address);
			const response = await tx.wait();
			const did = await deed.id();

			expect(response.logs.length).to.equal(2);
			const logDescription = deedEventIface.parseLog(response.logs[1]);
			expect(logDescription.name).to.equal("DeedCreated");
			expect(logDescription.args.did).to.equal(did);
			expect(logDescription.args.lender).to.equal(lender.address);
			expect(logDescription.args.offerHash).to.equal(ethers.utils.hexValue(offerHash));
		});

	});


	describe("Repay loan", function() {

		let did;

		beforeEach(async function() {
			await deed.create(offer, signature, borrower.address);
			did = await deed.id();
		});


		it("Should fail when sender is not PWN contract", async function() {
			try {
				await deed.connect(addr1).repayLoan(did);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Caller is not the PWN");
			}
		});

		it("Should fail when deed is not in running state", async function() {
			const deedMockFactory = await smock.mock("PWNDeed");
			const deedMock = await deedMockFactory.deploy("https://test.uri");
			await deedMock.setPWN(pwn.address);
			await deedMock.setVariable("deeds", {
				1: {
					status: 3
				}
			});

			try {
				await deedMock.repayLoan(did);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Deed is not running and cannot be paid back");
			}
		});

		it("Should update deed to paid back state", async function() {
			await deed.repayLoan(did);

			const status = (await deed.deeds(did)).status;
			expect(status).to.equal(3);
		});

		it("Should emit PaidBack event", async function() {
			const tx = await deed.repayLoan(did);
			const response = await tx.wait();

			expect(response.logs.length).to.equal(1);
			const logDescription = deedEventIface.parseLog(response.logs[0]);
			expect(logDescription.name).to.equal("PaidBack");
			const args = logDescription.args;
			expect(args.did).to.equal(did);
		});

	});


	describe("Claim", function() {

		let deedMockFactory, deedMock;
		let did;

		before(async function() {
			deedMockFactory = await smock.mock("PWNDeed");
		});

		beforeEach(async function() {
			deedMock = await deedMockFactory.deploy("https://test.uri");
			await deedMock.setPWN(pwn.address);

			await deedMock.create(offer, signature, borrower.address);
			did = await deedMock.id();
		});


		it("Should fail when sender is not PWN contract", async function() {
			try {
				await deedMock.connect(addr1).claim(did, lender.address);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Caller is not the PWN");
			}
		});

		it("Should fail when sender is not deed owner", async function() {
			try {
				await deedMock.claim(did, addr4.address);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Caller is not the deed owner");
			}
		});

		it("Should fail when deed is not in paid back nor expired state", async function() {
			await deedMock.setVariable("deeds", {
				1: {
					status: 2
				}
			});

			try {
				await deedMock.claim(did, lender.address);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Deed can't be claimed yet");
			}
		});

		it("Should be possible to claim expired deed", async function() {
			await deedMock.setVariable("deeds", {
				1: {
					status: 4
				}
			});

			await deedMock.claim(did, lender.address);

			expect(true);
		});

		it("Should be possible to claim paid back deed", async function() {
			await deedMock.setVariable("deeds", {
				1: {
					status: 3
				}
			});

			await deedMock.claim(did, lender.address);

			expect(true);
		});

		it("Should update deed to dead state", async function() {
			await deedMock.repayLoan(did);

			await deedMock.claim(did, lender.address);

			const status = (await deedMock.deeds(did)).status;
			expect(status).to.equal(0);
		});

		it("Should emit DeedClaimed event", async function() {
			await deedMock.repayLoan(did);

			const tx = await deedMock.claim(did, lender.address);
			const response = await tx.wait();

			expect(response.logs.length).to.equal(1);
			const logDescription = deedEventIface.parseLog(response.logs[0]);
			expect(logDescription.name).to.equal("DeedClaimed");
			const args = logDescription.args;
			expect(args.did).to.equal(did);
		});

	});


	describe("Burn", function() { // -> PWN is trusted source so we believe that it would not send invalid data

		let deedMockFactory, deedMock;
		let did;

		before(async function() {
			deedMockFactory = await smock.mock("PWNDeed");
		});

		beforeEach(async function() {
			deedMock = await deedMockFactory.deploy("https://test.uri");
			await deedMock.setPWN(pwn.address);

			await deedMock.create(offer, signature, borrower.address);
			did = await deedMock.id();
		});


		it("Should fail when sender is not PWN contract", async function() {
			try {
				await deedMock.connect(addr1).burn(did, lender.address);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Caller is not the PWN");
			}
		});

		it("Should fail when passing address is not deed owner", async function() {
			try {
				await deedMock.burn(did, addr4.address);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Caller is not the deed owner");
			}
		});

		it("Should fail when deed is not in dead state", async function() {
			await deedMock.setVariable("deeds", {
				1: {
					status: 2
				}
			});

			try {
				await deedMock.burn(did, lender.address);

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Deed can't be burned at this stage");
			}
		});

		it("Should delete deed data", async function() {
			await deedMock.setVariable("deeds", {
				1: {
					status: 0
				}
			});

			await deedMock.burn(did, lender.address);

			const deedToken = await deedMock.deeds(did);
			expect(deedToken.expiration).to.equal(0);
			expect(deedToken.duration).to.equal(0);
			expect(deedToken.borrower).to.equal(ethers.constants.AddressZero);
			expect(deedToken.collateral.assetAddress).to.equal(ethers.constants.AddressZero);
			expect(deedToken.collateral.category).to.equal(0);
			expect(deedToken.collateral.id).to.equal(0);
			expect(deedToken.collateral.amount).to.equal(0);
		});

		it("Should burn deed ERC1155 token", async function() {
			await deedMock.setVariable("deeds", {
				1: {
					status: 0
				}
			});

			await deedMock.burn(did, lender.address);

			const balance = await deedMock.balanceOf(lender.address, did);
			expect(balance).to.equal(0);
		});

	});


	describe("View functions", function() {

		let deedMockFactory, deedMock;
		const did = 1;

		before(async function() {
			deedMockFactory = await smock.mock("PWNDeed");
		});

		beforeEach(async function() {
			deedMock = await deedMockFactory.deploy("https://test.uri");
			await deedMock.setPWN(pwn.address);
		});


		// VIEW FUNCTIONS - DEEDS

		describe("Get deed status", function() {

			it("Should return none/dead state", async function() {
				await deedMock.setVariable("deeds", {
					1: {
						status: 0
					}
				});

				const status = await deedMock.getStatus(did);

				expect(status).to.equal(0);
			});

			it("Should return running state when not expired", async function() {
				await deedMock.setVariable("deeds", {
					1: {
						status: 2,
						expiration: await timestampFromNow(100)
					}
				});

				const status = await deedMock.getStatus(did);

				expect(status).to.equal(2);
			});

			it("Should return expired state when in running state", async function() {
				await deedMock.setVariable("deeds", {
					1: {
						status: 2,
						expiration: 1
					}
				});

				const status = await deedMock.getStatus(did);

				expect(status).to.equal(4);
			});

			it("Should return paid back state when not expired", async function() {
				await deedMock.setVariable("deeds", {
					1: {
						status: 3,
						expiration: await timestampFromNow(100)
					}
				});

				const status = await deedMock.getStatus(did);

				expect(status).to.equal(3);
			});

			it("Should return paid back state when expired", async function() {
				await deedMock.setVariable("deeds", {
					1: {
						status: 3,
						expiration: 1
					}
				});

				const status = await deedMock.getStatus(did);

				expect(status).to.equal(3);
			});

		});


		describe("Get expiration", function() {

			it("Should return deed expiration", async function() {
				await deedMock.setVariable("deeds", {
					1: {
						expiration: 3123
					}
				});

				const expiration = await deedMock.getExpiration(did);

				expect(expiration).to.equal(3123);
			});

		});

		describe("Get duration", function() {

			it("Should return deed duration", async function() {
				await deedMock.setVariable("deeds", {
					1: {
						duration: 1111
					}
				});

				const deedDuration = await deedMock.getDuration(did);

				expect(deedDuration).to.equal(1111);
			});

		});


		describe("Get borrower", function() {

			it("Should return deed borrower address", async function() {
				await deedMock.setVariable("deeds", {
					1: {
						borrower: borrower.address
					}
				});

				const borrowerAddress = await deedMock.getBorrower(did);

				expect(borrowerAddress).to.equal(borrower.address);
			});

		});


		describe("Get collateral asset", function() {

			// Smock doesn't support updating enums in storage
			xit("Should return deed collateral asset", async function() {
				await deedMock.setVariable("deeds", {
					1: {
						collateral: {
							assetAddress: asset1.address,
							category: 1,
							amount: 123123,
							id: 9537
						}
					}
				});

				const collateral = await deedMock.getCollateral(did);

				expect(collateral.assetAddress).to.equal(asset1.address);
				expect(collateral.category).to.equal(1);
				expect(collateral.amount).to.equal(123123);
				expect(collateral.id).to.equal(9537);
			});

		});


		describe("Get loan asset", function() {

			// Smock doesn't support updating enums in storage
			xit("Should return deed loan asset", async function() {
				await deedMock.setVariable("deeds", {
					1: {
						loan: {
							assetAddress: asset2.address,
							category: 0,
							amount: 8838,
							id: 0
						}
					}
				});

				const loan = await deedMock.getLoan(did);

				expect(loan.assetAddress).to.equal(asset2.address);
				expect(loan.category).to.equal(0);
				expect(loan.amount).to.equal(8838);
				expect(loan.id).to.equal(0);
			});

		});


		describe("Get loan repay amount", function() {

			it("Should return deed loan repay amount", async function() {
				await deedMock.setVariable("deeds", {
					1: {
						loanRepayAmount: 88393993
					}
				});

				const loanRepayAmount = await deedMock.getLoanRepayAmount(did);

				expect(loanRepayAmount).to.equal(88393993);
			});

		});


		describe("Is offer revoked", function() {

			it("Should return true if offer is revoked", async function() {
				await deedMock.setVariable("revokedOffers", {
					"1d9c0a4fa5589519086c908b1a5f492d770c0fd4208dd36e9a84f5b2dab97ad9": true
				});

				const isRevoked = await deedMock.isRevoked("0x1d9c0a4fa5589519086c908b1a5f492d770c0fd4208dd36e9a84f5b2dab97ad9");

				expect(isRevoked).to.equal(true);
			});

		});

	});


	describe("Set PWN", function() {

		it("Should fail when sender is not owner", async function() {
			try {
				await deed.connect(addr1).setPWN(addr2.address);

				expect.fail();
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

	describe("Set new URI", function() {

		it("Should fail when sender is not owner", async function() {
			try {
				await deed.connect(addr1).setUri("https://new.uri.com/deed/{id}");

				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Ownable: caller is not the owner");
			}
		});

		it("Should set a new URI", async function() {
			const formerURI = await deed.uri(1);

			await deed.connect(pwn).setUri("https://new.uri.com/deed/{id}");

			const latterURI = await deed.uri(1);
			expect(formerURI).to.not.equal(latterURI);
			expect(latterURI).to.equal("https://new.uri.com/deed/{id}");
		});

	});
});
