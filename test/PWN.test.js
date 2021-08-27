const { expect } = require("chai");

describe("PWN contract", function() {

	describe("New deed", function() {
		it("Should be able to create ERC20 deed");
		it("Should be able to create NFT deed");
		it("Should be able to crate ERC1155 deed");
		it("Should fail for unknown asset category");
		it("Should fail for expiration duration smaller than min duration");
		it("Should emit NewDeed event");
		it("Should return newly created deed ID");
		it("Should send borrower collateral to vault");
		it("Should mint new deed in correct state");
	});

	describe("Revoke deed", function() {
		it("Should fail when sender is not borrower");
		it("Should fail when deed is not in new/open state");
		it("Should send deed collateral to borrower from vault");
		it("Should burn deed token");
		it("Should emit DeedRevoked event");
	});

	describe("Make offer", function() {
		it("Should be able to make ERC20 offer");
		it("Should be able to make NFT offer");
		it("Should be able to make ERC1155 offer");
		it("Should fail for unknown asset category");
		it("Should fail when deed is not in new/open state");
		it("Should set new offer to the deed");
		it("Should emit NewOffer event");
		it("Should return new offer hash as bytes");
	});

	describe("Revoke offer", function() {
		it("Should fail when sender is not the offer maker");
		it("Should fail when deed of the offer is not in new/open state");
		it("Should remove offer from deed");
		it("Should emit OfferRevoked event");
	});

	describe("Accept offer", function() {
		it("Should fail when sender is not the borrower");
		it("Should fail when deed is not in new/open state");
		it("Should set offer as accepted in deed");
		it("Should update deed to running state");
		it("Should send lender asset to borrower");
		it("Should send deed token to lender");
		it("Should emit OfferAccepted event");
		it("Should return true if successful");
	});

	describe("Pay back", function() {
		it("Should fail when sender is not the borrower");
		it("Should fail when deed is not in running state");
		it("Should update deed to paid back state");
		it("Should send pay back amount to vault");
		it("Should send deed collateral to borrower from vault");
		it("Should emit PaidBack event");
		it("Should return true if successful");
	});

	describe("Claim deed", function() {
		it("Should fail when sender is not deed owner");
		it("Should fail when deed is not in paid back nor expired state");
		it("Should send collateral from vault to lender when deed is expired");
		it("Should send paid back amount from vault to lender when deed is paid back");
		it("Should emit DeedClaimed event");
		it("Should burn deed token");
		it("Should return true if successful");
	});

	describe("Change min duration", function() {
		it("Should fail when sender is not owner");
		it("Should set new min duration");
		it("Shoudl emit MinDurationChange event");
	});

});
