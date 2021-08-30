const { expect } = require("chai");

describe("MultiToken library", () => {

	describe("Transfer", () => {
		it("Should call transfer on ERC20 token");
		it("Should fail when passing ERC20 category without ERC20 token address");
		it("Should call transfer from current address on NFT");
		it("Should fail when passing NFT category without NFT address");
		it("Should call safe transfer from current address on ERC1155 token");
		it("SHould update amount on ERC1155 token transfer");
		it("Should fail when passing ERC1155 category without ERC1155 token address");
		it("Should fail when passing unsupported category");
	});

	describe("TransferFrom", () => {
		it("Should call transfer from on ERC20 token");
		it("Should fail when passing ERC20 category without ERC20 token address");
		it("Should call transfer from on NFT");
		it("Should fail when passing NFT category without NFT address");
		it("Should call safe transfer from on ERC1155 token");
		it("SHould update amount on ERC1155 token transfer");
		it("Should fail when passing ERC1155 category without ERC1155 token address");
		it("Should fail when passing unsupported category");
	});

	describe("BalanceOf", () => {
		it("Should return balance of ERC20 token");
		it("Should fail when passing ERC20 category without ERC20 token address");
		it("Should return ownership of NFT");
		it("Should fail when passing NFT category without NFT address");
		it("Should return balance ERC1155 token");
		it("Should fail when passing ERC1155 category without ERC1155 token address");
		it("Should fail when passing unsupported category");
	});

	describe("ApproveAsset", () => {
		it("Should call approve on ERC20 token");
		it("Should fail when passing ERC20 category without ERC20 token address");
		it("Should call approve on NFT");
		it("Should fail when passing NFT category without NFT address");
		it("Should call set approval for all on ERC1155 token");
		it("Should fail when passing ERC1155 category without ERC1155 token address");
		it("Should fail when passing unsupported category");
	});

});
