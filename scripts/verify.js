const hardhat = require("hardhat");
const { log, STYLE } = require("./scripts-helpers");
const { highlighted } = STYLE;
require("@nomiclabs/hardhat-etherscan");


const supportedNetworks = ["mainnet", "rinkeby"];

const pwnAddress = "0x...";
const pwnLoanAddress = "0x...";
const pwnVaultAddress = "0x...";
const metadataBaseUri = "https://api.pwn.xyz/";


async function verify() {
    if (supportedNetworks.includes(hardhat.network.name)) {

        log("\n Verify contracts on Etherscan", highlighted);

        const contracts = [
            {
                name: "PWN",
                address: pwnAddress,
                constructorArguments: [pwnLoanAddress, pwnVaultAddress]
            },
            {
                name: "PWNLOAN",
                address: pwnLoanAddress,
                constructorArguments: [metadataBaseUri]
            },
            {
                name: "PWNVault",
                address: pwnVaultAddress,
                constructorArguments: []
            },
        ];

        for (let i = 0; i < contracts.length; i++) {
            await verifyContract(contracts[i]);
        }

    } else if (hardhat.network.name == "localhost") {
        log("\n Skiping verifying contracts on Etherscan for localhost", highlighted);
    } else {
        log("\n Skiping verifying contracts on Etherscan for unknown network", highlighted);
    }

    log("\n 🎉🎉🎉 PWN contracts verification script successfully finished 🎉🎉🎉\n", highlighted);
}

async function verifyContract(contract) {
    log(` 🗄  Verifying ${contract.name} contract on Etherscan...`);
    try {
        await hardhat.run("verify:verify", {
            address: contract.address,
            constructorArguments: contract.constructorArguments
        });
    } catch(error) {
        if (["Already Verified", "Contract source code already verified"].includes(error.message)) {
            log( ` 💡 ${error.message}`);
        } else {
            throw error;
        }
    }
    log(` ✅ Verified ${contract.name} contract on Etherscan`);
}


verify()
    .then(() => {
        process.exit(0);
    })
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
