// We require the Hardhat Runtime Environment explicitly here. This is optional 
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile 
  // manually to make sure everything is compiled
  // await hre.run('compile');

  console.log("Starts here! ")
  // Get signer
  let sign, addrs;

  // Set tester accounts
  const Tester1 = "0x2c4480C87430CB81fBd1c970b185116C067059AB"; //J
  const Tester2 = "0xCD26e540F773dbC7abC46db7E2830Ad7f735Ce86"; //SK
  const Tester3 = "0xb3328c95FD4b3aA42053a1c7Cf77F2d176e0b321";

  [sign, ...addrs] = await ethers.getSigners();

  // Assign contract objects
  const BASIC20 = await hre.ethers.getContractFactory("Basic20");
  const BASIC721 = await hre.ethers.getContractFactory("Basic721");
  const BASIC1155 = await hre.ethers.getContractFactory("Basic1155");

  const FAUCET = await hre.ethers.getContractFactory("Faucet");
  const PWN = await hre.ethers.getContractFactory("PWN");
  const PWNDEED = await hre.ethers.getContractFactory("PWNDeed");
  const PWNVAULT = await hre.ethers.getContractFactory("PWNVault");

  // Deploy test tokens of all kinds
  const DAI = await BASIC20.deploy("Test DAI", "DAI");
  await DAI.deployed();

  const WETH = await BASIC20.deploy("Test WETH", "WETH");
  await WETH.deployed();

  const TOK = await BASIC20.deploy("Test TOK", "TOK");
  await TOK.deployed();

  const NFTX = await BASIC721.deploy("Test NFTx", "NFTX");
  await NFTX.deployed();

  const NFTY = await BASIC721.deploy("Test NFTy", "NFTY");
  await NFTY.deployed();

  const NFTZ = await BASIC721.deploy("Test NFTz", "NFTZ");
  await NFTZ.deployed();

  const A1155 = await BASIC1155.deploy("https://api.pwn.finance/a/");
  await A1155.deployed();

  const B1155 = await BASIC1155.deploy("https://api.pwn.finance/b/");
  await B1155.deployed();

  console.log("Tokens deployed!");

  await NFTX.connect(sign).setBaseURI("https://api.pwn.finance/x/");
  await NFTY.connect(sign).setBaseURI("https://api.pwn.finance/y/");
  await NFTZ.connect(sign).setBaseURI("https://api.pwn.finance/z/");

  // deploy & populate faucet
  const Faucet = await FAUCET.deploy(DAI.address, WETH.address, TOK.address, NFTX.address, NFTY.address, NFTZ.address, A1155.address, B1155.address);
  await Faucet.deployed();

  console.log("Faucet deployed!");
  // await DAI.connect(sign).transferOwnership(Faucet.address);
  // await WETH.connect(sign).transferOwnership(Faucet.address);
  // await TOK.connect(sign).transferOwnership(Faucet.address);
  // await NFTX.connect(sign).transferOwnership(Faucet.address);
  // await NFTY.connect(sign).transferOwnership(Faucet.address);
  // await NFTZ.connect(sign).transferOwnership(Faucet.address);
  // await A1155.connect(sign).transferOwnership(Faucet.address);
  // await B1155.connect(sign).transferOwnership(Faucet.address);

  await Faucet.connect(sign).gimme(Tester1);
  await Faucet.connect(sign).gimme(Tester2);
  await Faucet.connect(sign).gimme(Tester3);

  console.log("Faucet utilized!");
  // Deploy PWN
  const PwnVault = await PWNVAULT.deploy();
  const PwnDeed = await PWNDEED.deploy("https://api.pwn.finance/deed/")

  await PwnVault.deployed();
  await PwnDeed.deployed();

  console.log("PWN D & V deployed!");
  const Pwn = await PWN.deploy(PwnDeed.address, PwnVault.address);
  await Pwn.deployed();

  console.log("PWN deployed!");

  // Dump to log
  console.log("PWN deployed at: `" + Pwn.address + "`");
  console.log("PWNDeed deployed at: `" + PwnDeed.address + "`");
  console.log("PWNVault deployed at: `" + PwnVault.address + "`");

  console.log("DAI deployed at: `" + DAI.address + "`");
  console.log("WETH deployed at: `" + WETH.address + "`");
  console.log("TOK deployed at: `" + TOK.address + "`");

  console.log("NFTX deployed at: `" + NFTX.address + "`");
  console.log("NFTY deployed at: `" + NFTY.address + "`");
  console.log("NFTZ deployed at: `" + NFTZ.address + "`");

  console.log("A1155 deployed at: `" + A1155.address + "`");
  console.log("B1155 deployed at: `" + B1155.address + "`");

  console.log("Faucet deployed at: `" + Faucet.address + "`");

  await PwnDeed.connect(sign).setPWN(Pwn.address);
  await PwnVault.connect(sign).setPWN(Pwn.address);

  // Pass ownership of PWN & Faucet
  await Pwn.connect(sign).transferOwnership(Tester1);
  // await Faucet.connect(sign).tranferOwnership(Tester1);


}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => {

    process.exit(0)})
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
