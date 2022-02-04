const { ethers } = require("hardhat");

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
	MultiTokenAsset: [
		{ name: "assetAddress", type: "address" },
		{ name: "category", type: "uint8" },
		{ name: "amount", type: "uint256" },
		{ name: "id", type: "uint256" },
	],
	Offer: [
		{ name: "collateral", type: "MultiTokenAsset" },
		{ name: "loan", type: "MultiTokenAsset" },
		{ name: "loanRepayAmount", type: "uint256" },
		{ name: "duration", type: "uint32" },
		{ name: "expiration", type: "uint40" },
		{ name: "lender", type: "address" },
		{ name: "nonce", type: "bytes32" },
	]
}

function getOfferHashBytes(offerArray, deedAddress) {
	return ethers.utils._TypedDataEncoder.hash(
		getEIP712Domain(deedAddress),
		EIP712OfferTypes,
		getOfferObject(...offerArray)
	);
}

async function signOffer(offerArray, deedAddress, signer) {
	return signer._signTypedData(
		getEIP712Domain(deedAddress),
		EIP712OfferTypes,
		getOfferObject(...offerArray)
	);
}

function getOfferObject(
	collateralAssetAddress,
	collateralCategory,
	collateralAmount,
	collateralId,
	loanAssetAddress,
	loanAmount,
	loanRepayAmount,
	duration,
	offerExpiration,
	lender,
	nonce,
) {
	return {
		collateral: {
			assetAddress: collateralAssetAddress,
			category: collateralCategory,
			amount: collateralAmount,
			id: collateralId,
		},
		loan: {
			assetAddress: loanAssetAddress,
			category: CATEGORY.ERC20,
			amount: loanAmount,
			id: 0,
		},
		loanRepayAmount: loanRepayAmount,
		duration: duration,
		expiration: offerExpiration,
		lender: lender,
		nonce: nonce,
	}
}

function getOfferStruct(
	collateralAssetAddress,
	collateralCategory,
	collateralAmount,
	collateralId,
	loanAssetAddress,
	loanAmount,
	loanRepayAmount,
	duration,
	offerExpiration,
	lender,
	nonce,
) {
	return [
		[collateralAssetAddress, collateralCategory, collateralAmount, collateralId],
		[loanAssetAddress, CATEGORY.ERC20, loanAmount, 0],
		loanRepayAmount,
		duration,
		offerExpiration,
		lender,
		nonce,
	];
}

module.exports = { CATEGORY, timestampFromNow, getOfferHashBytes, signOffer, getOfferStruct };
