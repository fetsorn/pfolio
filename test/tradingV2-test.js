var chai = require("chai");

chai.use(require("chai-as-promised"));

var expect = chai.expect;

describe("PFOLIO V2 trading", function () {
  let PFOLIO;
  let pfolio;
  let Token;
  let token1;
  let token2;
  let token3;
  let owner;
  let addrs;
  let fundSize;
  let priceOne;

  let ten = ethers.BigNumber.from("10");
  let ONE = ten.pow(18);
  let PERCENT = ONE.div(100);
  let bindSize = ten.pow(17).mul(1);
  let min = PERCENT.mul(30);
  let max = PERCENT.mul(70);

  beforeEach(async function () {
    PFOLIO = await hre.ethers.getContractFactory("PFOLIO");
    pfolio = await PFOLIO.deploy();

    Token = await ethers.getContractFactory("ERC20PresetMinterPauser");
    [owner, ...addrs] = await ethers.getSigners();

    token1 = await Token.deploy("gold", "AU");
    token2 = await Token.deploy("silver", "AG");
    token3 = await Token.deploy("bronze", "BZ");

    fundSize = ten.pow(19);

    await token1.mint(owner.address, fundSize);
    await token2.mint(owner.address, fundSize);
    await token3.mint(owner.address, fundSize);

    await token1.approve(pfolio.address, fundSize);
    await token2.approve(pfolio.address, fundSize);
    await token3.approve(pfolio.address, fundSize);

    await pfolio.bind(token1.address, bindSize, min, max);
    await pfolio.bind(token2.address, bindSize, min, max);
    await pfolio.bind(token3.address, bindSize, min, max);

    priceOne = ten.pow(18);
  });

  it("Should query 1/1", async function () {
    const priceBase = priceOne.mul(1);
    const priceQuote = priceOne.mul(1);

    await pfolio.setOraclePrice(token1.address, priceBase);
    await pfolio.setOraclePrice(token2.address, priceQuote);

    let buy = await pfolio.queryBuyBaseToken(
      token1.address,
      token2.address,
      ten.pow(11).mul(5)
    );

    let sell = await pfolio.querySellBaseToken(
      token1.address,
      token2.address,
      ten.pow(11).mul(5)
    );

    let lower = ten.pow(11).mul(49).div(10); // 4.9
    let upper = ten.pow(11).mul(51).div(10); // 5.1
    expect(buy.gte(lower)).to.be.true;
    expect(buy.lte(upper)).to.be.true;
    expect(sell.gte(lower)).to.be.true;
    expect(sell.lte(upper)).to.be.true;
  });

  it("Should query 1/10", async function () {
    const priceBase = priceOne.mul(10);
    const priceQuote = priceOne.mul(1);

    await pfolio.setOraclePrice(token1.address, priceBase);
    await pfolio.setOraclePrice(token2.address, priceQuote);

    let tradeOne = ten.pow(11);

    let buy = await pfolio.queryBuyBaseToken(
      token1.address,
      token2.address,
      tradeOne.mul(5)
    );

    let sell = await pfolio.querySellBaseToken(
      token1.address,
      token2.address,
      tradeOne.mul(5)
    );

    let lower = tradeOne.mul(499).div(10); // 49.9
    let upper = tradeOne.mul(511).div(10); // 50.1
    expect(buy.gte(lower)).to.be.true;
    expect(buy.lte(upper)).to.be.true;
    expect(sell.gte(lower)).to.be.true;
    expect(sell.lte(upper)).to.be.true;
  });

  it("Should query 1/100", async function () {
    const priceBase = priceOne.mul(100);
    const priceQuote = priceOne.mul(1);

    await pfolio.setOraclePrice(token1.address, priceBase);
    await pfolio.setOraclePrice(token2.address, priceQuote);

    let tradeOne = ten.pow(11);

    let buy = await pfolio.queryBuyBaseToken(
      token1.address,
      token2.address,
      tradeOne.mul(5)
    );

    let sell = await pfolio.querySellBaseToken(
      token1.address,
      token2.address,
      tradeOne.mul(5)
    );

    let lower = tradeOne.mul(499).div(1); // 499
    let upper = tradeOne.mul(501).div(1); // 501
    expect(buy.gte(lower)).to.be.true;
    expect(buy.lte(upper)).to.be.true;
    expect(sell.gte(lower)).to.be.true;
    expect(sell.lte(upper)).to.be.true;
  });

  it("Should query 10/1", async function () {
    const priceBase = priceOne.mul(1);
    const priceQuote = priceOne.mul(10);

    await pfolio.setOraclePrice(token1.address, priceBase);
    await pfolio.setOraclePrice(token2.address, priceQuote);

    let tradeOne = ten.pow(11);

    let buy = await pfolio.queryBuyBaseToken(
      token1.address,
      token2.address,
      tradeOne.mul(5)
    );

    let sell = await pfolio.querySellBaseToken(
      token1.address,
      token2.address,
      tradeOne.mul(5)
    );

    let lower = tradeOne.mul(49).div(100); // 0.49
    let upper = tradeOne.mul(51).div(100); // 0.51
    expect(buy.gte(lower)).to.be.true;
    expect(buy.lte(upper)).to.be.true;
    expect(sell.gte(lower)).to.be.true;
    expect(sell.lte(upper)).to.be.true;
  });

  it("Should sell 1/1", async function () {
    const price = priceOne.mul(1);

    await pfolio.setOraclePrice(token1.address, price);
    await pfolio.setOraclePrice(token2.address, price);

    let balance1_1 = await token1.balanceOf(owner.address);
    let balance2_1 = await token2.balanceOf(owner.address);

    let tradeOne = ten.pow(11);

    // console.log(
    //   "Owner has token1:",
    //   balance1_1.div(tradeOne).toString(),
    //   "token2:",
    //   balance2_1.div(tradeOne).toString()
    // );

    await pfolio.sellBaseToken(
      token1.address,
      token2.address,
      tradeOne.mul(5),
      1
    );

    let balance1_2 = await token1.balanceOf(owner.address);
    let balance2_2 = await token2.balanceOf(owner.address);

    // console.log(
    //   "Owner has token1:",
    //   balance1_2.div(tradeOne).toString(),
    //   "token2:",
    //   balance2_2.div(tradeOne).toString()
    // );

    let loss = balance1_1.sub(balance1_2);
    let gain = balance2_2.sub(balance2_1);

    // console.log(
    //   "owner lost token1:",
    //   loss.div(tradeOne).toString(),
    //   "owner gaine token2:",
    //   gain.div(tradeOne).toString()
    // );

    let lower = tradeOne.mul(49).div(10); // 4.9
    let upper = tradeOne.mul(50).div(10); // 5.0
    expect(loss.gte(lower)).to.be.true;
    expect(loss.lte(upper)).to.be.true;
    expect(gain.gte(lower)).to.be.true;
    expect(gain.lte(upper)).to.be.true;
  });
});
