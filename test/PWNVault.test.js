const chai = require("chai");
const { ethers } = require("hardhat");
const { smock } = require("@defi-wonderland/smock");

const expect = chai.expect;
chai.use(smock.matchers);


describe("PWNVault contract", async function() {

	let Vault;
	let vault;
	let vaultEventIface;
	let owner, asset1, addr1, addr2, addr3, addr4;

	const CATEGORY = {
		ERC20: 0,
		ERC721: 1,
		ERC1155: 2,
		unknown: 3,
	};

	before(async function() {
		Vault = await ethers.getContractFactory("PWNVault");
		[owner, asset1, addr1, addr2, addr3, addr4] = await ethers.getSigners();

		vaultEventIface = new ethers.utils.Interface([
			"event VaultPull(tuple(address assetAddress, uint8 category, uint256 amount, uint256 id), address indexed origin)",
			"event VaultPush(tuple(address assetAddress, uint8 category, uint256 amount, uint256 id), address indexed beneficiary)",
	    	"event VaultPushFrom(tuple(address assetAddress, uint8 category, uint256 amount, uint256 id), address indexed origin, address indexed beneficiary)",
		]);
	});

	beforeEach(async function() {
		vault = await Vault.deploy();
		await vault.setPWN(owner.address);
	});


	describe("Constructor", function() {

		it("Should set correct owner", async function() {
			const factory = await ethers.getContractFactory("PWNVault", addr1);

			vault = await factory.deploy();

			const owner = await vault.owner();
			expect(addr1.address).to.equal(owner, "vault owner should be the vault deployer");
		});

	});


	describe("Pull", function() {

		let fakeToken;

		beforeEach(async function() {
			fakeToken = await smock.fake("ERC20");
			fakeToken.transferFrom.returns(true);
		});


		it("Should fail when sender is not PWN", async function() {
			const dummyAsset = {
				assetAddress: asset1.address,
				category: CATEGORY.ERC20,
				amount: 10,
				id: 0,
			};

			await expect(
				vault.connect(addr1).pull(dummyAsset, addr1.address)
			).to.be.revertedWith("Caller is not the PWN");
		});

		it("Should send asset from address to vault", async function() {
			// Best test would be checking that Vault is calling correct MultiToken lib function.
			// Unfortunatelly it is not possible at this time. 
			// MultiToken lib is tested separately.
			// Because of that we can test just ERC20 type and assume that others would work too.
			const amount = 123;

			await vault.pull([fakeToken.address, CATEGORY.ERC20, amount, 0], addr1.address);

			expect(fakeToken.transferFrom).to.have.been.calledOnce;
			expect(fakeToken.transferFrom).to.have.been.calledWith(addr1.address, vault.address, amount);
		});

		it("Should emit VaultPull event", async function() {
			const amount = 37;

			await expect(
				vault.pull([fakeToken.address, CATEGORY.ERC20, amount, 0], addr1.address)
			).to.emit(vault, "VaultPull").withArgs(
				[fakeToken.address, CATEGORY.ERC20, amount, 0], addr1.address
			);
		});

		it("Should return true if successful", async function() {
			const success = await vault.callStatic.pull([fakeToken.address, CATEGORY.ERC20, 84, 0], addr1.address);

			expect(success).to.equal(true);
		});

	});


	describe("Push", function() {

		let fakeToken;

		beforeEach(async function() {
			fakeToken = await smock.fake("ERC20");
			fakeToken.transfer.returns(true);
		});


		it("Should fail when sender is not PWN", async function() {
			const dummyAsset = {
				assetAddress: addr2.address,
				category: CATEGORY.ERC20,
				amount: 10,
				id: 0,
			};

			await expect(
				vault.connect(addr1).push(dummyAsset, addr3.address)
			).to.be.revertedWith("Caller is not the PWN");
		});

		it("Should send asset from vault to address", async function() {
			// Best test would be checking that Vault is calling correct MultiToken lib function.
			// Unfortunatelly it is not possible at this time. 
			// MultiToken lib is tested separately.
			// Because of that we can test just ERC20 type and assume that others would work too.
			const amount = 28;

			await vault.push([fakeToken.address, CATEGORY.ERC20, amount, 0], addr2.address);

			expect(fakeToken.transfer).to.have.been.calledOnce;
			expect(fakeToken.transfer).to.have.been.calledWith(addr2.address, amount);
		});

		it("Should emit VaultPush event", async function() {
			const amount = 73;

			await expect(
				vault.push([fakeToken.address, CATEGORY.ERC20, amount, 0], addr2.address)
			).to.emit(vault, "VaultPush").withArgs(
				[fakeToken.address, CATEGORY.ERC20, amount, 0], addr2.address
			);
		});

		it("Should return true if successful", async function() {
			const success = await vault.callStatic.push([fakeToken.address, CATEGORY.ERC20, 48, 0], addr2.address);

			expect(success).to.equal(true);
		});

	});


	describe("PushFrom", function() {

		let fakeToken;

		beforeEach(async function() {
			fakeToken = await smock.fake("ERC20");
			fakeToken.transferFrom.returns(true);
		});


		it("Should fail when sender is not PWN", async function() {
			const dummyAsset = {
				assetAddress: addr2.address,
				category: CATEGORY.ERC20,
				amount: 10,
				id: 0,
			};

			try {
				await vault.connect(addr1).pushFrom(dummyAsset, addr3.address, addr4.address);

				expect().fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Caller is not the PWN");
			}
		});

		it("Should send asset from address to address", async function() {
			// Best test would be checking that Vault is calling correct MultiToken lib function.
			// Unfortunatelly it is not possible at this time. 
			// MultiToken lib is tested separately.
			// Because of that we can test just ERC20 type and assume that others would work too.
			const amount = 432;

			await vault.pushFrom([fakeToken.address, CATEGORY.ERC20, amount, 0], addr2.address, addr3.address);

			expect(fakeToken.transferFrom).to.have.been.calledOnce;
			expect(fakeToken.transferFrom).to.have.been.calledWith(addr2.address, addr3.address, amount);
		});

		it("Should emit VaultPushFrom event", async function() {
			const amount = 7;

			await expect(
				vault.pushFrom([fakeToken.address, CATEGORY.ERC20, amount, 0], addr2.address, addr3.address)
			).to.emit(vault, "VaultPushFrom").withArgs(
				[fakeToken.address, CATEGORY.ERC20, amount, 0], addr2.address, addr3.address
			);
		});

		it("Should return true if successful", async function() {
			const success = await vault.callStatic.pushFrom([fakeToken.address, CATEGORY.ERC20, 22, 0], addr2.address, addr3.address);

			expect(success).to.equal(true);
		});

	});


	describe("On ERC1155 received", function() {

		it("Should return correct bytes", async function() {
			const bytes = await vault.callStatic.onERC1155Received(addr1.address, addr2.address, 1, 2, 0x321);

			expect(ethers.utils.hexValue(bytes)).to.equal(ethers.utils.hexValue(0xf23a6e61));
		});

	});


	describe("On ERC1155 batch received", function() {

		it("Should return correct bytes", async function() {
			const bytes = await vault.callStatic.onERC1155BatchReceived(addr1.address, addr2.address, [3], [4], 0x312);

			expect(ethers.utils.hexValue(bytes)).to.equal(ethers.utils.hexValue(0xbc197c81));
		});

	});


	describe("Set PWN", function() {

		it("Should fail when sender is not owner", async function() {
			try {
				await vault.connect(addr1).setPWN(addr2.address);
				expect().fail();
			} catch(error) {
				expect(error.message).to.contain("revert");
				expect(error.message).to.contain("Ownable: caller is not the owner");
			}
		});

		it("Should set PWN address", async function() {
			const formerPWN = await vault.PWN();

			await vault.connect(owner).setPWN(addr1.address);

			const latterPWN = await vault.PWN();
			expect(formerPWN).to.not.equal(latterPWN);
			expect(latterPWN).to.equal(addr1.address);
		});

	});


	describe("Supports interface", function() {

		function functionSelector(signature) {
			const bytes = ethers.utils.toUtf8Bytes(signature)
			const hash = ethers.utils.keccak256(bytes);
			const selector = ethers.utils.hexDataSlice(hash, 0, 4);
			return ethers.BigNumber.from(selector);
		}

		it("Should support ERC165 interface", async function() {
			const interfaceId = functionSelector("supportsInterface(bytes4)");

			const supportsERC165 = await vault.callStatic.supportsInterface(interfaceId);

			expect(supportsERC165).to.equal(true);
		});

		it("Should support Ownable interface", async function() {
			const interfaceId = functionSelector("owner()")
				.xor(functionSelector("renounceOwnership()"))
				.xor(functionSelector("transferOwnership(address)"));

			const supportsOwnable = await vault.callStatic.supportsInterface(interfaceId);

			expect(supportsOwnable).to.equal(true);
		});

		it("Should support PWN Vault interface", async function() {
			const interfaceId = functionSelector("PWN()")
				.xor(functionSelector("pull((address,uint8,uint256,uint256),address)"))
				.xor(functionSelector("push((address,uint8,uint256,uint256),address)"))
				.xor(functionSelector("pushFrom((address,uint8,uint256,uint256),address,address)"))
				.xor(functionSelector("setPWN(address)"));

			const supportsPWNVault = await vault.callStatic.supportsInterface(interfaceId);

			expect(supportsPWNVault).to.equal(true);
		});

		it("Should support ERC721Receiver interface", async function() {
			const interfaceId = functionSelector("onERC721Received(address,address,uint256,bytes)");

			const supportsERC721Receiver = await vault.callStatic.supportsInterface(interfaceId);

			expect(supportsERC721Receiver).to.equal(true);
		});

		it("Should support ERC1155Receiver interface", async function() {
			const interfaceId = functionSelector("onERC1155Received(address,address,uint256,uint256,bytes)")
				.xor(functionSelector("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"));

			const supportsERC1155Receiver = await vault.callStatic.supportsInterface(interfaceId);

			expect(supportsERC1155Receiver).to.equal(true);
		});

	});

});
