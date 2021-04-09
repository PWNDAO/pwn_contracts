const { expect } = require("chai");

const delay = ms => new Promise(res => setTimeout(res, ms));

let ERC20;
let ERC721;
let ERC1155;

let NFT, WETH, DAI;

let PWN;
let PWNDeed;
let PWNVault;

let owner;

let borrower;
let lender1;
let lender2;

let addr1;
let addr2;
let addrs;

let date = new Date();

// `beforeEach` will run before each test, re-deploying the contract every
// time. It receives a callback, which can be async.

beforeEach(async function () {
  // Get the ContractFactory and Signers here.
  ERC20 = await ethers.getContractFactory("Basic20");
  ERC721 = await ethers.getContractFactory("Basic721");
  ERC1155 = await ethers.getContractFactory("Basic1155");

  PWN = await ethers.getContractFactory("PWN");
  PWNDeed = await ethers.getContractFactory("PWNDeed");
  PWNVault = await ethers.getContractFactory("PWNVault");

  [borrower, lender1, lender2, addr1, addr2, ...addrs] = await ethers.getSigners();

  WETH = await ERC20.deploy("Fake wETH", "WETH");
  DAI = await ERC20.deploy("Fake Dai", "DAI");
  NFT = await ERC721.deploy("Real NFT", "NFT");

  PWNDeed = await PWNDeed.deploy("https://pwn.finance/");
  PWNVault = await PWNVault.deploy();
  PWN = await PWN.deploy(PWNDeed.address, PWNVault.address);

  await NFT.deployed();
  await DAI.deployed();
  await PWNDeed.deployed();
  await PWNVault.deployed();
  await PWN.deployed();

  await PWNDeed.setPWN(PWN.address);
  await PWNVault.setPWN(PWN.address);

  await DAI.mint(lender1.getAddress(),1000);
  await DAI.mint(borrower.getAddress(),200);
  await NFT.mint(borrower.getAddress(),42);

  bDAI = DAI.connect(borrower);
  lDAI = DAI.connect(lender1);
  bNFT = NFT.connect(borrower);
  lNFT = NFT.connect(lender1);
  bPWN = PWN.connect(borrower);
  lPWN = PWN.connect(lender1);
  bPWND = PWNDeed.connect(borrower);
  lPWND = PWNDeed.connect(lender1);
});

describe("Pawnage contract", function () {

  // You can nest describe calls to create subsections.
  describe("Deployment", function () {
    it("Should deploy PWN with links to Deed & Vault", async function () {
      expect(await PWN.token()).to.equal(await PWNDeed.address);
      expect(await PWN.vault()).to.equal(await PWNVault.address);
    });
    it("Should deploy Vault with a link to PWN", async function () {
      expect(await PWNVault.PWN()).to.equal(await PWN.address);
    });
    it("Should deploy Deed with a link to PWN", async function () {
      expect(await PWNDeed.PWN()).to.equal(await PWN.address);
    });
    it("Should set initial balances", async function () {
      expect(await DAI.balanceOf(borrower.getAddress())).to.equal(200);
      expect(await DAI.balanceOf(lender1.getAddress())).to.equal(1000);
      expect(await NFT.ownerOf(42)).to.equal(await borrower.getAddress());
    });
  });

  describe("Workflow", function () {
    it("Should be possible to create an ERC20 deed", async function () {
      await bDAI.approve(PWNVault.address, 100);
      await bPWN.newDeed(0, 0, 100, DAI.address, date.setDate(date.getDate() + 1));

      const eventFilter = PWN.filters.NewDeed();
      const events = await PWN.queryFilter(eventFilter, "latest");
      const DID = events[0].args[5];

      const balance = await PWNDeed.balanceOf(borrower.getAddress(), DID.toNumber());

      expect(await DAI.balanceOf(PWNVault.address)).to.equal(100);
      expect(balance.toNumber()).to.equal(1);
    });

    it("Should be possible to create an NFT deed", async function () {
      await bNFT.approve(PWNVault.address, 42);
      await bPWN.newDeed(1, 42, 0, NFT.address, date.setDate(date.getDate() + 1));
      const eventFilter = PWN.filters.NewDeed();
      const events = await PWN.queryFilter(eventFilter, "latest");
      const DID = events[0].args[5];

      // await PWN.on("NewDeed", async (cat, id, amount, tokenAddress, expiration, did) => {
      //   DeedID = did.toNumber();
      // });

      const balance = await PWNDeed.balanceOf(borrower.getAddress(), DID.toNumber());
      expect(await NFT.ownerOf(42)).to.equal(PWNVault.address);
      expect(balance).to.equal(1);
    });
    it("Should be possible get an offer", async function () {

      await bPWND.setApprovalForAll(PWNVault.address, true);

      await bNFT.approve(PWNVault.address, 42);
      await bPWN.newDeed(1, 42, 0, NFT.address, date.setDate(date.getDate() + 1));
      const eventFilter = PWN.filters.NewDeed();
      const events = await PWN.queryFilter(eventFilter, "latest");
      const DID = (events[0].args[5]).toNumber();

      await lDAI.approve(PWNVault.address, 1000);
      await lPWN.makeOffer(0, 1000, lDAI.address, DID, 1200);
      const eventFilter2 = PWN.filters.NewOffer();
      const events2 = await PWN.queryFilter(eventFilter2, "latest");
      const offer = (events2[0].args[5]);

      const offers = await PWNDeed.getOffers(DID);

      expect(offers[0]).is.equal(offer);
      // expect(await PWNDeed.getDeedID(offer)).is.equal(DID);
    });

    it("Should be possible to accept an offer", async function () {

      await bPWND.setApprovalForAll(PWNVault.address, true);

      await bNFT.approve(PWNVault.address, 42);
      await bPWN.newDeed(1, 42, 0, NFT.address, date.setDate(date.getDate() + 1));
      const eventFilter = PWN.filters.NewDeed();
      const events = await PWN.queryFilter(eventFilter, "latest");
      const DID = (events[0].args[5]).toNumber();


      console.log("DAI Balalnce:" + await DAI.balanceOf(lender1.getAddress()));
      const a = await lDAI.approve(PWNVault.address, 1000);
      console.log(a);
      await lPWN.makeOffer(0, 1000, DAI.address, DID, 1200);
      const eventFilter2 = PWN.filters.NewOffer();
      const events2 = await PWN.queryFilter(eventFilter2, "latest");
      const offer = (events2[0].args[5]);

      // const offers = await PWNDeed.getOffers(DID); /TODO: make multiple offers and pick at random

      await bPWN.acceptOffer(DID, offer);

      const eventFilter3 = PWN.filters.OfferAccepted();
      const events3 = await PWN.queryFilter(eventFilter3, "latest");
      const args3 = (events3[0].args);

      console.log("B: " + borrower.getAddress());
      console.log("L: " + lender1.getAddress());

      expect(await PWNDeed.getAcceptedOffer(DID)).is.equal(offer);
      expect(await DAI.balanceOf(borrower.getAddress())).is.equal(1200);
      expect(await DAI.balanceOf(lender1.getAddress())).is.equal(0);
      expect(await DAI.balanceOf(borrower.getAddress())).is.equal(1200);
      expect(await NFT.ownerOf(42)).to.equal(PWNVault.address);

      BBalance = await PWNDeed.balanceOf(borrower.getAddress(), DID.toNumber());
      LBalance = await PWNDeed.balanceOf(lender1.getAddress(), DID.toNumber());

      expect(BBalance.toNumber()).to.equal(0);
      expect(LBalance.toNumber()).to.equal(1);
    });

  });
});

