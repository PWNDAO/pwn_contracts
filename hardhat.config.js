require("@nomiclabs/hardhat-waffle");
require("hardhat-gas-reporter");
const config = require("config");

module.exports = {
    solidity: {
        version: "0.8.4",
        settings: {
            optimizer: {
                enabled: true,
                runs: 200,
            },
        },
    },
    networks: config.networks,
    etherscan: config.etherscan,
    gasReporter: {
        currency: "USD",
        gasPrice: 150,
        enabled: true
    }
};
