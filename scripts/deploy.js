const hardhat = require("hardhat");
const { log, STYLE } = require("./scripts-helpers");
const { highlighted } = STYLE;


async function deploy() {
    // Get signer
    let signer, addrs;
    [signer, ...addrs] = await ethers.getSigners();

    const PWN = await hardhat.ethers.getContractFactory("PWN", signer);
    const PWNLOAN = await hardhat.ethers.getContractFactory("PWNLOAN", signer);
    const PWNVAULT = await hardhat.ethers.getContractFactory("PWNVault", signer);


    // Deploy contracts
    log("\n Deploying PWN contracts...\n", highlighted);

    const PwnVault = await PWNVAULT.deploy();
    log(" ⛏  Deploying PWNVault...   (tx: " + PwnVault.deployTransaction.hash + ")");
    const vaultPromise = PwnVault.deployed();

    const PwnLoan = await PWNLOAN.deploy("");
    log(" ⛏  Deploying PWNLOAN...   (tx: " + PwnLoan.deployTransaction.hash + ")");
    const loanPromise = PwnLoan.deployed();

    await Promise.all([vaultPromise, loanPromise]);
    log(" ✅ PWNVault deployed at: " + PwnVault.address);
    log(" ✅ PWNLOAN deployed at: " + PwnLoan.address);

    const Pwn = await PWN.deploy(PwnLoan.address, PwnVault.address);
    log(" ⛏  Deploying PWN...   (tx: " + Pwn.deployTransaction.hash + ")");
    await Pwn.deployed();
    log(" ✅ PWN deployed at: " + Pwn.address);


    log("\n 🎉🎉🎉 PWN contracts deployment script successfully finished 🎉🎉🎉\n", highlighted);
}


deploy()
    .then(() => {
        process.exit(0);
    })
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
