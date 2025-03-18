const hre = require("hardhat");

async function main() {
  const GenBit = await hre.ethers.getContractFactory("GenBit"); // Replace "GenBit" with your contract name
  const genBit = await GenBit.deploy(); // Deploy the contract

  await genBit.waitForDeployment(); // Corrected method

  console.log(`✅ GenBit deployed at: ${await genBit.getAddress()}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
