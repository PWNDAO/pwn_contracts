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

function getOfferHashBytes(offer) {
	const encodedOffer = ethers.utils.defaultAbiCoder.encode(
		[ "tuple(tuple(address, uint8, uint256, uint256), tuple(address, uint8, uint256, uint256), uint256, uint32, uint40, address, uint256, uint256)" ],
		[ offer ]
	);
	const offerHash = ethers.utils.keccak256(encodedOffer);
	return ethers.utils.arrayify(offerHash);
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
		[loanAssetAddress, 0, loanAmount, 0],
		loanRepayAmount,
		duration,
		offerExpiration,
		lender,
		nonce,
		31337, // Default hardhat network chain id
	];
}

module.exports = { CATEGORY, timestampFromNow, getOfferHashBytes, getOfferStruct };
