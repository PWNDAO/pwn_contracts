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
	const offerHash = ethers.utils.solidityKeccak256(
		["address", "uint8", "uint256", "uint256", "address", "uint256", "uint256", "uint32", "uint40", "address", "uint256", "uint256"],
		[
			offer[0][0], offer[0][1], offer[0][2], offer[0][3],
			offer[1][0], offer[1][2],
			offer[2], offer[3], offer[4], offer[5], offer[6], offer[7],
		]
	);

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
		31337,
	];
}

module.exports = { CATEGORY, timestampFromNow, getOfferHashBytes, getOfferStruct };
