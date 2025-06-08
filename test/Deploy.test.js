const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Basic AIDebate Test", function () {
  let aiDebate;
  let owner, mod, user1;
  
  before(async function () {
    [owner, mod, user1] = await ethers.getSigners();
    
    const AIDebate = await ethers.getContractFactory("AIDebate");
    aiDebate = await AIDebate.deploy(owner.address, mod.address);
    await aiDebate.waitForDeployment();
  });

  it("Should deploy successfully", async function () {
    expect(await aiDebate.defaultPlatformFeePercentage()).to.equal(5);
  });
});
