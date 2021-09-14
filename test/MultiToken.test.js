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

		it("Should fail when passing ERC20 category without ERC20 token address", async function() {
			const fakeToken = await smock.fake("Basic721");

			try {
				await multiTokenAdapter.transferAsset(0, 1, 0, fakeToken.address, addr1.address);
				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
			}
		});

		it("Should call safe transfer from current address on ERC721 token", async function() {
			const assetId = 2047;
			const fakeToken = await smock.fake("Basic721");

			await multiTokenAdapter.transferAsset(1, 1, assetId, fakeToken.address, addr1.address);

			expect(fakeToken["safeTransferFrom(address,address,uint256)"]).to.have.been.calledOnce;
			expect(fakeToken["safeTransferFrom(address,address,uint256)"]).to.have.been.calledWith(multiTokenAdapter.address, addr1.address, assetId);
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
			const fakeToken = await smock.fake("Basic20");

			try {
				await multiTokenAdapter.transferAsset(3, 0, 0, fakeToken.address, addr1.address);
				expect.fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Unsupported category");
			}
		});
	});

	describe("TransferFrom", function() {
		it("Should call transfer from on ERC20 token");
		it("Should fail when passing ERC20 category without ERC20 token address");
		it("Should call safe transfer from on ERC721 token");
		it("Should fail when passing ERC721 category without ERC721 address");
		it("Should call safe transfer from on ERC1155 token");
		it("Should update amount on ERC1155 token transfer");
		it("Should fail when passing ERC1155 category without ERC1155 token address");
		it("Should fail when passing unsupported category");
	});

	describe("BalanceOf", function() {
		it("Should return balance of ERC20 token");
		it("Should fail when passing ERC20 category without ERC20 token address");
		it("Should return ownership of ERC721 token");
		it("Should fail when passing ERC721 category without ERC721 address");
		it("Should return balance ERC1155 token");
		it("Should fail when passing ERC1155 category without ERC1155 token address");
		it("Should fail when passing unsupported category");
	});

	describe("ApproveAsset", function() {
		it("Should call approve on ERC20 token");
		it("Should fail when passing ERC20 category without ERC20 token address");
		it("Should call approve on ERC721 token");
		it("Should fail when passing ERC721 category without ERC721 address");
		it("Should call set approval for all on ERC1155 token");
		it("Should fail when passing ERC1155 category without ERC1155 token address");
		it("Should fail when passing unsupported category");
	});

});
