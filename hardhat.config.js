require("@nomiclabs/hardhat-waffle");
const config = require("config");

module.exports = {
    solidity: "0.8.4",
    networks: config.networks,
    etherscan: config.etherscan
};
