const chai = require("chai");
const { ethers } = require("hardhat");
const { smock } = require("@defi-wonderland/smock");

const expect = chai.expect;
chai.use(smock.matchers);

describe("PWNVault contract", async function() {

	let vault;
	let vaultAdapter;

	let Vault;
	let VaultAdapter;
	let vaultEventIface;
	let owner, addr1, addr2, addr3, addr4;

	before(async function() {
		Vault = await ethers.getContractFactory("PWNVault");
		VaultAdapter = await ethers.getContractFactory("PWNVaultTestAdapter"); // Needed for passing MultiToken.Asset struct as a parameter
		[owner, addr1, addr2, addr3, addr4] = await ethers.getSigners();

		vaultEventIface = new ethers.utils.Interface([
			"event VaultPush(tuple(uint8 cat, uint256 amount, uint256 id, address tokenAddress))",
			"event VaultPull(tuple(uint8 cat, uint256 amount, uint256 id, address tokenAddress), address indexed beneficiary)",
	    	"event VaultProxy(tuple(uint8 cat, uint256 amount, uint256 id, address tokenAddress), address indexed origin, address indexed beneficiary)"
		]);
	});

	beforeEach(async function() {
		vault = await Vault.deploy();
		vaultAdapter = await VaultAdapter.deploy(vault.address);
		await vault.setPWN(vaultAdapter.address);
	});

	describe("Constructor", function() {
		it("Should set correct owner", async function() {
			const factory = await ethers.getContractFactory("PWNVault", addr1);

			vault = await factory.deploy();

			const owner = await vault.owner();
			expect(addr1.address).to.equal(owner, "vault owner should be the vault deployer");
		});
	});

	describe("Push", function() {
		it("Should fail when sender is not PWN", async function() {
			const dummyAsset = {
				cat: 0,
				amount: 10,
				id: 0,
				tokenAddress: addr2.address
			};

			try {
				await vault.connect(addr1).push(dummyAsset, addr1.address);
				expect().fail();
			} catch(error) {
				expect(error.message).to.contain("revert"); // TODO: Add reason?
			}
		});

		it("Should send asset from address to vault", async function() {
			// Best test would be checking that Vault is calling correct MultiToken lib function.
			// Unfortunatelly it is not possible at this time. 
			// MultiToken lib is tested separately.
			// Because of that we can test just ERC20 type and assume that others would work too.
			const amount = 123;
			const fakeToken = await smock.fake("Basic20");
			fakeToken.transferFrom.returns(true);

			await vaultAdapter.push(0, amount, 0, fakeToken.address, addr1.address);

			expect(fakeToken.transferFrom).to.have.been.calledOnce;
			expect(fakeToken.transferFrom).to.have.been.calledWith(addr1.address, vault.address, amount);
		});

		it("Should emit VaultPush event", async function() {
			const amount = 37;
			const fakeToken = await smock.fake("Basic20");
			fakeToken.transferFrom.returns(true);

			const tx = await vaultAdapter.push(0, amount, 0, fakeToken.address, addr1.address);
			const response = await tx.wait();

			expect(response.logs.length).to.equal(1);
			const logDescription = vaultEventIface.parseLog(response.logs[0]);
			expect(logDescription.name).to.equal("VaultPush");
			const args = logDescription.args[0];
			expect(args.cat).to.equal(0);
			expect(args.amount).to.equal(amount);
			expect(args.id).to.equal(0);
			expect(args.tokenAddress).to.equal(fakeToken.address);
		});

		it("Should return true if successful", async function() {
			const fakeToken = await smock.fake("Basic20");
			fakeToken.transferFrom.returns(true);

			const success = await vaultAdapter.callStatic.push(0, 84, 0, fakeToken.address, addr1.address);

			expect(success).to.equal(true);
		});
	});

	describe("Pull", function() {
		it("Should fail when sender is not PWN", async function() {
			const dummyAsset = {
				cat: 0,
				amount: 10,
				id: 0,
				tokenAddress: addr2.address
			};

			try {
				await vault.connect(addr1).pull(dummyAsset, addr3.address);
				expect().fail();
			} catch(error) {
				expect(error.message).to.contain("revert"); // TODO: Add reason?
			}
		});

		it("Should send asset from vault to address", async function() {
			// Best test would be checking that Vault is calling correct MultiToken lib function.
			// Unfortunatelly it is not possible at this time. 
			// MultiToken lib is tested separately.
			// Because of that we can test just ERC20 type and assume that others would work too.
			const amount = 28;
			const fakeToken = await smock.fake("Basic20");
			fakeToken.transfer.returns(true);

			await vaultAdapter.pull(0, amount, 0, fakeToken.address, addr2.address);

			expect(fakeToken.transfer).to.have.been.calledOnce;
			expect(fakeToken.transfer).to.have.been.calledWith(addr2.address, amount);
		});

		it("Should emit VaultPull event", async function() {
			const amount = 73;
			const fakeToken = await smock.fake("Basic20");
			fakeToken.transfer.returns(true);

			const tx = await vaultAdapter.pull(0, amount, 0, fakeToken.address, addr2.address);
			const response = await tx.wait();

			expect(response.logs.length).to.equal(1);
			const logDescription = vaultEventIface.parseLog(response.logs[0]);
			expect(logDescription.name).to.equal("VaultPull");
			expect(logDescription.args.beneficiary).to.equal(addr2.address);
			const args = logDescription.args[0];
			expect(args.cat).to.equal(0);
			expect(args.amount).to.equal(amount);
			expect(args.id).to.equal(0);
			expect(args.tokenAddress).to.equal(fakeToken.address);
		});

		it("Should return true if successful", async function() {
			const fakeToken = await smock.fake("Basic20");
			fakeToken.transfer.returns(true);

			const success = await vaultAdapter.callStatic.pull(0, 48, 0, fakeToken.address, addr2.address);

			expect(success).to.equal(true);
		});
	});

	describe("PullProxy", function() {
		it("Should fail when sender is not PWN", async function() {
			const dummyAsset = {
				cat: 0,
				amount: 10,
				id: 0,
				tokenAddress: addr2.address
			};

			try {
				await vault.connect(addr1).pullProxy(dummyAsset, addr3.address, addr4.address);
				expect().fail();
			} catch(error) {
				expect(error.message).to.contain("revert"); // TODO: Add reason?
			}
		});

		it("Should send asset from address to address", async function() {
			// Best test would be checking that Vault is calling correct MultiToken lib function.
			// Unfortunatelly it is not possible at this time. 
			// MultiToken lib is tested separately.
			// Because of that we can test just ERC20 type and assume that others would work too.
			const amount = 432;
			const fakeToken = await smock.fake("Basic20");
			fakeToken.transferFrom.returns(true);

			await vaultAdapter.pullProxy(0, amount, 0, fakeToken.address, addr2.address, addr3.address);

			expect(fakeToken.transferFrom).to.have.been.calledOnce;
			expect(fakeToken.transferFrom).to.have.been.calledWith(addr2.address, addr3.address, amount);
		});

		it("Should emit VaultProxy event", async function() {
			const amount = 7;
			const fakeToken = await smock.fake("Basic20");
			fakeToken.transferFrom.returns(true);

			const tx = await vaultAdapter.pullProxy(0, amount, 0, fakeToken.address, addr2.address, addr3.address);
			const response = await tx.wait();

			expect(response.logs.length).to.equal(1);
			const logDescription = vaultEventIface.parseLog(response.logs[0]);
			expect(logDescription.name).to.equal("VaultProxy");
			expect(logDescription.args.origin).to.equal(addr2.address);
			expect(logDescription.args.beneficiary).to.equal(addr3.address);
			const args = logDescription.args[0];
			expect(args.cat).to.equal(0);
			expect(args.amount).to.equal(amount);
			expect(args.id).to.equal(0);
			expect(args.tokenAddress).to.equal(fakeToken.address);
		});

		it("Should return true if successful", async function() {
			const fakeToken = await smock.fake("Basic20");
			fakeToken.transferFrom.returns(true);

			const success = await vaultAdapter.callStatic.pullProxy(0, 22, 0, fakeToken.address, addr2.address, addr3.address);

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
			}
		});

		it("Should set PWN address", async function() {
			const formerPWN = await vault.PWN();

			vault.connect(owner).setPWN(addr1.address);

			const latterPWN = await vault.PWN();
			expect(formerPWN).to.not.equal(latterPWN);
			expect(latterPWN).to.equal(addr1.address);
		});
	});

	describe("Supports interface", function() {

		const functionSelector = function(signature) {
			const bytes = ethers.utils.toUtf8Bytes(signature)
			const hash = ethers.utils.keccak256(bytes);
			return ethers.utils.hexDataSlice(hash, 0, 4);
		}

		it("Should support ERC165 interface", async function() {
			const interfaceId = functionSelector("supportsInterface(bytes4)");

			const supportsERC165 = await vault.callStatic.supportsInterface(interfaceId);

			expect(supportsERC165).to.equal(true);
		});

		it("Should support Ownable interface", async function() {
			const ownerSelector = functionSelector("owner()");
			const renounceOwnershipSelector = functionSelector("renounceOwnership()");
			const transferOwnershipSelector = functionSelector("transferOwnership(address)");
			const interfaceId = ethers.BigNumber.from(ownerSelector)
				.xor(ethers.BigNumber.from(renounceOwnershipSelector))
				.xor(ethers.BigNumber.from(transferOwnershipSelector));

			const supportsOwnable = await vault.callStatic.supportsInterface(interfaceId);

			expect(supportsOwnable).to.equal(true);
		});

		it("Should support PWN Vault interface", async function() {
			const pwnSelector = functionSelector("PWN()");
			const pushSelector = functionSelector("push((uint8,uint256,uint256,address),address)");
			const pullSelector = functionSelector("pull((uint8,uint256,uint256,address),address)");
			const pullProxySelector = functionSelector("pullProxy((uint8,uint256,uint256,address),address,address)");
			const setPWNSelector = functionSelector("setPWN(address)");
			
			const interfaceId = ethers.BigNumber.from(pwnSelector)
				.xor(ethers.BigNumber.from(pushSelector))
				.xor(ethers.BigNumber.from(pullSelector))
				.xor(ethers.BigNumber.from(pullProxySelector))
				.xor(ethers.BigNumber.from(setPWNSelector));

			const supportsPWNVault = await vault.callStatic.supportsInterface(interfaceId);

			expect(supportsPWNVault).to.equal(true);
		});

		it("Should support ERC1155Receiver interface", async function() {
			const onERC1155ReceivedSelector = functionSelector("onERC1155Received(address,address,uint256,uint256,bytes)");
			const onERC1155BatchReceivedSelector = functionSelector("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)");
			const interfaceId = ethers.BigNumber.from(onERC1155ReceivedSelector)
				.xor(ethers.BigNumber.from(onERC1155BatchReceivedSelector));

			const supportsERC1155Receiver = await vault.callStatic.supportsInterface(interfaceId);

			expect(supportsERC1155Receiver).to.equal(true);
		});
	});

});
