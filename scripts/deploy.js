const hre = require("hardhat");

async function main() {

  // get default account
  const account = await ethers.getSigners().then((as) => as[0].address);
  tstr = (n) => n.toString();

  // deploy pool
  console.log("Deploying PFOLIO...")

  const PFOLIO = await hre.ethers.getContractFactory("PFOLIO");
  const pfolio = await PFOLIO.deploy();

  await pfolio.deployed();

  console.log("PFOLIO deployed to:", pfolio.address)

  // deploy two presets
  console.log("Deploying presets...")

  const Token = await hre.ethers.getContractFactory("ERC20PresetMinterPauser");
  const token1 = await Token.deploy("gold", "AU");
  console.log("token1 deployed to:", token1.address)
  const token2 = await Token.deploy("silver", "AG");
  console.log("token2 deployed to:", token2.address)
  const token3 = await Token.deploy("bronze", "BZ");
  console.log("token3 deployed to:", token3.address)
  // mint a bunch of cash from presets
  console.log("Minting presets...")

  const fundSize = (Math.pow(10, 19)).toString();

  const name1 = await token1.name()
  await token1.mint(account, fundSize);
  const mint1 = await token1.balanceOf(account).then(tstr);
  console.log(mint1, name1);

  const name2 = await token2.name()
  await token2.mint(account, fundSize);
  const mint2 = await token2.balanceOf(account).then(tstr);
  console.log(mint2, name2);

  const name3 = await token3.name()
  await token3.mint(account, fundSize);
  const mint3 = await token3.balanceOf(account).then(tstr);
  console.log(mint3, name3);
  //aprrove presets for pool
  console.log("Approving presets...");

  await token1.approve(pfolio.address, fundSize);
  await token2.approve(pfolio.address, fundSize);
  await token3.approve(pfolio.address, fundSize);
  console.log("Assets approved");

  // bind presets
  console.log("Binding presets...");

  const bindSize = (Math.pow(10, 17)).toString();

  await pfolio.bind(token1.address, bindSize);
  await pfolio.bind(token2.address, bindSize);
  await pfolio.bind(token3.address, bindSize);
  console.log("Assets bound");

  // set oracle prices
  console.log("Setting oracle price to 1/1/1...");
  const priceOne = Math.pow(10, 18);
  const oraclePrice1_1 = (priceOne).toString();
  await pfolio.setOraclePrice(token1.address, token2.address, oraclePrice1_1);
  await pfolio.setOraclePrice(token2.address, token1.address, oraclePrice1_1);
  await pfolio.setOraclePrice(token1.address, token3.address, oraclePrice1_1);
  await pfolio.setOraclePrice(token3.address, token1.address, oraclePrice1_1);
  await pfolio.setOraclePrice(token2.address, token3.address, oraclePrice1_1);
  await pfolio.setOraclePrice(token3.address, token2.address, oraclePrice1_1);

  // call query functions
  const tradeOne = Math.pow(10, 11);
  const query1_1 = await pfolio.queryBuyBaseToken(token1.address, token2.address, 5*tradeOne).then(tstr);
  console.log("Buy  gold: 5 for silver:", query1_1/tradeOne);
  const query1_2 = await pfolio.queryBuyBaseToken(token2.address, token1.address, 5*tradeOne).then(tstr);
  console.log("Sell gold: 5 for silver:", query1_2/tradeOne);
  const query1_3 = await pfolio.queryBuyBaseToken(token1.address, token3.address, 5*tradeOne).then(tstr);
  console.log("Buy  gold: 5 for bronze:", query1_3/tradeOne);
  const query1_4 = await pfolio.queryBuyBaseToken(token3.address, token1.address, 5*tradeOne).then(tstr);
  console.log("Sell gold: 5 for bronze:", query1_4/tradeOne);

  // set oracle prices
  console.log("Setting oracle price to 1/10/100...");
  const oraclePrice2_1 = (priceOne*10).toString();
  await pfolio.setOraclePrice(token1.address, token2.address, oraclePrice2_1);
  const oraclePrice2_2 = (priceOne/10).toString();
  await pfolio.setOraclePrice(token2.address, token1.address, oraclePrice2_2);

  const oraclePrice2_3 = (priceOne*100).toString();
  await pfolio.setOraclePrice(token1.address, token3.address, oraclePrice2_3);
  const oraclePrice2_4 = (priceOne/100).toString();
  await pfolio.setOraclePrice(token3.address, token1.address, oraclePrice2_4);

  const oraclePrice2_5 = (priceOne*10).toString();
  await pfolio.setOraclePrice(token2.address, token3.address, oraclePrice2_5);
  const oraclePrice2_6 = (priceOne/10).toString();
  await pfolio.setOraclePrice(token3.address, token2.address, oraclePrice2_6);

  // call query functions
  const query2_1 = await pfolio.queryBuyBaseToken(token1.address, token2.address, 5*tradeOne).then(tstr);
  console.log("Buy  gold: 5 for silver:", query2_1/tradeOne);
  const query2_2 = await pfolio.queryBuyBaseToken(token1.address, token3.address, 5*tradeOne).then(tstr);
  console.log("Buy  gold: 5 for bronze:", query2_2/tradeOne);

  // const query2_3 = await pfolio.queryBuyBaseToken(token2.address, token1.address, 5*tradeOne).then(tstr);
  const query2_3 = await pfolio.querySellBaseToken(token1.address, token2.address, 5*tradeOne).then(tstr);
  console.log("Sell gold: 5 for silver:", query2_3/tradeOne);
  // const query2_4 = await pfolio.queryBuyBaseToken(token3.address, token1.address, 5*tradeOne).then(tstr);
  const query2_4 = await pfolio.querySellBaseToken(token1.address, token3.address, 5*tradeOne).then(tstr);
  console.log("Sell gold: 5 for bronze:", query2_4/tradeOne);

  // trade
  // const trade1 = await pfolio.sellBaseToken(token1.address, token2.address, 1*tradeOne, 1).then(tstr);
  // const trade1 = await pfolio.buyBaseToken(token1.address, token2.address, 1*tradeOne, 1*tradeOne).then(tstr);
  // console.log("Trade gold: 1 for silver:", trade1/tradeOne);
  // console.log("Gold:  ", await pfolio.getBalance(token1.address).then(tstr));
  // console.log("Silver:", await pfolio.getBalance(token2.address).then(tstr));

  // call query functions
  // const query3_1 = await pfolio.queryBuyBaseToken(token1.address, token2.address, 5*priceOne).then(tstr);
  // console.log("Buy  token1: 5 for token2:", query3_1);
  // const query3_2 = await pfolio.queryBuyBaseToken(token2.address, token1.address, 5*priceOne).then(tstr);
  // console.log("Sell token1: 5 for token2:", query3_2);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
