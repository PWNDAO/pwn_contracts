require("@nomiclabs/hardhat-waffle");
require('@openzeppelin/hardhat-upgrades');
const KEYS = require("./.keys/PRIVATE.json");
// import * as KEYS from './.keys/PRIVATE.json';

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async () => {
  const accounts = await ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

const KOVAN_PRIVATE_KEY = KEYS.key1;

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: "0.8.4",
  networks: {
    kovan: {
      url: `https://kovan.infura.io/v3/2e64f610a85f433d83a708df23e6e71f`,
      accounts: [`0x${KOVAN_PRIVATE_KEY}`]
    }
  }
};

// npx hardhat run script.js