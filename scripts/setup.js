const hardhat = require("hardhat");
const { log, STYLE } = require("./scripts-helpers");
const { highlighted } = STYLE;


const owner = "0x...";
const pwnAddress = "0x...";
const pwnLoanAddress = "0x...";
const pwnVaultAddress = "0x...";
const metadataBaseUri = "https://api.pwn.xyz/";


async function setup() {
    // Get signer
    let signer, addrs;
    [signer, ...addrs] = await ethers.getSigners();

    const Pwn = await hardhat.ethers.getContractAt("PWN", pwnAddress);
    const PwnLoan = await hardhat.ethers.getContractAt("PWNLOAN", pwnLoanAddress);
    const PwnVault = await hardhat.ethers.getContractAt("PWNVault", pwnVaultAddress);


    // Set PWNLOAN metadata
    const metadata = metadataBaseUri + `loan/${hardhat.network.config.chainId}/${PwnLoan.address}/{id}/metadata`;
    const pwnloanMetadata = await PwnLoan.connect(signer).setUri(metadata);
    log(" ⛏  Setting PWNLOAN metadata...   (tx: " + pwnloanMetadata.hash + ")");
    await pwnloanMetadata.wait();
    log(" ✅ PWNLOAN metadata set to " + metadata);


    // Set PWN contract address
    const pwnToLoan = await PwnLoan.connect(signer).setPWN(Pwn.address);
    log(" ⛏  Setting PWN address to PWNLOAN...   (tx: " + pwnToLoan.hash + ")");
    const pwnToLoanPromise = pwnToLoan.wait();

    const pwnToVault = await PwnVault.connect(signer).setPWN(Pwn.address);
    log(" ⛏  Setting PWN address to PWNVault...   (tx: " + pwnToVault.hash + ")");
    const pwnToVaultPromise = pwnToVault.wait();

    await Promise.all([pwnToLoanPromise, pwnToVaultPromise]);
    log(" ✅ PWNLOAN PWN address set");
    log(" ✅ PWNVault PWN address set");


    // Pass ownership of PWN contracts to Owner
    if (owner.toLowerCase() != signer.address.toLowerCase()) {
        log("\n Transfer PWN ownership to " + owner + "\n", highlighted);

        const ownershipPwn = await Pwn.connect(signer).transferOwnership(owner);
        log(" ⛏  Transferring PWN ownership...   (tx: " + ownershipPwn.hash + ")");
        const ownershipPwnPromise = ownershipPwn.wait();

        const ownershipLOAN = await PwnLoan.connect(signer).transferOwnership(owner);
        log(" ⛏  Transferring PWNLOAN ownership...   (tx: " + ownershipLOAN.hash + ")");
        const ownershipLOANPromise = ownershipLOAN.wait();

        const ownershipVault = await PwnVault.connect(signer).transferOwnership(owner);
        log(" ⛏  Transferring PWNVault ownership...   (tx: " + ownershipVault.hash + ")");
        const ownershipVaultPromise = ownershipVault.wait();

        await Promise.all([ownershipPwnPromise, ownershipLOANPromise, ownershipVaultPromise]);
        log(" ✅ PWN ownership transferred");
        log(" ✅ PWNLOAN ownership transferred");
        log(" ✅ PWNVault ownership transferred");
    } else {
        log(" 💡 Owner address is the same as a signer address, skipping setting ownership txs");
    }


    log("\n 🎉🎉🎉 PWN contracts setup script successfully finished 🎉🎉🎉\n", highlighted);
}


setup()
    .then(() => {
        process.exit(0);
    })
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
