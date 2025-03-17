// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract GenBit is ERC20, Ownable(msg.sender), ReentrancyGuard {
    uint256 public constant TOTAL_SUPPLY = 21_000_000 * 10**18;
    uint256 public constant MIN_PRICE_FLOOR = 1 ether; // ₹1 minimum price floor
    uint256 public minTax = 1; // Minimum 1% tax
    uint256 public maxTax = 4; // Maximum 4% tax
    uint256 public burnTax = 5; // 5% of buy/sell tax burned
    uint256 public liquidityThreshold = 20_000 ether; // USDT reserve threshold
    uint256 public reserveUSDT = 100_000 ether; // Initial reserve
    uint256 public liquidityInjectionAmount = 10_000 * 10**18;
    uint256 public adoptionProgress; // Tracks adoption, reduces tax over time

    struct Order {
        address user;
        uint256 amount;
        uint256 price;
    }

    Order[] public buyOrders;
    Order[] public sellOrders;

    event BuyOrderPlaced(address indexed buyer, uint256 amount, uint256 price);
    event SellOrderPlaced(address indexed seller, uint256 amount, uint256 price);
    event TokensBurned(uint256 amount);
    event LiquidityInjected(uint256 amount);
    event GovernanceVote(address indexed voter, string proposal, bool vote);
    event TaxAdjusted(uint256 newTaxRate);
    event PartialSell(address indexed seller, address indexed buyer, uint256 soldAmount, uint256 receivedAmount);
    event FullSell(address indexed seller, address indexed buyer, uint256 amount);
    event DebugOrderMatched(
        address indexed seller,
        address indexed buyer,
        uint256 tradeAmount,
        uint256 taxAmount,
        uint256 burnAmount,
        uint256 buyerReceived,
        uint256 taxRate
    );

    constructor() ERC20("GenBit", "GBT") {
        _mint(msg.sender, TOTAL_SUPPLY / 2); // Mint 10.5M tokens to owner
        _mint(address(this), TOTAL_SUPPLY / 2); // Mint 10.5M tokens to contract for liquidity
    }

    function getTaxRate() public view returns (uint256) {
        uint256 adoptionFactor = adoptionProgress / 1_000_000; // Example scaling
        uint256 adjustedTax = maxTax > adoptionFactor ? maxTax - adoptionFactor : minTax;
        return adjustedTax;
    }

    function placeBuyOrder(uint256 amount, uint256 price) external {
        require(price >= MIN_PRICE_FLOOR, "Price too low");
        buyOrders.push(Order(msg.sender, amount, price));
        emit BuyOrderPlaced(msg.sender, amount, price);
    }

    // Updated: Seller locks full amount without applying a tax on placement.
    function placeSellOrder(uint256 amount, uint256 price) external {
        require(price >= MIN_PRICE_FLOOR, "Price too low");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        // Lock the full amount in the contract.
        _transfer(msg.sender, address(this), amount);

        // Record the sell order.
        sellOrders.push(Order(msg.sender, amount, price));
        emit SellOrderPlaced(msg.sender, amount, price);
    }

    // Updated matchOrders: Use tokens already locked in the contract.
    function matchOrders() external onlyOwner {
        while (buyOrders.length > 0 && sellOrders.length > 0) {
            Order storage buy = buyOrders[0];
            Order storage sell = sellOrders[0];

            // Only match if the sell price meets the buy price criteria.
            if (sell.price > buy.price) break;

            // Determine the trade amount (the lesser of the two orders).
            uint256 tradeAmount = buy.amount < sell.amount ? buy.amount : sell.amount;
            if (tradeAmount == 0) continue; // Skip if trade amount is zero

            // Compute tax details on the trade amount.
            uint256 taxRate = getTaxRate();
            uint256 taxAmount = (tradeAmount * taxRate) / 100;
            uint256 burnAmount = (taxAmount * burnTax) / 100;
            uint256 buyerReceived = tradeAmount - taxAmount;

            // Use locked tokens to pay the buyer.
            require(balanceOf(address(this)) >= tradeAmount, "Insufficient locked tokens");
            _transfer(address(this), buy.user, buyerReceived);
            _burn(address(this), burnAmount);

            // Adjust the sell order:
            if (tradeAmount < sell.amount) {
                // Partial fill: return remaining unsold tokens to the seller.
                uint256 unsold = sell.amount - tradeAmount;
                _transfer(address(this), sell.user, unsold);
                // Remove the sell order from the order book.
                shiftOrder(sellOrders);
            } else {
                // Fully filled.
                shiftOrder(sellOrders);
            }

            // Adjust the buy order.
            if (tradeAmount < buy.amount) {
                buy.amount = buy.amount - tradeAmount;
            } else {
                shiftOrder(buyOrders);
            }

            // Update adoption progress.
            adoptionProgress += tradeAmount;

            emit DebugOrderMatched(
                sell.user,
                buy.user,
                tradeAmount,
                taxAmount,
                burnAmount,
                buyerReceived,
                taxRate
            );
        }
    }

    function shiftOrder(Order[] storage orders) internal {
        require(orders.length > 0, "No orders to shift");
        for (uint256 i = 0; i < orders.length - 1; i++) {
            orders[i] = orders[i + 1];
        }
        orders.pop(); // Remove the last element.
    }

    function checkAndInjectLiquidity() external onlyOwner nonReentrant {
        require(reserveUSDT < liquidityThreshold, "Reserve is sufficient");

        uint256 injectionAmount = liquidityInjectionAmount + (adoptionProgress / 10_000);
        require(injectionAmount + reserveUSDT <= TOTAL_SUPPLY, "Exceeds total supply");

        _mint(address(this), injectionAmount);
        reserveUSDT += injectionAmount;

        emit LiquidityInjected(injectionAmount);
    }

    struct Vote {
        address voter;
        string proposal;
        bool vote;
    }

    Vote[] public votes;
    mapping(address => bool) public hasVoted;

    function voteOnProposal(string memory proposal, bool decision) external {
        require(balanceOf(msg.sender) >= 1000 * 10**18, "Minimum 1000 GBT required to vote");
        require(!hasVoted[msg.sender], "You have already voted");

        votes.push(Vote(msg.sender, proposal, decision));
        hasVoted[msg.sender] = true;

        emit GovernanceVote(msg.sender, proposal, decision);
    }

    function getVotes() external view returns (Vote[] memory) {
        return votes;
    }

    function adjustTaxRate(uint256 newTaxRate) external onlyOwner {
        require(newTaxRate >= minTax && newTaxRate <= maxTax, "Invalid tax rate");
        maxTax = newTaxRate;
        emit TaxAdjusted(newTaxRate);
    }

    function emergencyWithdraw(address to, uint256 amount) external onlyOwner nonReentrant {
        require(balanceOf(address(this)) >= amount, "Not enough tokens");
        _transfer(address(this), to, amount);
    }

    function setReserveUSDT(uint256 amount) external onlyOwner {
        reserveUSDT = amount;
    }
}
