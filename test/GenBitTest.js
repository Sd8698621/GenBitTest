const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
// Import parseEther and formatEther directly from ethers.
const { parseEther, formatEther } = require("ethers");

describe("GenBit Smart Contract Upgradeable", function () {
  let GenBit, genBit, owner, addr1, addr2, addr3;

  beforeEach(async function () {
    [owner, addr1, addr2, addr3] = await ethers.getSigners();
    GenBit = await ethers.getContractFactory("GenBit");
    // Deploy as an upgradeable proxy with initializer.
    genBit = await upgrades.deployProxy(GenBit, [], { initializer: "initialize" });
  });

  it("Should deploy with correct total supply", async function () {
    const totalSupply = await genBit.totalSupply();
    expect(totalSupply).to.equal(parseEther("21000000"));
  });

  it("Should handle buy & sell orders with FIFO and tax deductions", async function () {
    await genBit.transfer(addr1.address, parseEther("2000")); // Transfer 2000 tokens to addr1.
    await genBit.connect(addr1).placeSellOrder(parseEther("2000"), parseEther("1"));
    await genBit.connect(addr2).placeBuyOrder(parseEther("1000"), parseEther("1"));

    console.log("\n--- Before Order Matching ---");
    console.log("Sell Orders:", await genBit.sellOrders(0));
    console.log("Buy Orders:", await genBit.buyOrders(0));

    await genBit.matchOrders(); // Execute FIFO matching.

    console.log("\n--- After Order Matching ---");
    const sellerBalance = await genBit.balanceOf(addr1.address);
    const buyerBalance = await genBit.balanceOf(addr2.address);

    console.log("Seller Remaining GBT:", formatEther(sellerBalance));
    console.log("Buyer Received GBT:", formatEther(buyerBalance));

    const expectedSellerBalance = parseEther("1000");
    const expectedBuyerBalance = parseEther("960"); // After a 4% tax deduction.

    console.log("Expected Seller Balance:", formatEther(expectedSellerBalance));
    console.log("Expected Buyer Balance:", formatEther(expectedBuyerBalance));

    expect(sellerBalance).to.be.closeTo(expectedSellerBalance, parseEther("10"));
    expect(buyerBalance).to.be.closeTo(expectedBuyerBalance, parseEther("1"));
  });

  it("Should update adoption progress after matching orders", async function () {
    // Initially, adoption progress should be 0.
    let progress = await genBit.adoptionProgress();
    expect(progress).to.equal(0);

    // Place orders and execute matching.
    await genBit.transfer(addr1.address, parseEther("2000"));
    await genBit.connect(addr1).placeSellOrder(parseEther("2000"), parseEther("1"));
    await genBit.connect(addr2).placeBuyOrder(parseEther("1000"), parseEther("1"));
    await genBit.matchOrders();

    // After matching, adoption progress should equal the trade amount (1000 tokens).
    progress = await genBit.adoptionProgress();
    expect(progress).to.equal(parseEther("1000"));
  });

  it("Should not allow non-owner to match orders", async function () {
    await genBit.transfer(addr1.address, parseEther("2000"));
    await genBit.connect(addr1).placeSellOrder(parseEther("2000"), parseEther("1"));
    await genBit.connect(addr2).placeBuyOrder(parseEther("1000"), parseEther("1"));

    // Using a generic "reverted" check because custom errors may not yield a text message.
    await expect(genBit.connect(addr1).matchOrders()).to.be.reverted;
  });

  it("Should allow governance voting and prevent duplicate votes", async function () {
    await genBit.transfer(addr1.address, parseEther("1000"));
    // First vote from addr1.
    await genBit.connect(addr1).voteOnProposal("Reduce Tax", true);
    const vote = await genBit.votes(0);
    expect(vote.proposal).to.equal("Reduce Tax");
    expect(vote.vote).to.equal(true);

    // A duplicate vote from the same account should revert.
    await expect(genBit.connect(addr1).voteOnProposal("Increase Rewards", false))
      .to.be.reverted;
  });

  it("Should adjust tax rate", async function () {
    // Adjust the maximum tax rate to a new valid value.
    await genBit.adjustTaxRate(3); // set new maxTax to 3.
    const taxRate = await genBit.getTaxRate();
    // With adoptionProgress still zero, getTaxRate should return the new maxTax.
    expect(taxRate).to.equal(3);
  });

  it("Should allow emergency withdrawal by owner and reject non-owner", async function () {
    // Transfer tokens to addr1 and then lock them by placing a sell order.
    await genBit.transfer(addr1.address, parseEther("500"));
    await genBit.connect(addr1).placeSellOrder(parseEther("500"), parseEther("1"));
    
    // A non-owner attempting an emergency withdrawal should revert.
    await expect(
      genBit.connect(addr1).emergencyWithdraw(addr1.address, parseEther("100"))
    ).to.be.reverted;
    
    // Owner performs emergency withdrawal.
    const ownerBalanceBefore = await genBit.balanceOf(owner.address);
    await genBit.emergencyWithdraw(owner.address, parseEther("100"));
    const ownerBalanceAfter = await genBit.balanceOf(owner.address);
    
    // Convert balances to BigInt via toString conversion.
    const diff = BigInt(ownerBalanceAfter.toString()) - BigInt(ownerBalanceBefore.toString());
    expect(diff).to.equal(BigInt(parseEther("100").toString()));
  });


  it("Should allow setting the reserveUSDT manually", async function () {
    await genBit.connect(owner).setReserveUSDT(parseEther("50000"));
    const reserve = await genBit.reserveUSDT();
    expect(reserve).to.equal(parseEther("50000"));
  });

  it("Should return all governance votes", async function () {
    await genBit.transfer(addr1.address, parseEther("1000"));
    await genBit.transfer(addr2.address, parseEther("1000"));
    await genBit.connect(addr1).voteOnProposal("Proposal 1", true);
    await genBit.connect(addr2).voteOnProposal("Proposal 2", false);
    const votes = await genBit.getVotes();
    expect(votes.length).to.equal(2);
    expect(votes[0].proposal).to.equal("Proposal 1");
    expect(votes[1].proposal).to.equal("Proposal 2");
  });

  it("Should handle liquidity injections properly", async function () {
    // Simulate reserve dropping below the threshold by setting reserveUSDT to 19000.
    await genBit.connect(owner).setReserveUSDT(parseEther("19000"));

    console.log("\n--- Before Liquidity Injection ---");
    const reserveBefore = await genBit.reserveUSDT();
    console.log("Reserve USDT Before Injection:", formatEther(reserveBefore));

    await genBit.checkAndInjectLiquidity();

    console.log("\n--- After Liquidity Injection ---");
    const reserveAfter = await genBit.reserveUSDT();
    console.log("Reserve USDT After Injection:", formatEther(reserveAfter));

    // Check that the reserve increased above 20000.
    expect(reserveAfter).to.be.above(parseEther("20000"));
  });
});
