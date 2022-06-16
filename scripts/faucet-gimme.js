const { ethers } = require("hardhat");
const { log, STYLE } = require("./scripts-helpers");
const { highlighted } = STYLE;


const addr = "0x";


async function faucetGimme() {
    const Faucet = await ethers.getContractAt("Faucet", "0x");

    log("\n Giving faucet assets to: " + addr + "...");

    await Faucet.gimme(addr);

    log("🎉🎉🎉 Faucet gimme script successfully finished 🎉🎉🎉\n", highlighted);
}


faucetGimme()
    .then(() => {
        process.exit(0)})
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
