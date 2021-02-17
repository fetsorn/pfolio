require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-web3");
require("@eth-optimism/plugins/hardhat/compiler")
require("@eth-optimism/plugins/hardhat/ethers")

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async () => {
  const accounts = await ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

task("balance", "Prints an account's balance")
  .addParam("account", "The account's address")
  .setAction(async taskArgs => {
    const account = web3.utils.toChecksumAddress(taskArgs.account);
    const balance = await web3.eth.getBalance(account);

    console.log(web3.utils.fromWei(balance, "ether"), "ETH");
  });

task("balance1", "Prints first account's balance", async () => {
  const accounts1 = await ethers.getSigners();
  console.log(accounts1[0].address);
  const accounts2 = await web3.eth.getAccounts();
  console.log(accounts2[0]);
  web3.eth.defaultAccount = await accounts2[0];
  const account3 = await web3.eth.defaultAccount;
  console.log(account3);
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  networks: {
    localhost9: {
      url: "http://127.0.0.1:9545"
    }
  },
  solidity: {
    compilers: [
      {
        version: "0.6.9",
        settings: {
           "optimizer": {
               // disabled by default
               "enabled": true,
               // Optimize for how many times you intend to run the code.
               // Lower values will optimize more for initial deployment cost, higher
               // values will optimize more for high-frequency usage.
               "runs": 1
           } 
        }
      },
      {
        version: "0.7.0",
        settings: {
           "optimizer": {
               // disabled by default
               "enabled": true,
               // Optimize for how many times you intend to run the code.
               // Lower values will optimize more for initial deployment cost, higher
               // values will optimize more for high-frequency usage.
               "runs": 200
           } 
        }
      },
      {
        version: "0.8.1",
        settings: {
           "optimizer": {
               // disabled by default
               "enabled": true,
               // Optimize for how many times you intend to run the code.
               // Lower values will optimize more for initial deployment cost, higher
               // values will optimize more for high-frequency usage.
               "runs": 200
           } 
        }
      }
    ]
  }
};

