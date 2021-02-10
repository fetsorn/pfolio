const { expect } = require("chai");

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
  let bindSize;
  let priceOne;
  let tradeOne;

  tstr = (n) => n.toString();

  beforeEach(async function () {
    PFOLIO = await hre.ethers.getContractFactory("PFOLIOV2");
    pfolio = await PFOLIO.deploy();

    Token = await ethers.getContractFactory("ERC20PresetMinterPauser");
    [owner, ...addrs] = await ethers.getSigners();

    token1 = await Token.deploy("gold", "AU");
    token2 = await Token.deploy("silver", "AG");
    token3 = await Token.deploy("bronze", "BZ");

    fundSize = Math.pow(10, 19).toString();

    await token1.mint(owner.address, fundSize);
    await token2.mint(owner.address, fundSize);
    await token3.mint(owner.address, fundSize);

    await token1.approve(pfolio.address, fundSize);
    await token2.approve(pfolio.address, fundSize);
    await token3.approve(pfolio.address, fundSize);

    bindSize = Math.pow(10, 17).toString();

    await pfolio.bind(token1.address, bindSize);
    await pfolio.bind(token2.address, bindSize);
    await pfolio.bind(token3.address, bindSize);

    priceOne = Math.pow(10, 18);
    tradeOne = Math.pow(10, 11);
  });

  describe("Deployment", function () {
    it("Should set the right token name", async function () {
      expect(await token1.name()).to.equal("gold");
    });

    it("Should bind 10^17 to pool", async function () {
      expect(await pfolio.getBalance(token1.address)).to.equal(bindSize);
    });

    it("Should query 1/1", async function () {
       const priceBase  = (1*priceOne).toString();
       const priceQuote = (1*priceOne).toString();

      await pfolio.setOraclePrice(token1.address, priceBase);
      await pfolio.setOraclePrice(token2.address, priceQuote);

      let buy = await pfolio
        .queryBuyBaseToken(token1.address, token2.address, 5 * tradeOne)
        .then((n1, n2, n3, n4) => n1.toString())
        .then((s) => s.split(",")[0]);

      let sell = await pfolio
        .querySellBaseToken(token1.address, token2.address, 5 * tradeOne)
        .then((n1, n2, n3, n4) => n1.toString())
        .then((s) => s.split(",")[0]);

      expect(buy / tradeOne).to.within(4.9, 5.1);
      expect(sell / tradeOne).to.within(4.9, 5.1);
    });

    it("Should query 1/10", async function () {
       const priceBase  = (10*priceOne).toString();
       const priceQuote = (1*priceOne).toString();

      await pfolio.setOraclePrice(token1.address, priceBase);
      await pfolio.setOraclePrice(token2.address, priceQuote);

      let buy = await pfolio
        .queryBuyBaseToken(token1.address, token2.address, 5 * tradeOne)
        .then((n1, n2, n3, n4) => n1.toString())
        .then((s) => s.split(",")[0]);

      let sell = await pfolio
        .querySellBaseToken(token1.address, token2.address, 5 * tradeOne)
        .then((n1, n2, n3, n4) => n1.toString())
        .then((s) => s.split(",")[0]);

      expect(buy / tradeOne).to.within(49.9, 50.1);
      expect(sell / tradeOne).to.within(49.9, 50.1);
    });

    it("Should query 1/100", async function () {
       const priceBase  = (100*priceOne).toString();
       const priceQuote = (1*priceOne).toString();

      await pfolio.setOraclePrice(token1.address, priceBase);
      await pfolio.setOraclePrice(token2.address, priceQuote);

      let buy = await pfolio
        .queryBuyBaseToken(token1.address, token2.address, 5 * tradeOne)
        .then((n1, n2, n3, n4) => n1.toString())
        .then((s) => s.split(",")[0]);

      let sell = await pfolio
        .querySellBaseToken(token1.address, token2.address, 5 * tradeOne)
        .then((n1, n2, n3, n4) => n1.toString())
        .then((s) => s.split(",")[0]);

      expect(buy / tradeOne).to.within(499, 501);
      expect(sell / tradeOne).to.within(499, 501);
    });

    it("Should query 10/1", async function () {
       const priceBase  = (1*priceOne).toString();
       const priceQuote = (10*priceOne).toString();

      await pfolio.setOraclePrice(token1.address, priceBase);
      await pfolio.setOraclePrice(token2.address, priceQuote);

      let buy = await pfolio
        .queryBuyBaseToken(token1.address, token2.address, 5 * tradeOne)
        .then((n1, n2, n3, n4) => n1.toString())
        .then((s) => s.split(",")[0]);

      let sell = await pfolio
        .querySellBaseToken(token1.address, token2.address, 5 * tradeOne)
        .then((n1, n2, n3, n4) => n1.toString())
        .then((s) => s.split(",")[0]);

      expect(buy / tradeOne).to.within(0.49, 0.51);
      expect(sell / tradeOne).to.within(0.49, 0.51);
    });

    it("Should sell 1/1", async function () {
       const priceBase  = (1*priceOne).toString();
       const priceQuote = (1*priceOne).toString();

      await pfolio.setOraclePrice(token1.address, priceBase);
      await pfolio.setOraclePrice(token2.address, priceQuote);

      let balance1_1 = await token1
        .balanceOf(owner.address)
        .then(tstr)
        .then(parseInt);
      let balance2_1 = await token2
        .balanceOf(owner.address)
        .then(tstr)
        .then(parseInt);

      // console.log(
      //   "Owner has token1:",
      //   balance1_1 / tradeOne,
      //   "token2:",
      //   balance2_1 / tradeOne
      // );

      await pfolio
        .sellBaseToken(token1.address, token2.address, 5 * tradeOne, 1)
        .then((n) => n.toString());

      let balance1_2 = await token1
        .balanceOf(owner.address)
        .then(tstr)
        .then(parseInt);
      let balance2_2 = await token2
        .balanceOf(owner.address)
        .then(tstr)
        .then(parseInt);

      // console.log(
      //   "Owner has token1:",
      //   balance1_2 / tradeOne,
      //   "token2:",
      //   balance2_2 / tradeOne
      // );

      expect((balance1_1 - balance1_2) / tradeOne).to.within(4.9, 5.1);
      expect((balance2_2 - balance2_1) / tradeOne).to.within(4.9, 5.1);
    });
  });
});
