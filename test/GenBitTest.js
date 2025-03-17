const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("GenBit Smart Contract", function () {
    let GenBit, genBit, owner, addr1, addr2;

    beforeEach(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();
        GenBit = await ethers.getContractFactory("GenBit");
        genBit = await GenBit.deploy();
    });

    it("Should deploy with correct total supply", async function () {
        const totalSupply = await genBit.totalSupply();
        expect(totalSupply).to.equal(ethers.parseEther("21000000"));
    });

    it("Should handle buy & sell orders with FIFO and tax deductions", async function () {
        await genBit.transfer(addr1.address, ethers.parseEther("2000")); // Seller gets 2000 GBT
        await genBit.connect(addr1).placeSellOrder(ethers.parseEther("2000"), ethers.parseEther("1"));
        await genBit.connect(addr2).placeBuyOrder(ethers.parseEther("1000"), ethers.parseEther("1"));
    
        console.log("\n--- Before Order Matching ---");
        console.log("Sell Orders:", await genBit.sellOrders(0));
        console.log("Buy Orders:", await genBit.buyOrders(0));
    
        await genBit.matchOrders(); // Execute FIFO matching
    
        console.log("\n--- After Order Matching ---");
        const sellerBalance = await genBit.balanceOf(addr1.address);
        const buyerBalance = await genBit.balanceOf(addr2.address);
    
        console.log("Seller Remaining GBT:", ethers.formatEther(sellerBalance));
        console.log("Buyer Received GBT:", ethers.formatEther(buyerBalance));
    
        const expectedSellerBalance = ethers.parseEther("1000"); // Updated value
        const expectedBuyerBalance = ethers.parseEther("960"); // After 4% tax deduction
    
        console.log("Expected Seller Balance:", ethers.formatEther(expectedSellerBalance));
        console.log("Expected Buyer Balance:", ethers.formatEther(expectedBuyerBalance));
    
        expect(sellerBalance).to.be.closeTo(expectedSellerBalance, ethers.parseEther("10"));
        expect(buyerBalance).to.be.closeTo(expectedBuyerBalance, ethers.parseEther("1"));
    });    
    it("Should allow governance voting", async function () {
        await genBit.transfer(addr1.address, ethers.parseEther("1000"));
        await genBit.connect(addr1).voteOnProposal("Reduce Tax", true);

        const vote = await genBit.votes(0);
        expect(vote.proposal).to.equal("Reduce Tax");
        expect(vote.vote).to.equal(true);
    });

    it("Should handle liquidity injections", async function () {
        // Simulate reserve dropping below the threshold
        await genBit.connect(owner).setReserveUSDT(ethers.parseEther("19000")); // Simulate low reserve

        console.log("\n--- Before Liquidity Injection ---");
        const reserveBefore = await genBit.reserveUSDT();
        console.log("Reserve USDT Before Injection:", ethers.formatEther(reserveBefore));

        await genBit.checkAndInjectLiquidity(); // Inject liquidity

        console.log("\n--- After Liquidity Injection ---");
        const reserveAfter = await genBit.reserveUSDT();
        console.log("Reserve USDT After Injection:", ethers.formatEther(reserveAfter));

        // Verify the reserve is above the minimum threshold
        expect(reserveAfter).to.be.above(ethers.parseEther("20000"));
    });
});
