require("@nomiclabs/hardhat-waffle");

task("accounts", "Prints the list of accounts", async () => {
    const accounts = await ethers.getSigners();

    for (const account of accounts) {
        console.log(account.address);
    }
});

// const KOVAN_PRIVATE_KEY = require("./.keys/PRIVATE.json").key1;

module.exports = {
    solidity: "0.8.4",
    networks: {
        // To deploy to Kovan testnet, uncomment setup bellow & KOVAN_PRIVATE_KEY.
        // Note you have to have ./.keys/PRIVATE.json file locally.
        //
        // kovan: {
        //     url: `https://kovan.infura.io/v3/2e64f610a85f433d83a708df23e6e71f`,
        //     accounts: [`0x${KOVAN_PRIVATE_KEY}`]
        // }
    }
};
