var chai = require("chai");

chai.use(require("chai-as-promised"));

var expect = chai.expect;

describe("PFOLIO V2 minmax", function () {
  let PFOLIO;
  let pfolio;
  let Token;
  let token1;
  let token2;
  let token3;
  let owner;
  let addrs;

  const ten = ethers.BigNumber.from("10");
  const ONE = ten.pow(18);
  const PERCENT = ONE.div(100);

  const fundSize = ten.pow(25);

  beforeEach(async function () {
    PFOLIO = await hre.ethers.getContractFactory("PFOLIO");
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

  it("Should get share 1/3", async function () {
    let bindSize = ten.pow(17);
    let min = PERCENT.mul(30);
    let max = PERCENT.mul(70);

    await pfolio.bind(token1.address, bindSize, min, max);
    await pfolio.bind(token2.address, bindSize, min, max);
    await pfolio.bind(token3.address, bindSize, min, max);

    const price = ONE.mul(1);

    await pfolio.setOraclePrice(token1.address, price);
    await pfolio.setOraclePrice(token2.address, price);
    await pfolio.setOraclePrice(token3.address, price);

    await pfolio.updatePortfolioValue();

    share = await pfolio.getCurrentShare(token1.address);

    expect(share.eq(ONE.div(3))).to.be.true;
  });

  it("Should get share 1/5", async function () {
    let bindSize = ten.pow(17);
    let min = PERCENT.mul(30);
    let max = PERCENT.mul(70);

    await pfolio.bind(token1.address, bindSize, min, max);
    await pfolio.bind(token2.address, bindSize, min, max);
    await pfolio.bind(token3.address, bindSize, min, max);

    const price1 = ONE.mul(1);
    const price2 = ONE.mul(2);
    const price3 = ONE.mul(2);

    await pfolio.setOraclePrice(token1.address, price1);
    await pfolio.setOraclePrice(token2.address, price2);
    await pfolio.setOraclePrice(token3.address, price3);

    await pfolio.updatePortfolioValue();

    share = await pfolio.getCurrentShare(token1.address);

    expect(share.eq(ONE.div(5))).to.be.true;
  });

  it("Should stay within limits and succeed", async function () {
    let bindSize = ten.pow(17);
    let min = PERCENT.mul(30);
    let max = PERCENT.mul(70);

    await pfolio.bind(token1.address, bindSize, min, max);
    await pfolio.bind(token2.address, bindSize, min, max);
    await pfolio.bind(token3.address, bindSize, min, max);

    const price = ONE.mul(1);

    await pfolio.setOraclePrice(token1.address, price);
    await pfolio.setOraclePrice(token2.address, price);
    await pfolio.setOraclePrice(token3.address, price);

    const tradeOne = ten.pow(11);

    expect(
      pfolio.sellBaseToken(token1.address, token2.address, tradeOne.mul(5), 1)
    ).to.be.fulfilled;
  });

  it("Should leave share limits and fail", async function () {
    let bindSize = ten.pow(17);
    let min = PERCENT.mul(30);
    let max = PERCENT.mul(70);

    await pfolio.bind(token1.address, bindSize, min, max);
    await pfolio.bind(token2.address, bindSize, min, max);
    await pfolio.bind(token3.address, bindSize, min, max);

    const price = ONE.mul(1);

    await pfolio.setOraclePrice(token1.address, price);
    await pfolio.setOraclePrice(token2.address, price);
    await pfolio.setOraclePrice(token3.address, price);

    const tradeOne = ten.pow(18);

    return expect(
      pfolio.sellBaseToken(token1.address, token2.address, tradeOne.mul(5), 1)
    ).to.be.rejectedWith(
      "VM Exception while processing transaction: revert GAIN OUTSIDE MAX"
    );
  });
});
