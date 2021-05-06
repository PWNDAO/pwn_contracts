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
  const Tester1 = "0x2c4480C87430CB81fBd1c970b185116C067059AB"; //J

  console.log("Starts here! ")
  // Get signer
  let sign, addrs;

  [sign, ...addrs] = await ethers.getSigners();

  const PWN = await hre.ethers.getContractFactory("PWN");
  const PWNDEED = await hre.ethers.getContractFactory("PWNDeed");
  const PWNVAULT = await hre.ethers.getContractFactory("PWNVault");

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


  await PwnDeed.connect(sign).setPWN(Pwn.address);
  await PwnVault.connect(sign).setPWN(Pwn.address);

  // Pass ownership of PWN & Faucet
  await Pwn.connect(sign).transferOwnership(Tester1);

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
