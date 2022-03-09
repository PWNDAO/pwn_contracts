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

function getEIP712Domain(address) {
	return {
		name: "PWN",
		version: "1",
		chainId: 31337, // Default hardhat network chain id
		verifyingContract: address
	}
};

const EIP712OfferTypes = {
	Offer: [
		{ name: "collateralAddress", type: "address" },
		{ name: "collateralCategory", type: "uint8" },
		{ name: "collateralAmount", type: "uint256" },
		{ name: "collateralId", type: "uint256" },
		{ name: "loanAssetAddress", type: "address" },
		{ name: "loanAmount", type: "uint256" },
		{ name: "loanYield", type: "uint256" },
		{ name: "duration", type: "uint32" },
		{ name: "expiration", type: "uint40" },
		{ name: "lender", type: "address" },
		{ name: "nonce", type: "bytes32" },
	]
}

const EIP712FlexibleOfferTypes = {
	FlexibleOffer: [
		{ name: "collateralAddress", type: "address" },
		{ name: "collateralCategory", type: "uint8" },
		{ name: "collateralAmount", type: "uint256" },
		{ name: "collateralIdsWhitelistMerkleRoot", type: "bytes32" },
		{ name: "loanAssetAddress", type: "address" },
		{ name: "loanAmountMax", type: "uint256" },
		{ name: "loanAmountMin", type: "uint256" },
		{ name: "loanYieldMax", type: "uint256" },
		{ name: "durationMax", type: "uint32" },
		{ name: "durationMin", type: "uint32" },
		{ name: "expiration", type: "uint40" },
		{ name: "lender", type: "address" },
		{ name: "nonce", type: "bytes32" },
	]
}

function getOfferHashBytes(offerArray, loanAddress) {
	if (offerArray.length == 11) {
		// Simple offer
		return ethers.utils._TypedDataEncoder.hash(
			getEIP712Domain(loanAddress),
			EIP712OfferTypes,
			getOfferObject(...offerArray)
		);
	} else if (offerArray.length == 13) {
		// Flexible offer
		return ethers.utils._TypedDataEncoder.hash(
			getEIP712Domain(loanAddress),
			EIP712FlexibleOfferTypes,
			getFlexibleOfferObject(...offerArray)
		);
	}
}

async function signOffer(offerArray, loanAddress, signer) {
	if (offerArray.length == 11) {
		// Simple offer
		return signer._signTypedData(
			getEIP712Domain(loanAddress),
			EIP712OfferTypes,
			getOfferObject(...offerArray)
		);
	} else if (offerArray.length == 13) {
		// Flexible offer
		return signer._signTypedData(
			getEIP712Domain(loanAddress),
			EIP712FlexibleOfferTypes,
			getFlexibleOfferObject(...offerArray)
		);
	}
}

function getMerkleTree(leaves) {
	return new MerkleTree(leaves, keccak256, { sort: true });
}



function getOfferObject(
	collateralAddress,
	collateralCategory,
	collateralAmount,
	collateralId,
	loanAssetAddress,
	loanAmount,
	loanYield,
	duration,
	expiration,
	lender,
	nonce,
) {
	return {
		collateralAddress: collateralAddress,
		collateralCategory: collateralCategory,
		collateralAmount: collateralAmount,
		collateralId: collateralId,
		loanAssetAddress: loanAssetAddress,
		loanAmount: loanAmount,
		loanYield: loanYield,
		duration: duration,
		expiration: expiration,
		lender: lender,
		nonce: nonce,
	}
}

function getFlexibleOfferObject(
	collateralAddress,
	collateralCategory,
	collateralAmount,
	collateralIdsWhitelistMerkleRoot,
	loanAssetAddress,
	loanAmountMax,
	loanAmountMin,
	loanYieldMax,
	durationMax,
	durationMin,
	expiration,
	lender,
	nonce
) {
	return {
		collateralAddress: collateralAddress,
		collateralCategory: collateralCategory,
		collateralAmount: collateralAmount,
		collateralIdsWhitelistMerkleRoot: collateralIdsWhitelistMerkleRoot,
		loanAssetAddress: loanAssetAddress,
		loanAmountMax: loanAmountMax,
		loanAmountMin: loanAmountMin,
		loanYieldMax: loanYieldMax,
		durationMax: durationMax,
		durationMin: durationMin,
		expiration: expiration,
		lender: lender,
		nonce: nonce,
	}
}

module.exports = { CATEGORY, timestampFromNow, getOfferHashBytes, signOffer, getMerkleTree };
