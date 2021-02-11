var chai = require("chai");
var chaiAsPromised = require("chai-as-promised");

chai.use(chaiAsPromised);
chai.use(require('chai-bignumber')(ethers.BigNumber));

// Then either:
var expect = chai.expect;

describe("PFOLIO V2 admin", function () {
  let PFOLIO;
  let pfolio;
  let Token;
  let token1;
  let token2;
  let token3;
  let owner;
  let addrs;
  let ten = ethers.BigNumber.from("10");
  let ONE = ten.pow(18);
  let PERCENT = ONE.div(100);
  let fundSize = ten.pow(25).toString();

  tstr = (n) => n.toString();

  beforeEach(async function () {
    PFOLIO = await hre.ethers.getContractFactory("PFOLIOV2");
    pfolio = await PFOLIO.deploy();

    Token = await ethers.getContractFactory("ERC20PresetMinterPauser");
    [owner, ...addrs] = await ethers.getSigners();

    token1 = await Token.deploy("gold", "AU");
    token2 = await Token.deploy("silver", "AG");
    token3 = await Token.deploy("bronze", "BZ");

    await token1.mint(owner.address, fundSize);
    await token2.mint(owner.address, fundSize);
    await token3.mint(owner.address, fundSize);

    await token1.approve(pfolio.address, fundSize);
    await token2.approve(pfolio.address, fundSize);
    await token3.approve(pfolio.address, fundSize);

  });

  describe("Deployment", function () {
    it("Should set token name", async function () {
      expect(await token1.name()).to.equal("gold");
    });

    it("Should bind token", async function () {

      let bindSize = ten.pow(17).mul(1);
      let min = PERCENT.mul(30);
      let max = PERCENT.mul(70);

      await pfolio.bind(token1.address, bindSize, min, max);

      let b = await pfolio.isBound(token1.address);

      expect(b).to.equal(true);
    });

    it("Should bind balance", async function () {

      let bindSize = ten.pow(17).mul(1);
      let min = PERCENT.mul(30);
      let max = PERCENT.mul(70);

      await pfolio.bind(token1.address, bindSize, min, max);

      let balance = await pfolio.getBalance(token1.address);

      expect(balance).to.eql(bindSize);
    });

    it("Should bind min share limit", async function () {

      let bindSize = ten.pow(17).mul(1);
      let min = PERCENT.mul(30);
      let max = PERCENT.mul(70);

      await pfolio.bind(token1.address, bindSize, min, max);

      let min1 = await pfolio.getMin(token1.address);

      expect(min1).to.eql(min);
    });

    it("Should bind max share limit", async function () {

      let bindSize = ten.pow(17).mul(1);
      let min = PERCENT.mul(30);
      let max = PERCENT.mul(70);

      await pfolio.bind(token1.address, bindSize, min, max);

      let max1 = await pfolio.getMax(token1.address);

      expect(max1).to.eql(max);
    });

    it("Should unbind token", async function () {

      let bindSize = ten.pow(17).mul(1);
      let min = PERCENT.mul(30);
      let max = PERCENT.mul(70);

      await pfolio.bind(token1.address, bindSize, min, max);

      let bound;

      bound = await pfolio.isBound(token1.address);

      expect(bound).to.equal(true);

      await pfolio.unbind(token1.address);

      bound = await pfolio.isBound(token1.address);

      expect(bound).to.equal(false);
    });

  });
});
