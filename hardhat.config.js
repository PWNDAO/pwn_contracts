require("@nomiclabs/hardhat-waffle");

task("accounts", "Prints the list of accounts", async () => {
    const accounts = await ethers.getSigners();

    for (const account of accounts) {
        console.log(account.address);
    }
});

// const PRIVATE_KEY = require("./keys/PRIVATE.json").key1;

module.exports = {
    solidity: "0.8.4"
    // networks: {
    //     // To deploy to Kovan testnet, uncomment setup bellow & KOVAN_PRIVATE_KEY.
    //     // Note you have to have ./.keys/PRIVATE.json file locally.
    //
    //     rinkeby: {
    //         url: `https://rinkeby.infura.io/v3/1ef6c7c90cde4e21b161b48edeb5c8c8`,
    //         accounts: [`0x${PRIVATE_KEY}`]
    //     }
    // }
};
