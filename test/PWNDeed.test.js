const { expect } = require("chai");

describe("PWNDeed contract", () => {

	describe("Constructor", () => {
		it("Should set correct owner");
		it("Should set correct uri");
	});

	describe("Mint", () => {
		it("Should fail when sender is not PWN contract"); // -> PWN is trusted source so we believe that it would not send invalid data
		it("Should mint deed ERC1155 token");
		it("Should save deed data");
		it("Should return minted deed ID");
	});

	describe("Burn", () => {
		it("Should fail when sender is not PWN contract"); // -> PWN is trusted source so we believe that it would not send invalid data
		it("Should burn deed ERC1155 token");
		it("Should delete deed data");
	});

	describe("Set offer", () => {
		it("Should fail when sender is not PWN contract"); // -> PWN is trusted source so we believe that it would not send invalid data
		it("Should save offer data");
		it("Should set offer to deed");
		it("Should return offer hash as bytes");
	});

	describe("Delete offer", () => {
		it("Should fail when sender is not PWN contract"); // -> PWN is trusted source so we believe that it would not send invalid data
		it("Should delete offer");
	});

	describe("Set credit", () => {
		it("Should fail when sender is not PWN contract"); // -> PWN is trusted source so we believe that it would not send invalid data
		it("Should set offer as accepted in deed");
		it("Should delete deed pending offers");
	});

	describe("Change status", () => {
		it("Should fail when sender is not PWN contract"); // -> PWN is trusted source so we believe that it would not send invalid data
		it("Should set deed state");
	});

	// should we test function beforeTokenTransfer??

	describe("Get deed status", () => {
		it("Should return none/dead state");
		it("Should return new/open state");
		it("Should return running state");
		it("Should return paid back state");
		it("Should return expired state");
	});

	describe("Get expiration", () => {
		it("Should return deed expiration");
	});
	
	describe("Get borrower", () => {
		it("Should return borrower address");
	});
	
	describe("Get deed asset", () => {
		it("Should return deed asset");
	});

	describe("Get offers", () => {
		it("Should return deed pending offers byte array");
	});

	describe("Get accepted offer", () => {
		it("Should return deed accepted offer");
	});

	describe("Get deed ID", () => {
		it("Should return deed ID");
	});

	describe("Get offer asset", () => {
		it("Should return offer asset");
	});

	describe("To be paid", () => {
		it("Should return offer to be paid value");
	});

	describe("Get lender", () => {
		it("Should return lender address");
	});

	describe("Set PWN", () => {
		it("Should fail when sender is not owner");
		it("Should set PWN address");
	});

});
