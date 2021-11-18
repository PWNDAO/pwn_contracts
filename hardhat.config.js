require("@nomiclabs/hardhat-waffle");
require("hardhat-gas-reporter");
const config = require("config");

module.exports = {
    solidity: "0.8.4",
    networks: config.networks,
    etherscan: config.etherscan,
    gasReporter: {
        currency: "USD",
        gasPrice: 150,
        enabled: true
    }
};
