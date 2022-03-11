const hardhat = require("hardhat");
const readline = require("readline");
require("@nomiclabs/hardhat-etherscan");

const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
});


const highlighted = "\x1b[32m";
const basic = "\x1b[36m";
const reset = "\x1b[0m";

function log(text, style = basic) {
    process.stdout.clearLine();
    console.log(style, text, reset);
}

function moveToLine(line) {
    process.stdout.moveCursor(0, line);
}


function main() {
    const Owner = "0x2c4480C87430CB81fBd1c970b185116C067059AB"; //J
    const metadataUri = "https://api.pwn.finance/deed/{id}.json";

    log("\n ===============================", highlighted);
    log("PWN contracts deployment script", highlighted);
    log("===============================\n", highlighted);


    let question = "\x1b[36mMetadataUri:\t" + metadataUri + "\n";
    question += "Owner:\t\t" + Owner + "\n\n";
    question += "\x1b[0mDo you want to continue? (y/n): ";

    rl.question(question, async function(answer) {
        if (answer.toLowerCase() == "y" || answer.toLowerCase() == "yes") {
            deploy(Owner, metadataUri)
                .then(() => {
                    process.exit(0);
                })
                .catch(error => {
                    console.error(error);
                    process.exit(1);
                });
        } else {
            rl.close();
        }
    });

    rl.on("close", function() {
        process.exit(0);
    });
}

async function deploy(Owner, metadataUri) {
    // Get signer
    let sign, addrs;
    [sign, ...addrs] = await ethers.getSigners();

    const PWN = await hardhat.ethers.getContractFactory("PWN");
    const PWNLOAN = await hardhat.ethers.getContractFactory("PWNLOAN");
    const PWNVAULT = await hardhat.ethers.getContractFactory("PWNVault");


    // Deploy contracts
    log("\n Deploying PWN contracts...\n", highlighted);

    const PwnVault = await PWNVAULT.deploy();
    log(" ⛏  Deploying PWNVault...   (tx: " + PwnVault.deployTransaction.hash + ")");
    const vaultPromise = PwnVault.deployed();

    const PwnLoan = await PWNLOAN.deploy(metadataUri);
    log(" ⛏  Deploying PWNLOAN...   (tx: " + PwnLoan.deployTransaction.hash) + ")";
    const loanPromise = PwnLoan.deployed();

    await Promise.all([vaultPromise, loanPromise]);
    moveToLine(-2);
    log(" PWNVault deployed at: `" + PwnVault.address + "`");
    log(" PWNLOAN deployed at: `" + PwnLoan.address + "`");

    const Pwn = await PWN.deploy(PwnLoan.address, PwnVault.address);
    log(" ⛏  Deploying PWN...   (tx: " + Pwn.deployTransaction.hash + ")");
    await Pwn.deployed();
    moveToLine(-1);
    log(" PWN deployed at: `" + Pwn.address + "`");

    log("\n 🎉 PWN contracts deployed 🎉\n", highlighted);


    // Set PWN contract
    const pwnToLoan = await PwnLoan.connect(sign).setPWN(Pwn.address);
    log(" ⛏  Setting PWN address to PWNLOAN...   (tx: " + pwnToLoan.hash + ")");
    const pwnToLoanPromise = pwnToLoan.wait();

    const pwnToVault = await PwnVault.connect(sign).setPWN(Pwn.address);
    log(" ⛏  Setting PWN address to PWNVault...   (tx: " + pwnToVault.hash + ")");
    const pwnToVaultPromise = pwnToVault.wait();

    await Promise.all([pwnToLoanPromise, pwnToVaultPromise]);
    moveToLine(-2);
    log(" PWNLOAN PWN address set");
    log(" PWNVault PWN address set");


    // Pass ownership of PWN contracts to Owner
    log("\n Transfer PWN ownership to " + Owner + "\n", highlighted);

    const ownershipPwn = await Pwn.connect(sign).transferOwnership(Owner);
    log(" ⛏  Transferring PWN ownership...   (tx: " + ownershipPwn.hash + ")");
    const ownershipPwnPromise = ownershipPwn.wait();

    const ownershipLOAN = await PwnLoan.connect(sign).transferOwnership(Owner);
    log(" ⛏  Transferring PWNLOAN ownership...   (tx: " + ownershipLOAN.hash + ")");
    const ownershipLOANPromise = ownershipLOAN.wait();

    const ownershipVault = await PwnVault.connect(sign).transferOwnership(Owner);
    log(" ⛏  Transferring PWNVault ownership...   (tx: " + ownershipVault.hash + ")");
    const ownershipVaultPromise = ownershipVault.wait();

    await Promise.all([ownershipPwnPromise, ownershipLOANPromise, ownershipVaultPromise]);
    moveToLine(-3);
    log(" PWN ownership transferred");
    log(" PWNLOAN ownership transferred");
    log(" PWNVault ownership transferred");


    // Verify contract code on Etherscan
    if (hardhat.network.name == "mainnet" || hardhat.network.name == "rinkeby") {
        log("\n Verify contracts on Etherscan", highlighted);

        log(" 🗄  Verifying PWN contract on Etherscan...");
        try {
            await hardhat.run("verify:verify", {
                address: Pwn.address,
                constructorArguments: [PwnLoan.address, PwnVault.address]
            });
        } catch(error) {
            if (error.message != "Already Verified" && error.message != "Contract source code already verified") {
                throw error;
            }
        }
        log(" Verified PWN contract on Etherscan");

        log(" 🗄  Verifying PWNLOAN contract on Etherscan...");
        try {
            await hardhat.run("verify:verify", {
                address: PwnLoan.address,
                constructorArguments: [metadataUri]
            });
        } catch(error) {
            if (error.message != "Already Verified" && error.message != "Contract source code already verified") {
                throw error;
            }
        }
        log(" Verified PWNLOAN contract on Etherscan");

        log(" 🗄  Verifying PWNVault contract on Etherscan...");
        try {
            await hardhat.run("verify:verify", {
                address: PwnVault.address,
                constructorArguments: []
            });
        } catch(error) {
            if (error.message != "Already Verified" && error.message != "Contract source code already verified") {
                throw error;
            }
        }
        log(" Verified PWNVault contract on Etherscan");

    } else if (hardhat.network.name == "localhost") {
        log("\n Skiping verifying contracts on Etherscan for localhost", highlighted);
    } else {
        log("\n Skiping verifying contracts on Etherscan for unknown network", highlighted);
    }


    log("\n 🎉🎉🎉 PWN contracts deployment script successfully finished 🎉🎉🎉\n", highlighted);
}

main();
