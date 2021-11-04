require("@nomiclabs/hardhat-waffle");

// const PRIVATE = require("./.keys/PRIVATE.json");

module.exports = {
    solidity: "0.8.4",
    networks: {
        // To deploy to Rinkeby testnet, uncomment setup bellow & PRIVATE.
        // Note you have to have ./.keys/PRIVATE.json file locally.

        // rinkeby: {
        //     url: `https://rinkeby.infura.io/v3/${PRIVATE.infuraId}`,
        //     accounts: [`0x${PRIVATE.key}`]
        // }
    }
};
