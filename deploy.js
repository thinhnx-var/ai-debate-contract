const { ethers } = require("hardhat");

async function main() {
  try {
    // const [deployer] = await ethers.getSigners();
    const ownerHardCode = process.env.OWNER;
    const AIDebateContract = await ethers.getContractFactory("AIDebate");
    const aidsc = await AIDebateContract.deploy(ownerHardCode);
    await aidsc.waitForDeployment();

    console.log("AIDebate deployed to:", aidsc.target);
  } catch (error) {
    console.error("Error deploying contract:", error);
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });