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
		{ name: "borrower", type: "address" },
		{ name: "lender", type: "address" },
		{ name: "isPersistent", type: "bool" },
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
		{ name: "borrower", type: "address" },
		{ name: "lender", type: "address" },
		{ name: "isPersistent", type: "bool" },
		{ name: "nonce", type: "bytes32" },
	]
}

function getOfferHashBytes(offerArray, loanAddress) {
	if (offerArray.length == 13) {
		// Simple offer
		return ethers.utils._TypedDataEncoder.hash(
			getEIP712Domain(loanAddress),
			EIP712OfferTypes,
			getOfferObject(...offerArray)
		);
	} else if (offerArray.length == 15) {
		// Flexible offer
		return ethers.utils._TypedDataEncoder.hash(
			getEIP712Domain(loanAddress),
			EIP712FlexibleOfferTypes,
			getFlexibleOfferObject(...offerArray)
		);
	}
}

async function signOffer(offerArray, loanAddress, signer) {
	if (offerArray.length == 13) {
		// Simple offer
		return signer._signTypedData(
			getEIP712Domain(loanAddress),
			EIP712OfferTypes,
			getOfferObject(...offerArray)
		);
	} else if (offerArray.length == 15) {
		// Flexible offer
		return signer._signTypedData(
			getEIP712Domain(loanAddress),
			EIP712FlexibleOfferTypes,
			getFlexibleOfferObject(...offerArray)
		);
	}
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
	collateralAddress,
	collateralCategory,
	collateralAmount,
	collateralId,
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
		collateralAddress: collateralAddress,
		collateralCategory: collateralCategory,
		collateralAmount: collateralAmount,
		collateralId: collateralId,
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
	borrower,
	lender,
	isPersistent,
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
		borrower: borrower,
		lender: lender,
		isPersistent: isPersistent,
		nonce: nonce,
	}
}

module.exports = { CATEGORY, timestampFromNow, getOfferHashBytes, signOffer, getMerkleRootWithProof };
