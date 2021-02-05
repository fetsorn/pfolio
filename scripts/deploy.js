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

  // We get the contract to deploy
  const Greeter = await hre.ethers.getContractFactory("Greeter");
  const greeter = await Greeter.deploy("Hello, fetsorn!");

  await greeter.deployed();

  // console.log("Greeter deployed to:", greeter.address);

  const s = await greeter.greet()
  console.log(s)
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

  const Preset = await hre.ethers.getContractFactory("ERC20PresetMinterPauser");
  const token1 = await Preset.deploy("fetsorns", "FTS");
  console.log("token1 deployed to:", token1.address)
  const token2 = await Preset.deploy("konfetas", "KFT");
  console.log("token2 deployed to:", token2.address)
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

  //aprrove presets for pool
  console.log("Approving presets...");

  await token1.approve(pfolio.address, fundSize);
  await token2.approve(pfolio.address, fundSize);
  console.log("Assets approved");

  // bind presets
  console.log("Binding presets...");

  const bindSize = (Math.pow(10, 12)).toString();

  const ONE = Math.pow(10, 18);
  const weight = (25 * ONE).toString();
  await pfolio.bind(token1.address, bindSize, weight);
  const balance1 = await pfolio.getBalance(token1.address).then(tstr);
  await pfolio.bind(token2.address, bindSize, weight);
  console.log("Assets bound", balance1);

  // set oracle prices
  console.log("Setting oracle price to 1/1...");
  const priceOne = Math.pow(10, 9)
  const oraclePrice1_1 = (priceOne).toString();
  await pfolio.setOraclePrice(token1.address, token2.address, oraclePrice1_1);
  const oraclePrice1_2 = (priceOne).toString();
  await pfolio.setOraclePrice(token2.address, token1.address, oraclePrice1_2);

  // console.log("token1 to token2 is", oraclePrice1_1/priceOne);
  // call query functions

  const query1_1 = await pfolio.queryBuyBaseToken(token1.address, token2.address, 5*priceOne).then(tstr);
  console.log("Buy  token1: 5 for token2:", query1_1);

  const query1_2 = await pfolio.queryBuyBaseToken(token2.address, token1.address, 5*priceOne).then(tstr);
  console.log("Sell token1: 5 for token2:", query1_2);

  // set oracle prices
  console.log("Setting oracle price to 1/10...");
  const oraclePrice2_1 = (priceOne*10).toString();
  await pfolio.setOraclePrice(token1.address, token2.address, oraclePrice2_1);
  const oraclePrice2_2 = (priceOne/10).toString();
  await pfolio.setOraclePrice(token2.address, token1.address, oraclePrice2_2);

  // console.log("token1 to token2 is", oraclePrice2_1/priceOne);

  // call query functions
  const query2_1 = await pfolio.queryBuyBaseToken(token1.address, token2.address, 5*priceOne).then(tstr);
  console.log("Buy  token1: 5 for token2:", query2_1);
  const query2_2 = await pfolio.queryBuyBaseToken(token2.address, token1.address, 5*priceOne).then(tstr);
  console.log("Sell token1: 5 for token2:", query2_2);

  // trade
  const trade1 = await pfolio.sellBaseToken(token1.address, token2.address, 1*priceOne, 1).then((n) => n.value.toString());
  console.log("Trade token1: 1*10**5 for token2:", trade1);
  console.log(await pfolio.getBalance(token1.address).then(tstr));
  console.log(await pfolio.getBalance(token2.address).then(tstr));

  // call query functions
  const query3_1 = await pfolio.queryBuyBaseToken(token1.address, token2.address, 5*priceOne).then(tstr);
  console.log("Buy  token1: 5 for token2:", query3_1);
  const query3_2 = await pfolio.queryBuyBaseToken(token2.address, token1.address, 5*priceOne).then(tstr);
  console.log("Sell token1: 5 for token2:", query3_2);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
