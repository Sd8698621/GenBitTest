require('@openzeppelin/hardhat-upgrades');
require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config(); // Load environment variables

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.28",
  networks: {
    polygon_amoy: {
      url: "https://rpc-amoy.polygon.technology",
      accounts: [process.env.PRIVATE_KEY], // Securely load private key
    },
  },
};
