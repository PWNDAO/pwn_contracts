require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");
require("hardhat-gas-reporter");
require("dotenv").config();

module.exports = {
    solidity: {
        version: "0.8.4",
        settings: {
            optimizer: {
                enabled: true,
                runs: 200,
            },
            outputSelection: {
                "*": {
                    "*": ["storageLayout"]
                }
            },
        },
    },
    networks: {
        // Mainnets
        mainnet: {
            url: process.env.MAINNET_URL || "",
            accounts: process.env.PRIVATE_KEY_MAINNET !== undefined
                ? [process.env.PRIVATE_KEY_MAINNET]
                : [],
        },
        polygon: {
            url: process.env.POLYGON_URL || "",
            accounts: process.env.PRIVATE_KEY_MAINNET !== undefined
                ? [process.env.PRIVATE_KEY_MAINNET]
                : [],
        },
        // Testnets
        rinkeby: {
            url: process.env.RINKEBY_URL || "",
            accounts: process.env.PRIVATE_KEY_TESTNET !== undefined
                ? [process.env.PRIVATE_KEY_TESTNET]
                : [],
        },
        "arbitrum-rinkeby": {
            url: process.env.ARBITRUM_RINKEBY_URL || "",
            accounts: process.env.PRIVATE_KEY_TESTNET !== undefined
                ? [process.env.PRIVATE_KEY_TESTNET]
                : [],
        },
        "optimism-kovan": {
            url: process.env.OPTIMISM_KOVAN || "",
            accounts: process.env.PRIVATE_KEY_TESTNET !== undefined
                ? [process.env.PRIVATE_KEY_TESTNET]
                : [],
        },
        mumbai: {
            url: process.env.MUMBAI || "",
            accounts: process.env.PRIVATE_KEY_TESTNET !== undefined
                ? [process.env.PRIVATE_KEY_TESTNET]
                : [],
        },
    },
    etherscan: {
        apiKey: {
            mainnet: process.env.ETHERSCAN_API_KEY_MAINNET || "",
            polygon: process.env.ETHERSCAN_API_KEY_POLYGON || "",
        },
    },
    gasReporter: {
        currency: "USD",
        gasPrice: 150,
        enabled: process.env.REPORT_GAS !== undefined,
    },
};
