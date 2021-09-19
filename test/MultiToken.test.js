const chai = require("chai");
const { ethers } = require("hardhat");
const { smock } = require("@defi-wonderland/smock");

const expect = chai.expect;
chai.use(smock.matchers);

describe("MultiToken library", function() {

	let MultiTokenAdapter;
	let multiTokenAdapter;
	let owner, addr1, addr2, addr3, addr4, addr5;

	before(async function() {
		MultiTokenAdapter = await ethers.getContractFactory("MultiTokenTestAdapter");
		[owner, addr1, addr2, addr3, addr4, addr5] = await ethers.getSigners();
	});

	beforeEach(async function() {
		multiTokenAdapter = await MultiTokenAdapter.deploy();
	});

	describe("Transfer", function() {
		it("Should call transfer on ERC20 token", async function () {
			const amount = 732;
			const fakeToken = await smock.fake("Basic20");
			fakeToken.transfer.returns(true);

			await multiTokenAdapter.transferAsset(0, amount, 0, fakeToken.address, addr1.address);

			expect(fakeToken.transfer).to.have.been.calledOnce;
			expect(fakeToken.transfer).to.have.been.calledWith(addr1.address, amount);
		});

		it("Should call transfer from current address on ERC721 token", async function() {
			const assetId = 2047;
			const fakeToken = await smock.fake("Basic721");

			await multiTokenAdapter.transferAsset(1, 1, assetId, fakeToken.address, addr1.address);

			expect(fakeToken.transferFrom).to.have.been.calledOnce;
			expect(fakeToken.transferFrom).to.have.been.calledWith(multiTokenAdapter.address, addr1.address, assetId);
		});

		it("Should call safe transfer from current address on ERC1155 token", async function() {
			const amount = 20;
			const assetId = 2047;
			const fakeToken = await smock.fake("Basic1155");

			await multiTokenAdapter.transferAsset(2, amount, assetId, fakeToken.address, addr1.address);

			expect(fakeToken.safeTransferFrom).to.have.been.calledOnce;
			expect(fakeToken.safeTransferFrom).to.have.been.calledWith(multiTokenAdapter.address, addr1.address, assetId, amount, "0x");
		});

		it("Should pass at least amount 1 on ERC1155 token transfer", async function() {
			const assetId = 2047;
			const fakeToken = await smock.fake("Basic1155");

			await multiTokenAdapter.transferAsset(2, 0, assetId, fakeToken.address, addr1.address);

			expect(fakeToken.safeTransferFrom).to.have.been.calledOnce;
			expect(fakeToken.safeTransferFrom).to.have.been.calledWith(multiTokenAdapter.address, addr1.address, assetId, 1, "0x");
		});

		it("Should fail when passing unsupported category", async function() {
			try {
				await multiTokenAdapter.transferAsset(3, 0, 0, addr4.address, addr1.address);
				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Unsupported category");
			}
		});
	});

	describe("TransferFrom", function() {
		it("Should call transfer from on ERC20 token", async function() {
			const amount = 732;
			const fakeToken = await smock.fake("Basic20");
			fakeToken.transferFrom.returns(true);

			await multiTokenAdapter.transferAssetFrom(0, amount, 0, fakeToken.address, addr1.address, addr2.address);

			expect(fakeToken.transferFrom).to.have.been.calledOnce;
			expect(fakeToken.transferFrom).to.have.been.calledWith(addr1.address, addr2.address, amount);
		});

		it("Should call transfer from on ERC721 token", async function() {
			const assetId = 2047;
			const fakeToken = await smock.fake("Basic721");

			await multiTokenAdapter.transferAssetFrom(1, 1, assetId, fakeToken.address, addr1.address, addr2.address);

			expect(fakeToken.transferFrom).to.have.been.calledOnce;
			expect(fakeToken.transferFrom).to.have.been.calledWith(addr1.address, addr2.address, assetId);
		});

		it("Should call safe transfer from on ERC1155 token", async function() {
			const amount = 20;
			const assetId = 2047;
			const fakeToken = await smock.fake("Basic1155");

			await multiTokenAdapter.transferAssetFrom(2, amount, assetId, fakeToken.address, addr1.address, addr2.address);

			expect(fakeToken.safeTransferFrom).to.have.been.calledOnce;
			expect(fakeToken.safeTransferFrom).to.have.been.calledWith(addr1.address, addr2.address, assetId, amount, "0x");
		});

		it("Should pass at least amount 1 on ERC1155 token transfer", async function() {
			const assetId = 2047;
			const fakeToken = await smock.fake("Basic1155");

			await multiTokenAdapter.transferAssetFrom(2, 0, assetId, fakeToken.address, addr1.address, addr2.address);

			expect(fakeToken.safeTransferFrom).to.have.been.calledOnce;
			expect(fakeToken.safeTransferFrom).to.have.been.calledWith(addr1.address, addr2.address, assetId, 1, "0x");
		});

		it("Should fail when passing unsupported category", async function() {
			try {
				await multiTokenAdapter.transferAssetFrom(3, 0, 0, addr4.address, addr1.address, addr2.address);
				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Unsupported category");
			}
		});
	});

	describe("BalanceOf", function() {
		it("Should return balance of ERC20 token", async function() {
			const amount = 888;
			const fakeToken = await smock.fake("Basic20");
			fakeToken.balanceOf.returns(amount);

			const balance = await multiTokenAdapter.balanceOf(0, 732, 0, fakeToken.address, addr1.address);

			expect(balance).to.equal(amount);
			expect(fakeToken.balanceOf).to.have.been.calledOnce;
			expect(fakeToken.balanceOf).to.have.been.calledWith(addr1.address);
		});

		it("Should return balance of 1 if target address is ERC721 token owner", async function() {
			const assetId = 123;
			const fakeToken = await smock.fake("Basic721");
			fakeToken.ownerOf.returns(addr1.address);

			const balance = await multiTokenAdapter.balanceOf(1, 1, assetId, fakeToken.address, addr1.address);

			expect(balance).to.equal(1);
			expect(fakeToken.ownerOf).to.have.been.calledOnce;
			expect(fakeToken.ownerOf).to.have.been.calledWith(assetId);
		});

		it("Should return balance of 0 if target address is not ERC721 token owner", async function() {
			const assetId = 123;
			const fakeToken = await smock.fake("Basic721");
			fakeToken.ownerOf.returns(addr2.address);

			const balance = await multiTokenAdapter.balanceOf(1, 1, assetId, fakeToken.address, addr1.address);

			expect(balance).to.equal(0);
			expect(fakeToken.ownerOf).to.have.been.calledOnce;
			expect(fakeToken.ownerOf).to.have.been.calledWith(assetId);
		});

		it("Should return balance of ERC1155 token", async function() {
			const assetId = 123;
			const amount = 24;
			const fakeToken = await smock.fake("Basic1155");
			fakeToken.balanceOf.returns(amount);

			const balance = await multiTokenAdapter.balanceOf(2, 732, assetId, fakeToken.address, addr1.address);

			expect(balance).to.equal(amount);
			expect(fakeToken.balanceOf).to.have.been.calledOnce;
			expect(fakeToken.balanceOf).to.have.been.calledWith(addr1.address, assetId);
		});

		it("Should fail when passing unsupported category", async function() {
			try {
				await multiTokenAdapter.balanceOf(3, 1, 0, addr4.address, addr1.address);
				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Unsupported category");
			}
		});
	});

	describe("ApproveAsset", function() {
		it("Should call approve on ERC20 token", async function() {
			const amount = 657;
			const fakeToken = await smock.fake("Basic20");
			fakeToken.approve.returns(true);

			await multiTokenAdapter.approveAsset(0, amount, 0, fakeToken.address, addr1.address);

			expect(fakeToken.approve).to.have.been.calledOnce;
			expect(fakeToken.approve).to.have.been.calledWith(addr1.address, amount);
		});

		it("Should call approve on ERC721 token", async function() {
			const assetId = 657;
			const fakeToken = await smock.fake("Basic721");

			await multiTokenAdapter.approveAsset(1, 0, assetId, fakeToken.address, addr1.address);

			expect(fakeToken.approve).to.have.been.calledOnce;
			expect(fakeToken.approve).to.have.been.calledWith(addr1.address, assetId);
		});

		it("Should call set approval for all on ERC1155 token", async function() {
			const fakeToken = await smock.fake("Basic1155");

			await multiTokenAdapter.approveAsset(2, 0, 657, fakeToken.address, addr1.address);

			expect(fakeToken.setApprovalForAll).to.have.been.calledOnce;
			expect(fakeToken.setApprovalForAll).to.have.been.calledWith(addr1.address, true);
		});

		it("Should fail when passing unsupported category", async function() {
			try {
				await multiTokenAdapter.approveAsset(3, 1, 0, addr4.address, addr1.address);
				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Unsupported category");
			}
		});
	});

});
