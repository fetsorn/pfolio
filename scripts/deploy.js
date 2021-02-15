const hre = require("hardhat");

async function main() {

  const ten = ethers.BigNumber.from("10");
  const ONE = ten.pow(18);
  const PERCENT = ONE.div(100);

  const fundSize = ten.pow(17).add(ten.pow(13));
  const bindSize = ten.pow(17).mul(1);
  const min = PERCENT.mul(30);
  const max = PERCENT.mul(70);

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

  await token1.mint(account, fundSize);
  await token2.mint(account, fundSize);
  await token3.mint(account, fundSize);

  await token1.approve(pfolio.address, fundSize);
  await token2.approve(pfolio.address, fundSize);
  await token3.approve(pfolio.address, fundSize);

  await pfolio.bind(token1.address, bindSize, min, max);
  await pfolio.bind(token2.address, bindSize, min, max);
  await pfolio.bind(token3.address, bindSize, min, max);

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
