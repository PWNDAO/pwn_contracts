require("@nomiclabs/hardhat-waffle");
const config = require("dotenv").config().parsed;

module.exports = {
    solidity: "0.8.4",
    networks: {
        rinkeby: {
            url: `https://rinkeby.infura.io/v3/${config.INFURA_ID}`,
            accounts: [config.PRIVATE_KEY]
        },
        hardhat: {
            mining: {
                auto: false,
                interval: 2000
            }
        }
    },
    etherscan: {
        apiKey: config.ETHERSCAN_API_KEY
    }
};
