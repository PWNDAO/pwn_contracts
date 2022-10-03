const { ethers } = require("hardhat");
const { log, STYLE } = require("./scripts-helpers");
const { highlighted } = STYLE;


async function faucetDeploy() {
    // Get signer
    let signer, addrs;
    [signer, ...addrs] = await ethers.getSigners();

    // Assign contract objects
    const BASIC20 = await ethers.getContractFactory("Basic20");
    const BASIC721 = await ethers.getContractFactory("Basic721");
    const BASIC1155 = await ethers.getContractFactory("Basic1155");
    const FAUCET = await ethers.getContractFactory("Faucet");

    log("\n Deploying Faucet contracts...\n", highlighted);

    // Deploy test tokens of all kinds
    const DAI = await BASIC20.deploy("Test DAI", "DAI");
    log(" ⛏  Deploying DAI...   (tx: " + DAI.deployTransaction.hash + ")");
    await DAI.deployed();
    log(" ✅ DAI deployed at: " + DAI.address);

    const WETH = await BASIC20.deploy("Test WETH", "WETH");
    log(" ⛏  Deploying WETH...   (tx: " + WETH.deployTransaction.hash + ")");
    await WETH.deployed();
    log(" ✅ WETH deployed at: " + WETH.address);

    const TOK = await BASIC20.deploy("Test TOK", "TOK");
    log(" ⛏  Deploying TOK...   (tx: " + TOK.deployTransaction.hash + ")");
    await TOK.deployed();
    log(" ✅ TOK deployed at: " + TOK.address);

    const NFTX = await BASIC721.deploy("Test NFTx", "NFTX");
    log(" ⛏  Deploying NFTX...   (tx: " + NFTX.deployTransaction.hash + ")");
    await NFTX.deployed();
    log(" ✅ NFTX deployed at: " + NFTX.address);

    const NFTY = await BASIC721.deploy("Test NFTy", "NFTY");
    log(" ⛏  Deploying NFTY...   (tx: " + NFTY.deployTransaction.hash + ")");
    await NFTY.deployed();
    log(" ✅ NFTY deployed at: " + NFTY.address);

    const NFTZ = await BASIC721.deploy("Test NFTz", "NFTZ");
    log(" ⛏  Deploying NFTZ...   (tx: " + NFTZ.deployTransaction.hash + ")");
    await NFTZ.deployed();
    log(" ✅ NFTZ deployed at: " + NFTZ.address);

    const A1155 = await BASIC1155.deploy("https://api.pwn.xyz/a/");
    log(" ⛏  Deploying A1155...   (tx: " + A1155.deployTransaction.hash + ")");
    await A1155.deployed();
    log(" ✅ A1155 deployed at: " + A1155.address);

    const B1155 = await BASIC1155.deploy("https://api.pwn.xyz/b/");
    log(" ⛏  Deploying B1155...   (tx: " + B1155.deployTransaction.hash + ")");
    await B1155.deployed();
    log(" ✅ B1155 deployed at: " + B1155.address);

    log("\n Faucet tokens deployed!\n", highlighted);


    await NFTX.connect(signer).setBaseURI("https://api.pwn.xyz/x/");
    await NFTY.connect(signer).setBaseURI("https://api.pwn.xyz/y/");
    await NFTZ.connect(signer).setBaseURI("https://api.pwn.xyz/z/");

    // deploy & populate faucet
    const Faucet = await FAUCET.deploy(DAI.address, WETH.address, TOK.address, NFTX.address, NFTY.address, NFTZ.address, A1155.address, B1155.address, 1);
    log(" ⛏  Deploying Faucet...   (tx: " + Faucet.deployTransaction.hash + ")");
    await Faucet.deployed();
    log(" ✅ Faucet deployed at: " + Faucet.address);

    log("\n 🎉🎉🎉 Faucet deploy script successfully finished 🎉🎉🎉\n", highlighted);
}


faucetDeploy()
    .then(() => {
        process.exit(0)})
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
