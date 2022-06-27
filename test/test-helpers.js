const { MerkleTree } = require("merkletreejs");
const { ethers } = require("hardhat");
const utils = ethers.utils;
const keccak256 = ethers.utils.keccak256;


const CATEGORY = {
	ERC20: 0,
	ERC721: 1,
	ERC1155: 2,
	unknown: 3,
};


async function timestampFromNow(delta) {
	const lastBlockNumber = await ethers.provider.getBlockNumber();
	const lastBlock = await ethers.provider.getBlock(lastBlockNumber);
	return lastBlock.timestamp + delta;
}


function getPWNEIP712Domain(address) {
	return {
		name: "PWN",
		version: "1",
		chainId: 31337, // Default hardhat network chain id
		verifyingContract: address
	}
};

function getPermit20EIP712Domain(address) {
	return {
		name: "Basic20",
		version: "1",
		chainId: 31337, // Default hardhat network chain id
		verifyingContract: address
	}
};


const EIP712OfferTypes = {
	Offer: [
		{ name: "collateralCategory", type: "uint8" },
		{ name: "collateralAddress", type: "address" },
		{ name: "collateralId", type: "uint256" },
		{ name: "collateralAmount", type: "uint256" },
		{ name: "loanAssetAddress", type: "address" },
		{ name: "loanAmount", type: "uint256" },
		{ name: "loanYield", type: "uint256" },
		{ name: "duration", type: "uint32" },
		{ name: "expiration", type: "uint40" },
		{ name: "borrower", type: "address" },
		{ name: "lender", type: "address" },
		{ name: "isPersistent", type: "bool" },
		{ name: "nonce", type: "bytes32" },
	]
}

const EIP712FlexibleOfferTypes = {
	FlexibleOffer: [
		{ name: "collateralCategory", type: "uint8" },
		{ name: "collateralAddress", type: "address" },
		{ name: "collateralIdsWhitelistMerkleRoot", type: "bytes32" },
		{ name: "collateralAmount", type: "uint256" },
		{ name: "loanAssetAddress", type: "address" },
		{ name: "loanAmountMax", type: "uint256" },
		{ name: "loanAmountMin", type: "uint256" },
		{ name: "loanYieldMax", type: "uint256" },
		{ name: "durationMax", type: "uint32" },
		{ name: "durationMin", type: "uint32" },
		{ name: "expiration", type: "uint40" },
		{ name: "borrower", type: "address" },
		{ name: "lender", type: "address" },
		{ name: "isPersistent", type: "bool" },
		{ name: "nonce", type: "bytes32" },
	]
}

const Permit20OfferType = {
	Permit: [
		{ name: "owner", type: "address" },
		{ name: "spender", type: "address" },
		{ name: "value", type: "uint256" },
		{ name: "nonce", type: "uint256" },
		{ name: "deadline", type: "uint256" },
	]
}


function getOfferHashBytes(offerArray, loanAddress) {
	if (offerArray.length == 13) {
		// Simple offer
		return ethers.utils._TypedDataEncoder.hash(
			getPWNEIP712Domain(loanAddress),
			EIP712OfferTypes,
			getOfferObject(...offerArray)
		);
	} else if (offerArray.length == 15) {
		// Flexible offer
		return ethers.utils._TypedDataEncoder.hash(
			getPWNEIP712Domain(loanAddress),
			EIP712FlexibleOfferTypes,
			getFlexibleOfferObject(...offerArray)
		);
	}
}


async function signOffer(offerArray, loanAddress, signer) {
	if (offerArray.length == 13) {
		// Simple offer
		return signer._signTypedData(
			getPWNEIP712Domain(loanAddress),
			EIP712OfferTypes,
			getOfferObject(...offerArray)
		);
	} else if (offerArray.length == 15) {
		// Flexible offer
		return signer._signTypedData(
			getPWNEIP712Domain(loanAddress),
			EIP712FlexibleOfferTypes,
			getFlexibleOfferObject(...offerArray)
		);
	}
}

async function signPermit20(permitArray, tokenAddress, signer) {
	return signer._signTypedData(
		getPermit20EIP712Domain(tokenAddress),
		Permit20OfferType,
		getPermit20Object(...permitArray)
	);
}


function getMerkleRootWithProof(ids, index) {
	if (ids.length == 0) {
		return [ethers.utils.hexZeroPad(0, 32), []];
	}

	const leaves = ids.map((x) => keccak256(ethers.utils.hexZeroPad(x, 32)));
	const tree = new MerkleTree(leaves, keccak256, { sort: true });
	const proof = index == -1 ? [] : tree.getHexProof(leaves[index]);
	return [tree.getHexRoot(), proof, tree];
}



function getOfferObject(
	collateralCategory,
	collateralAddress,
	collateralId,
	collateralAmount,
	loanAssetAddress,
	loanAmount,
	loanYield,
	duration,
	expiration,
	borrower,
	lender,
	isPersistent,
	nonce,
) {
	return {
		collateralCategory: collateralCategory,
		collateralAddress: collateralAddress,
		collateralId: collateralId,
		collateralAmount: collateralAmount,
		loanAssetAddress: loanAssetAddress,
		loanAmount: loanAmount,
		loanYield: loanYield,
		duration: duration,
		expiration: expiration,
		borrower: borrower,
		lender: lender,
		isPersistent: isPersistent,
		nonce: nonce,
	}
}

function getFlexibleOfferObject(
	collateralCategory,
	collateralAddress,
	collateralIdsWhitelistMerkleRoot,
	collateralAmount,
	loanAssetAddress,
	loanAmountMax,
	loanAmountMin,
	loanYieldMax,
	durationMax,
	durationMin,
	expiration,
	borrower,
	lender,
	isPersistent,
	nonce
) {
	return {
		collateralCategory: collateralCategory,
		collateralAddress: collateralAddress,
		collateralIdsWhitelistMerkleRoot: collateralIdsWhitelistMerkleRoot,
		collateralAmount: collateralAmount,
		loanAssetAddress: loanAssetAddress,
		loanAmountMax: loanAmountMax,
		loanAmountMin: loanAmountMin,
		loanYieldMax: loanYieldMax,
		durationMax: durationMax,
		durationMin: durationMin,
		expiration: expiration,
		borrower: borrower,
		lender: lender,
		isPersistent: isPersistent,
		nonce: nonce,
	}
}

function getPermit20Object(
	owner,
	spender,
	value,
	nonce,
	deadline
){
	return {
		owner: owner,
		spender: spender,
		value: value,
		nonce: nonce,
		deadline: deadline,
	}
}


module.exports = { CATEGORY, timestampFromNow, getOfferHashBytes, signOffer, signPermit20, getMerkleRootWithProof };
