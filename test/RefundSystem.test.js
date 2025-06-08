const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("AIDebate Comprehensive Refund System Tests", function () {
  let aiDebate;
  let owner, mod, user1, user2, user3, user4;
  
  beforeEach(async function () {
    // Get signers
    [owner, mod, user1, user2, user3, user4] = await ethers.getSigners();
    
    // Deploy the contract
    const AIDebate = await ethers.getContractFactory("AIDebate");
    aiDebate = await AIDebate.deploy(owner.address, mod.address);
    await aiDebate.waitForDeployment();
  });

  /**
   * ADMIN REFUND FUNCTIONALITY TESTS
   * Testing admin controls for marking debates as refundable and processing refunds
   */
  describe("Admin Refund Functionality", function () {
    let debateId = 1;
    let agentAID = 100;
    let agentBID = 200;
    let platformFeePercentage = 500; // 5%
    
    beforeEach(async function () {
      // Get current block timestamp to avoid timestamp conflicts
      const currentBlock = await ethers.provider.getBlock('latest');
      const currentTime = currentBlock.timestamp;
      const publicTimeStamp = currentTime + 3600; // 1 hour from now
      const startTimeStamp = currentTime + 7200; // 2 hours from now
      const sessionDuration = 3600; // 1 hour duration
      
      // Create a debate as mod
      await aiDebate.connect(mod).adminCreateDebate(
        debateId,
        agentAID,
        agentBID,
        platformFeePercentage,
        publicTimeStamp,
        startTimeStamp,
        sessionDuration
      );
      
      // Fast forward time to after public timestamp
      await ethers.provider.send("evm_setNextBlockTimestamp", [publicTimeStamp + 1]);
      await ethers.provider.send("evm_mine");
    });

    describe("Admin Mark Debate as Refundable", function () {
      it("Should allow admin to mark a debate as refundable", async function () {
        // Place some bets first
        await aiDebate.connect(user1).placeBet(debateId, ethers.parseEther("1"), agentAID, {
          value: ethers.parseEther("1")
        });
        
        await aiDebate.connect(user2).placeBet(debateId, ethers.parseEther("2"), agentBID, {
          value: ethers.parseEther("2")
        });
        
        // Mark debate as refundable
        await expect(aiDebate.connect(mod).adminMarkDebateRefundable(debateId))
          .to.emit(aiDebate, "DebateMarkedRefundable")
          .withArgs(debateId);
        
        // Check if debate is marked as refundable
        const isRefundable = await aiDebate.isDebateRefundable(debateId);
        expect(isRefundable).to.be.true;
      });

      it("Should not allow marking non-existent debate as refundable", async function () {
        await expect(aiDebate.connect(mod).adminMarkDebateRefundable(999))
          .to.be.revertedWith("Debate is not created yet");
      });

      it("Should not allow marking already resolved debate as refundable", async function () {
        // Place bets and resolve debate first
        await aiDebate.connect(user1).placeBet(debateId, ethers.parseEther("1"), agentAID, {
          value: ethers.parseEther("1")
        });
        
        await aiDebate.connect(mod).adminResolveDebate(debateId, agentAID);
        
        await expect(aiDebate.connect(mod).adminMarkDebateRefundable(debateId))
          .to.be.revertedWith("Debate is already resolved");
      });

      it("Should not allow marking already refundable debate as refundable again", async function () {
        await aiDebate.connect(mod).adminMarkDebateRefundable(debateId);
        
        await expect(aiDebate.connect(mod).adminMarkDebateRefundable(debateId))
          .to.be.revertedWith("Debate is already marked as refundable");
      });

      it("Should not allow non-mod to mark debate as refundable", async function () {
        await expect(aiDebate.connect(user1).adminMarkDebateRefundable(debateId))
          .to.be.revertedWith("Not allowed");
      });
    });

    describe("Admin Process Refunds", function () {
      beforeEach(async function () {
        // Place some bets
        await aiDebate.connect(user1).placeBet(debateId, ethers.parseEther("1"), agentAID, {
          value: ethers.parseEther("1")
        });
        
        await aiDebate.connect(user2).placeBet(debateId, ethers.parseEther("2"), agentBID, {
          value: ethers.parseEther("2")
        });
        
        await aiDebate.connect(user3).placeBet(debateId, ethers.parseEther("0.5"), agentAID, {
          value: ethers.parseEther("0.5")
        });
        
        // Mark debate as refundable
        await aiDebate.connect(mod).adminMarkDebateRefundable(debateId);
      });

      it("Should process refunds for all users", async function () {
        const user1BalanceBefore = await ethers.provider.getBalance(user1.address);
        const user2BalanceBefore = await ethers.provider.getBalance(user2.address);
        const user3BalanceBefore = await ethers.provider.getBalance(user3.address);
        
        // Process refunds
        await expect(aiDebate.connect(mod).adminProcessRefunds(debateId))
          .to.emit(aiDebate, "UserRefunded")
          .withArgs(debateId, user1.address, ethers.parseEther("1"))
          .to.emit(aiDebate, "UserRefunded")
          .withArgs(debateId, user2.address, ethers.parseEther("2"))
          .to.emit(aiDebate, "UserRefunded")
          .withArgs(debateId, user3.address, ethers.parseEther("0.5"));
        
        // Check balances increased
        const user1BalanceAfter = await ethers.provider.getBalance(user1.address);
        const user2BalanceAfter = await ethers.provider.getBalance(user2.address);
        const user3BalanceAfter = await ethers.provider.getBalance(user3.address);
        
        expect(user1BalanceAfter - user1BalanceBefore).to.equal(ethers.parseEther("1"));
        expect(user2BalanceAfter - user2BalanceBefore).to.equal(ethers.parseEther("2"));
        expect(user3BalanceAfter - user3BalanceBefore).to.equal(ethers.parseEther("0.5"));
        
        // Check refund status
        const [user1RefundedA, user1AmountA] = await aiDebate.getUserRefundStatus(debateId, user1.address, agentAID);
        const [user2RefundedB, user2AmountB] = await aiDebate.getUserRefundStatus(debateId, user2.address, agentBID);
        const [user3RefundedA, user3AmountA] = await aiDebate.getUserRefundStatus(debateId, user3.address, agentAID);
        
        expect(user1RefundedA).to.be.true;
        expect(user1AmountA).to.equal(ethers.parseEther("1"));
        expect(user2RefundedB).to.be.true;
        expect(user2AmountB).to.equal(ethers.parseEther("2"));
        expect(user3RefundedA).to.be.true;
        expect(user3AmountA).to.equal(ethers.parseEther("0.5"));
      });

      it("Should not process refunds for non-refundable debate", async function () {
        // Create another debate that's not marked as refundable
        const debateId2 = 2;
        const currentTime = Math.floor(Date.now() / 1000);
        await aiDebate.connect(mod).adminCreateDebate(
          debateId2,
          agentAID,
          agentBID,
          platformFeePercentage,
          currentTime + 3600,
          currentTime + 7200,
          3600
        );
        
        await expect(aiDebate.connect(mod).adminProcessRefunds(debateId2))
          .to.be.revertedWith("Debate is not marked as refundable");
      });

      it("Should not process refunds for resolved debate", async function () {
        // Resolve the debate first
        await aiDebate.connect(mod).adminResolveDebate(debateId, agentAID);
        
        await expect(aiDebate.connect(mod).adminProcessRefunds(debateId))
          .to.be.revertedWith("Cannot refund resolved debate");
      });
    });
  });

  /**
   * USER REFUND FUNCTIONALITY TESTS
   * Testing user-initiated refund claims and edge cases
   */
  describe("User Refund Functionality", function () {
    let debateId = 1;
    let agentAID = 100;
    let agentBID = 200;
    let platformFeePercentage = 500; // 5%
    
    beforeEach(async function () {
      // Get current block timestamp to avoid timestamp conflicts
      const currentBlock = await ethers.provider.getBlock('latest');
      const currentTime = currentBlock.timestamp;
      const publicTimeStamp = currentTime + 3600; // 1 hour from now
      const startTimeStamp = currentTime + 7200; // 2 hours from now
      const sessionDuration = 3600; // 1 hour duration
      
      // Create a debate as mod
      await aiDebate.connect(mod).adminCreateDebate(
        debateId,
        agentAID,
        agentBID,
        platformFeePercentage,
        publicTimeStamp,
        startTimeStamp,
        sessionDuration
      );
      
      // Fast forward time to after public timestamp
      await ethers.provider.send("evm_setNextBlockTimestamp", [publicTimeStamp + 1]);
      await ethers.provider.send("evm_mine");
      
      // Place some bets
      await aiDebate.connect(user1).placeBet(debateId, ethers.parseEther("1"), agentAID, {
        value: ethers.parseEther("1")
      });
      
      await aiDebate.connect(user2).placeBet(debateId, ethers.parseEther("2"), agentBID, {
        value: ethers.parseEther("2")
      });
      
      // User1 places bet on both agents
      await aiDebate.connect(user1).placeBet(debateId, ethers.parseEther("0.5"), agentBID, {
        value: ethers.parseEther("0.5")
      });
      
      // Mark debate as refundable
      await aiDebate.connect(mod).adminMarkDebateRefundable(debateId);
    });

    describe("User Refund Claims", function () {
      it("Should allow user to claim refund for their bets", async function () {
        const user1BalanceBefore = await ethers.provider.getBalance(user1.address);
        
        // User1 claims refund
        const tx = await aiDebate.connect(user1).userRefund(debateId);
        const receipt = await tx.wait();
        const gasUsed = receipt.gasUsed * receipt.gasPrice;
        
        const user1BalanceAfter = await ethers.provider.getBalance(user1.address);
        
        // User1 should get back 1.5 ETH (1 ETH from agentA + 0.5 ETH from agentB) minus gas
        const expectedRefund = ethers.parseEther("1.5");
        const actualRefund = user1BalanceAfter - user1BalanceBefore + gasUsed;
        
        expect(actualRefund).to.be.closeTo(expectedRefund, ethers.parseEther("0.01")); // Allow small variance for gas
      });

      it("Should emit UserRefunded events for each bet", async function () {
        await expect(aiDebate.connect(user1).userRefund(debateId))
          .to.emit(aiDebate, "UserRefunded")
          .withArgs(debateId, user1.address, ethers.parseEther("1"))
          .to.emit(aiDebate, "UserRefunded")
          .withArgs(debateId, user1.address, ethers.parseEther("0.5"));
      });

      it("Should not allow refund for non-refundable debate", async function () {
        // Create another debate that's not marked as refundable
        const debateId2 = 2;
        const currentTime = Math.floor(Date.now() / 1000);
        await aiDebate.connect(mod).adminCreateDebate(
          debateId2,
          agentAID,
          agentBID,
          platformFeePercentage,
          currentTime + 3600,
          currentTime + 7200,
          3600
        );
        
        await expect(aiDebate.connect(user1).userRefund(debateId2))
          .to.be.revertedWith("Debate is not marked as refundable");
      });

      it("Should not allow refund for resolved debate", async function () {
        // Resolve the debate
        await aiDebate.connect(mod).adminResolveDebate(debateId, agentAID);
        
        await expect(aiDebate.connect(user1).userRefund(debateId))
          .to.be.revertedWith("Cannot refund resolved debate");
      });

      it("Should not allow refund for users who didn't bet", async function () {
        // user3 didn't place any bet in this setup
        await expect(aiDebate.connect(user3).userRefund(debateId))
          .to.be.revertedWith("You did not place any bet on this debate");
      });

      it("Should not allow double refund", async function () {
        // First refund should work
        await aiDebate.connect(user1).userRefund(debateId);
        
        // Second refund should fail
        await expect(aiDebate.connect(user1).userRefund(debateId))
          .to.be.revertedWith("No eligible bets found for refund");
      });
    });

    describe("Refund Integration with Betting", function () {
      it("Should not allow new bets on refundable debate", async function () {
        // Try to place a bet on already refundable debate
        await expect(aiDebate.connect(user3).placeBet(debateId, ethers.parseEther("1"), agentAID, {
          value: ethers.parseEther("1")
        })).to.be.revertedWith("Debate is marked as refundable, no new bets allowed");
      });

      it("Should not allow claiming rewards on refundable debate", async function () {
        // Mark as refundable and resolve
        await aiDebate.connect(mod).adminResolveDebate(debateId, agentAID);
        
        // Try to claim rewards
        await expect(aiDebate.connect(user1).userClaim(debateId))
          .to.be.revertedWith("Debate is refundable, use refund instead of claim");
      });
    });

    describe("Contract Balance and Refunds", function () {
      it("Should maintain correct contract balance after refunds", async function () {
        // Create a fresh debate for this test to get a clean initial balance
        const testDebateId = 999;
        const currentBlock = await ethers.provider.getBlock('latest');
        const currentTime = currentBlock.timestamp;
        const publicTimeStamp = currentTime + 100;
        const startTimeStamp = currentTime + 200;
        
        await aiDebate.connect(mod).adminCreateDebate(
          testDebateId,
          agentAID,
          agentBID,
          platformFeePercentage,
          publicTimeStamp,
          startTimeStamp,
          3600
        );
        
        // Fast forward time
        await ethers.provider.send("evm_setNextBlockTimestamp", [publicTimeStamp + 1]);
        await ethers.provider.send("evm_mine");
        
        const initialBalance = await ethers.provider.getBalance(aiDebate.target);
        
        // Place bets
        await aiDebate.connect(user1).placeBet(testDebateId, ethers.parseEther("1"), agentAID, {
          value: ethers.parseEther("1")
        });
        
        await aiDebate.connect(user2).placeBet(testDebateId, ethers.parseEther("2"), agentBID, {
          value: ethers.parseEther("2")
        });
        
        const balanceAfterBets = await ethers.provider.getBalance(aiDebate.target);
        expect(balanceAfterBets - initialBalance).to.equal(ethers.parseEther("3"));
        
        // Mark as refundable and process refunds
        await aiDebate.connect(mod).adminMarkDebateRefundable(testDebateId);
        await aiDebate.connect(mod).adminProcessRefunds(testDebateId);
        
        const balanceAfterRefunds = await ethers.provider.getBalance(aiDebate.target);
        expect(balanceAfterRefunds).to.equal(initialBalance);
      });

      it("Should handle insufficient balance gracefully", async function () {
        // Owner withdraws all funds
        await aiDebate.connect(owner).withdrawAll();
        
        // Try to process refunds - should fail due to insufficient balance
        await expect(aiDebate.connect(mod).adminProcessRefunds(debateId))
          .to.be.revertedWith("Insufficient contract balance");
      });
    });
  });

  /**
   * REFUND QUERY FUNCTIONS TESTS
   * Testing getUserRefundableAmount and other query functions
   */
  describe("Refund Query Functions", function () {
    beforeEach(async function () {
      // Set up a debate session with future timestamps
      const currentBlock = await ethers.provider.getBlock('latest');
      const currentTime = currentBlock.timestamp;
      const publicTime = currentTime + 100;
      const startTime = currentTime + 200;
      const duration = 3600; // 1 hour
      
      await aiDebate.connect(owner).adminCreateDebate(
        1, // debateId
        101, // agentAID
        102, // agentBID
        500, // 5% platform fee
        publicTime,
        startTime,
        duration
      );
      
      // Fast forward to public time
      await ethers.provider.send("evm_setNextBlockTimestamp", [publicTime + 50]);
      await ethers.provider.send("evm_mine");
      
      // Users place bets
      await aiDebate.connect(user1).placeBet(1, ethers.parseEther("1"), 101, { value: ethers.parseEther("1") });
      await aiDebate.connect(user1).placeBet(1, ethers.parseEther("0.5"), 102, { value: ethers.parseEther("0.5") });
      await aiDebate.connect(user2).placeBet(1, ethers.parseEther("2"), 101, { value: ethers.parseEther("2") });
      await aiDebate.connect(user3).placeBet(1, ethers.parseEther("0.8"), 102, { value: ethers.parseEther("0.8") });
      await aiDebate.connect(user4).placeBet(1, ethers.parseEther("1.2"), 101, { value: ethers.parseEther("1.2") });
    });

    describe("getUserRefundableAmount", function () {
      it("Should return 0 when debate is not refundable", async function () {
        const refundableAmount = await aiDebate.getUserRefundableAmount(1, user1.address);
        expect(refundableAmount).to.equal(0);
      });

      it("Should return correct refundable amount for user when debate is refundable", async function () {
        // Mark debate as refundable
        await aiDebate.connect(owner).adminMarkDebateRefundable(1);
        
        // Check user1's refundable amount (1 + 0.5 = 1.5 ETH)
        const user1Amount = await aiDebate.getUserRefundableAmount(1, user1.address);
        expect(user1Amount).to.equal(ethers.parseEther("1.5"));
        
        // Check user2's refundable amount (2 ETH)
        const user2Amount = await aiDebate.getUserRefundableAmount(1, user2.address);
        expect(user2Amount).to.equal(ethers.parseEther("2"));
        
        // Check user3's refundable amount (0.8 ETH)
        const user3Amount = await aiDebate.getUserRefundableAmount(1, user3.address);
        expect(user3Amount).to.equal(ethers.parseEther("0.8"));
      });

      it("Should return 0 for user who hasn't bet", async function () {
        // Mark debate as refundable
        await aiDebate.connect(owner).adminMarkDebateRefundable(1);
        
        // Get additional signers to find one who hasn't bet
        const allSigners = await ethers.getSigners();
        const nonBettor = allSigners[10]; // Use a signer that definitely hasn't bet
        
        const refundableAmount = await aiDebate.getUserRefundableAmount(1, nonBettor.address);
        expect(refundableAmount).to.equal(0);
      });

      it("Should return 0 after user claims refund", async function () {
        // Mark debate as refundable
        await aiDebate.connect(owner).adminMarkDebateRefundable(1);
        
        // Check amount before refund
        const amountBefore = await aiDebate.getUserRefundableAmount(1, user1.address);
        expect(amountBefore).to.equal(ethers.parseEther("1.5"));
        
        // User1 claims refund
        await aiDebate.connect(user1).userRefund(1);
        
        // Check amount after refund
        const amountAfter = await aiDebate.getUserRefundableAmount(1, user1.address);
        expect(amountAfter).to.equal(0);
      });

      it("Should return 0 when debate is resolved", async function () {
        // Mark debate as refundable
        await aiDebate.connect(owner).adminMarkDebateRefundable(1);
        
        // Resolve the debate
        await aiDebate.connect(owner).adminResolveDebate(1, 101);
        
        // Should return 0 for all users
        const user1Amount = await aiDebate.getUserRefundableAmount(1, user1.address);
        expect(user1Amount).to.equal(0);
      });
    });
  });

  /**
   * USERS REFUND INFO FUNCTION TESTS
   * Testing the primary frontend function getUsersRefundInfo
   */
  describe("getUsersRefundInfo Function", function () {
    beforeEach(async function () {
      // Set up a debate session with future timestamps
      const currentBlock = await ethers.provider.getBlock('latest');
      const currentTime = currentBlock.timestamp;
      const publicTime = currentTime + 100;
      const startTime = currentTime + 200;
      const duration = 3600; // 1 hour
      
      await aiDebate.connect(owner).adminCreateDebate(
        1, // debateId
        101, // agentAID
        102, // agentBID
        500, // 5% platform fee
        publicTime,
        startTime,
        duration
      );
      
      // Fast forward to public time
      await ethers.provider.send("evm_setNextBlockTimestamp", [publicTime + 50]);
      await ethers.provider.send("evm_mine");
      
      // Users place bets
      await aiDebate.connect(user1).placeBet(1, ethers.parseEther("1"), 101, { value: ethers.parseEther("1") });
      await aiDebate.connect(user1).placeBet(1, ethers.parseEther("0.5"), 102, { value: ethers.parseEther("0.5") });
      await aiDebate.connect(user2).placeBet(1, ethers.parseEther("2"), 101, { value: ethers.parseEther("2") });
      await aiDebate.connect(user3).placeBet(1, ethers.parseEther("0.8"), 102, { value: ethers.parseEther("0.8") });
      await aiDebate.connect(user4).placeBet(1, ethers.parseEther("1.2"), 101, { value: ethers.parseEther("1.2") });
    });

    describe("Basic getUsersRefundInfo functionality", function () {
      it("Should return all users with correct refund amounts and refunded=false initially", async function () {
        const usersRefundInfo = await aiDebate.getUsersRefundInfo(1);
        
        // Should return 4 users
        expect(usersRefundInfo).to.have.length(4);
        
        // Check user refund info structure and values
        expect(usersRefundInfo[0].user).to.equal(user1.address);
        expect(usersRefundInfo[0].amountOfRefund).to.equal(ethers.parseEther("1.5")); // 1 + 0.5
        expect(usersRefundInfo[0].refunded).to.equal(false);
        
        expect(usersRefundInfo[1].user).to.equal(user2.address);
        expect(usersRefundInfo[1].amountOfRefund).to.equal(ethers.parseEther("2"));
        expect(usersRefundInfo[1].refunded).to.equal(false);
        
        expect(usersRefundInfo[2].user).to.equal(user3.address);
        expect(usersRefundInfo[2].amountOfRefund).to.equal(ethers.parseEther("0.8"));
        expect(usersRefundInfo[2].refunded).to.equal(false);
        
        expect(usersRefundInfo[3].user).to.equal(user4.address);
        expect(usersRefundInfo[3].amountOfRefund).to.equal(ethers.parseEther("1.2"));
        expect(usersRefundInfo[3].refunded).to.equal(false);
      });

      it("Should show refunded=true after user claims refund", async function () {
        // Mark debate as refundable
        await aiDebate.connect(owner).adminMarkDebateRefundable(1);
        
        // User1 claims refund
        await aiDebate.connect(user1).userRefund(1);
        
        const usersRefundInfo = await aiDebate.getUsersRefundInfo(1);
        
        // User1 should show refunded=true
        expect(usersRefundInfo[0].user).to.equal(user1.address);
        expect(usersRefundInfo[0].amountOfRefund).to.equal(ethers.parseEther("1.5"));
        expect(usersRefundInfo[0].refunded).to.equal(true);
        
        // Other users should still show refunded=false
        expect(usersRefundInfo[1].refunded).to.equal(false);
        expect(usersRefundInfo[2].refunded).to.equal(false);
        expect(usersRefundInfo[3].refunded).to.equal(false);
      });

      it("Should show refunded=true after admin processes refunds", async function () {
        // Mark debate as refundable
        await aiDebate.connect(owner).adminMarkDebateRefundable(1);
        
        // Admin processes all refunds
        await aiDebate.connect(owner).adminProcessRefunds(1);
        
        const usersRefundInfo = await aiDebate.getUsersRefundInfo(1);
        
        // All users should show refunded=true
        expect(usersRefundInfo[0].refunded).to.equal(true);
        expect(usersRefundInfo[1].refunded).to.equal(true);
        expect(usersRefundInfo[2].refunded).to.equal(true);
        expect(usersRefundInfo[3].refunded).to.equal(true);
        
        // Amounts should remain the same
        expect(usersRefundInfo[0].amountOfRefund).to.equal(ethers.parseEther("1.5"));
        expect(usersRefundInfo[1].amountOfRefund).to.equal(ethers.parseEther("2"));
        expect(usersRefundInfo[2].amountOfRefund).to.equal(ethers.parseEther("0.8"));
        expect(usersRefundInfo[3].amountOfRefund).to.equal(ethers.parseEther("1.2"));
      });

      it("Should show mixed refund statuses after partial refunds", async function () {
        // Mark debate as refundable
        await aiDebate.connect(owner).adminMarkDebateRefundable(1);
        
        // User1 and user3 claim refunds
        await aiDebate.connect(user1).userRefund(1);
        await aiDebate.connect(user3).userRefund(1);
        
        const usersRefundInfo = await aiDebate.getUsersRefundInfo(1);
        
        // User1 and user3 should show refunded=true
        expect(usersRefundInfo[0].refunded).to.equal(true);
        expect(usersRefundInfo[2].refunded).to.equal(true);
        
        // User2 and user4 should show refunded=false
        expect(usersRefundInfo[1].refunded).to.equal(false);
        expect(usersRefundInfo[3].refunded).to.equal(false);
      });
    });

    describe("Edge cases and special scenarios", function () {
      it("Should return empty array for non-existent debate", async function () {
        const usersRefundInfo = await aiDebate.getUsersRefundInfo(999);
        expect(usersRefundInfo).to.have.length(0);
      });

      it("Should work correctly even when debate is not refundable", async function () {
        const usersRefundInfo = await aiDebate.getUsersRefundInfo(1);
        
        // Should still return all users with their bet amounts
        expect(usersRefundInfo).to.have.length(4);
        
        // All should show refunded=false since no refunds have been processed
        for (let i = 0; i < usersRefundInfo.length; i++) {
          expect(usersRefundInfo[i].refunded).to.equal(false);
        }
      });

      it("Should work correctly after debate is resolved", async function () {
        // Resolve the debate
        await aiDebate.connect(owner).adminResolveDebate(1, 101);
        
        const usersRefundInfo = await aiDebate.getUsersRefundInfo(1);
        
        // Should still return all users with their bet amounts
        expect(usersRefundInfo).to.have.length(4);
        
        // All should show refunded=false since no refunds were processed
        for (let i = 0; i < usersRefundInfo.length; i++) {
          expect(usersRefundInfo[i].refunded).to.equal(false);
        }
      });

      it("Should handle user with only one agent bet correctly", async function () {
        // Create a new debate for this test
        const currentBlock = await ethers.provider.getBlock('latest');
        const currentTime = currentBlock.timestamp;
        const publicTime = currentTime + 100;
        const startTime = currentTime + 200;
        const duration = 3600;
        
        await aiDebate.connect(owner).adminCreateDebate(
          2, // debateId
          201, // agentAID
          202, // agentBID
          500, // 5% platform fee
          publicTime,
          startTime,
          duration
        );
        
        // Fast forward to public time
        await ethers.provider.send("evm_setNextBlockTimestamp", [publicTime + 50]);
        await ethers.provider.send("evm_mine");
        
        // User1 bets only on agent A
        await aiDebate.connect(user1).placeBet(2, ethers.parseEther("1"), 201, { value: ethers.parseEther("1") });
        
        const usersRefundInfo = await aiDebate.getUsersRefundInfo(2);
        
        expect(usersRefundInfo).to.have.length(1);
        expect(usersRefundInfo[0].user).to.equal(user1.address);
        expect(usersRefundInfo[0].amountOfRefund).to.equal(ethers.parseEther("1"));
        expect(usersRefundInfo[0].refunded).to.equal(false);
      });

      it("Should correctly identify partial refunds (user with multiple bets)", async function () {
        // This test verifies the edge case where a user has bets on both agents
        // and only one of them gets refunded somehow (though this shouldn't happen 
        // in normal flow since userRefund() refunds all bets)
        
        // Mark debate as refundable
        await aiDebate.connect(owner).adminMarkDebateRefundable(1);
        
        // Get user1's refund info before any refunds
        let usersRefundInfo = await aiDebate.getUsersRefundInfo(1);
        expect(usersRefundInfo[0].refunded).to.equal(false);
        
        // User1 claims refund (this should refund both agent A and agent B bets)
        await aiDebate.connect(user1).userRefund(1);
        
        // Check that user1 is now fully refunded
        usersRefundInfo = await aiDebate.getUsersRefundInfo(1);
        expect(usersRefundInfo[0].refunded).to.equal(true);
      });

      it("Should return consistent data structure for all users", async function () {
        const usersRefundInfo = await aiDebate.getUsersRefundInfo(1);
        
        // Verify each object has the correct structure
        for (let i = 0; i < usersRefundInfo.length; i++) {
          // Check if properties exist and have correct types
          expect(usersRefundInfo[i].user).to.be.a('string');
          expect(usersRefundInfo[i].amountOfRefund).to.be.a('bigint');
          expect(usersRefundInfo[i].refunded).to.be.a('boolean');
          
          // Additional validation
          expect(usersRefundInfo[i].user.length).to.equal(42); // Ethereum address length
          expect(usersRefundInfo[i].amountOfRefund).to.be.at.least(0n);
        }
      });
    });
  });
});
