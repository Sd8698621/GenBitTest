const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("GenBit Smart Contract", function () {
    let GenBit, genBit, owner, addr1, addr2;

    beforeEach(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();
        GenBit = await ethers.getContractFactory("GenBit");
        genBit = await GenBit.deploy(); // Deploy contract
    });

    it("Should deploy with correct total supply", async function () {
        const totalSupply = await genBit.totalSupply();
        expect(totalSupply).to.equal(ethers.parseEther("21000000"));
    });

    it("Should handle buy & sell orders with FIFO and tax deductions", async function () {
        // Transfer 2000 GBT to addr1 (Seller)
        await genBit.transfer(addr1.address, ethers.parseEther("2000"));

        // Seller places 2000 GBT sell order
        await genBit.connect(addr1).placeSellOrder(ethers.parseEther("2000"), ethers.parseEther("1"));

        // Buyer places a 1000 GBT buy order
        await genBit.connect(addr2).placeBuyOrder(ethers.parseEther("1000"), ethers.parseEther("1"));

        // Execute matching
        await genBit.matchOrders();

        // Validate partial sale execution
        const sellerBalance = await genBit.balanceOf(addr1.address);
        const buyerBalance = await genBit.balanceOf(addr2.address);
        console.log("Seller Remaining GBT:", ethers.formatEther(sellerBalance));
        console.log("Buyer Received GBT:", ethers.formatEther(buyerBalance));

        // Ensure correct tax deductions
        expect(sellerBalance).to.be.closeTo(ethers.parseEther("1000"), ethers.parseEther("5")); // ~1000 GBT left
        expect(buyerBalance).to.be.closeTo(ethers.parseEther("921.6"), ethers.parseEther("5")); // ~921.6 GBT received
    });

    it("Should allow governance voting", async function () {
        // Transfer tokens to addr1 to meet voting requirements
        await genBit.transfer(addr1.address, ethers.parseEther("1000"));

        // addr1 votes on a proposal
        await genBit.connect(addr1).voteOnProposal("Reduce Tax", true);
        
        const votes = await genBit.getVote(0);
        expect(votes.proposal).to.equal("Reduce Tax");
        expect(votes.vote).to.equal(true);
    });

    it("Should handle liquidity injections", async function () {
        // Reduce reserve to trigger liquidity injection
        await genBit.withdrawReserve(ethers.parseEther("90000"));

        // Inject liquidity
        await genBit.checkAndInjectLiquidity();
        
        const reserve = await genBit.reserveUSDT();
        console.log("New Liquidity Reserve:", ethers.formatEther(reserve));
    });
});
