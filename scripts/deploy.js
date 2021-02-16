const hre = require("hardhat");

async function main() {

  const ten = ethers.BigNumber.from("10");
  const ONE = ten.pow(18);
  const PERCENT = ONE.div(100);

  const tradeSize = ten.pow(18);

  const baseSize = tradeSize.mul(tradeSize);
  const quotSize = tradeSize.mul(tradeSize);

  const reserveSize1 = baseSize;
  const reserveSize2 = quotSize;
  const reserveSize3 = quotSize;

  const fundSize1 = reserveSize1.add(tradeSize.mul(100));
  const fundSize2 = reserveSize2.add(tradeSize.mul(100));
  const fundSize3 = reserveSize3.add(tradeSize.mul(100));

  const min = PERCENT.mul(1).div(10000);
  const max = PERCENT.mul(100).mul(10000);

  // get default account
  const account = await ethers.getSigners().then((as) => as[0].address);

  const PFOLIO = await hre.ethers.getContractFactory("PFOLIO");
  const pfolio = await PFOLIO.deploy(); await pfolio.deployed();

  console.log("PFOLIO deployed to:", pfolio.address)

  const Token = await hre.ethers.getContractFactory("ERC20PresetMinterPauser");
  const token1 = await Token.deploy("gold", "AU");   await token1.deployed();
  const token2 = await Token.deploy("silver", "AG"); await token2.deployed();
  const token3 = await Token.deploy("bronze", "BZ"); await token3.deployed();
  console.log("token1 deployed to:", token1.address)
  console.log("token2 deployed to:", token2.address)
  console.log("token3 deployed to:", token3.address)

  await token1.mint(account, fundSize1);
  await token2.mint(account, fundSize2);
  await token3.mint(account, fundSize3);

  await token1.approve(pfolio.address, fundSize1);
  await token2.approve(pfolio.address, fundSize2);
  await token3.approve(pfolio.address, fundSize3);

  await pfolio.bind(token1.address, reserveSize1, min, max);
  await pfolio.bind(token2.address, reserveSize2, min, max);
  await pfolio.bind(token3.address, reserveSize3, min, max);

  priceOne = ten.pow(18);
  const price = priceOne.mul(1);

  await pfolio.setOraclePrice(token1.address, price);
  await pfolio.setOraclePrice(token2.address, price);
  await pfolio.setOraclePrice(token3.address, price);

}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
