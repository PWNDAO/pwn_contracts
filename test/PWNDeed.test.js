const { expect } = require("chai");

describe("PWNDeed contract", function() {

	describe("Constructor", function() {
		it("Should set correct owner");
		it("Should set correct uri");
	});

	describe("Mint", function() {
		it("Should fail when sender is not PWN contract"); // -> PWN is trusted source so we believe that it would not send invalid data
		it("Should mint deed ERC1155 token");
		it("Should save deed data");
		it("Should return minted deed ID");
	});

	describe("Burn", function() {
		it("Should fail when sender is not PWN contract"); // -> PWN is trusted source so we believe that it would not send invalid data
		it("Should burn deed ERC1155 token");
		it("Should delete deed data");
	});

	describe("Set offer", function() {
		it("Should fail when sender is not PWN contract"); // -> PWN is trusted source so we believe that it would not send invalid data
		it("Should save offer data");
		it("Should set offer to deed");
		it("Should return offer hash as bytes");
	});

	describe("Delete offer", function() {
		it("Should fail when sender is not PWN contract"); // -> PWN is trusted source so we believe that it would not send invalid data
		it("Should delete offer");
	});

	describe("Set credit", function() {
		it("Should fail when sender is not PWN contract"); // -> PWN is trusted source so we believe that it would not send invalid data
		it("Should set offer as accepted in deed");
		it("Should delete deed pending offers");
	});

	describe("Change status", function() {
		it("Should fail when sender is not PWN contract"); // -> PWN is trusted source so we believe that it would not send invalid data
		it("Should set deed state");
	});

	// should we test function beforeTokenTransfer??

	describe("Get deed status", function() {
		it("Should return none/dead state");
		it("Should return new/open state");
		it("Should return running state");
		it("Should return paid back state");
		it("Should return expired state");
	});

	describe("Get expiration", function() {
		it("Should return deed expiration");
	});
	
	describe("Get borrower", function() {
		it("Should return borrower address");
	});
	
	describe("Get deed asset", function() {
		it("Should return deed asset");
	});

	describe("Get offers", function() {
		it("Should return deed pending offers byte array");
	});

	describe("Get accepted offer", function() {
		it("Should return deed accepted offer");
	});

	describe("Get deed ID", function() {
		it("Should return deed ID");
	});

	describe("Get offer asset", function() {
		it("Should return offer asset");
	});

	describe("To be paid", function() {
		it("Should return offer to be paid value");
	});

	describe("Get lender", function() {
		it("Should return lender address");
	});

	describe("Set PWN", function() {
		it("Should fail when sender is not owner");
		it("Should set PWN address");
	});

});
