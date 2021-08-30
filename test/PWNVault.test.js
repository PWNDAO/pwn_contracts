const { expect } = require("chai");

describe("PWNVault contract", () => {

	describe("Constructor", () => {
		it("Should set correct owner");
	});

	describe("Push", () => {
		it("Should fail when sender is not PWN contract");
		it("Should send asset from address to vault");
		it("Should emit VaultPush event");
		it("Should return true if successful");
	});

	describe("Pull", () => {
		it("Should fail when sender is not PWN contract");
		it("Should send asset from vault to address");
		it("Should emit VaultPull event");
		it("Should return true if successful");
	});

	describe("PullProxy", () => {
		it("Should fail when sender is not PWN contract");
		it("Should send asset from address to address");
		it("Should emit VaultProxy event");
		it("Should return true if successful");
	});

	describe("On ERC1155 received", () => {
		it("Should return correct bytes");
	});

	describe("On ERC1155 batch received", () => {
		it("Should return correct bytes");
	});

	describe("Set PWN", () => {
		it("Should fail when sender is not owner");
		it("Should set PWN address");
	});

	describe("Supports interface", () => {
		it("Should return true for supported interfaces");
	});

});
