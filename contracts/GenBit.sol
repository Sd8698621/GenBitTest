// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol"; 
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol"; 
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract GenBit is ERC20Upgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    // *************************************************************
    // ** Tokenomics & Global Parameters **
    // *************************************************************
    // Constants (allowed to be inline since they never change)
    uint256 public constant TOTAL_SUPPLY_GLOBAL = 21_000_000 * 10**18;
    uint256 public constant MIN_PRICE_FLOOR = 1 ether; // Token notional minimum price floor

    // Tax settings (set in initializer)
    uint256 public minTax; // Minimum 1% tax
    uint256 public maxTax; // Maximum 4% tax
    uint256 public burnTax; // Percentage of the tax that is burned

    // Liquidity settings (set in initializer)
    uint256 public liquidityThreshold; // USDT reserve threshold
    uint256 public reserveUSDT;        // Initial USDT reserve value
    uint256 public liquidityInjectionAmount;

    // Adoption progress: used to reduce tax as network usage grows.
    uint256 public adoptionProgress;

    // *************************************************************
    // ** Order Structures & Order Books **
    // *************************************************************
    struct Order {
        address user;
        uint256 amount;
        uint256 price;
    }
    Order[] public buyOrders;
    Order[] public sellOrders;

    // *************************************************************
    // ** Governance Structures **
    // *************************************************************
    struct Vote {
        address voter;
        string proposal;
        bool vote;
    }
    Vote[] public votes;
    mapping(address => bool) public hasVoted;

    // *************************************************************
    // ** Events **
    // *************************************************************
    event BuyOrderPlaced(address indexed buyer, uint256 amount, uint256 price);
    event SellOrderPlaced(address indexed seller, uint256 amount, uint256 price);
    event TokensBurned(uint256 amount);
    event LiquidityInjected(uint256 amount);
    event GovernanceVote(address indexed voter, string proposal, bool vote);
    event TaxAdjusted(uint256 newTaxRate);
    event DebugOrderMatched(
        address indexed seller,
        address indexed buyer,
        uint256 tradeAmount,
        uint256 taxAmount,
        uint256 burnAmount,
        uint256 buyerReceived,
        uint256 taxRate
    );

    // *************************************************************
    // ** Initializer (replaces constructor) **
    // *************************************************************
    function initialize() public initializer {
        __ERC20_init("GenBit", "GBT");
        __Ownable_init(msg.sender);  // Set msg.sender as the initial owner
        __ReentrancyGuard_init();

        // Mint: 50% to the deployer (owner) and 50% to the contract (for liquidity functions)
        _mint(msg.sender, TOTAL_SUPPLY_GLOBAL / 2);
        _mint(address(this), TOTAL_SUPPLY_GLOBAL / 2);

        // Set tax parameters.
        minTax = 1; // 1%
        maxTax = 4; // 4%
        burnTax = 5; // 5% of the collected tax is burned

        // Set liquidity parameters.
        liquidityThreshold = 20_000 ether;
        reserveUSDT = 100_000 ether;
        liquidityInjectionAmount = 10_000 * 10**18;
    }

    // *************************************************************
    // ** Utility Functions **
    // *************************************************************
    /// @notice Returns the current tax rate based on adoption progress.
    function getTaxRate() public view returns (uint256) {
        // Example: for every 1,000,000 tokens traded, reduce the tax by 1%
        uint256 adoptionFactor = adoptionProgress / 1_000_000;
        uint256 adjustedTax = (maxTax > adoptionFactor) ? maxTax - adoptionFactor : minTax;
        return adjustedTax;
    }

    // *************************************************************
    // ** Order Book Functions **
    // *************************************************************
    /// @notice Places a buy order.
    function placeBuyOrder(uint256 amount, uint256 price) external {
        require(price >= MIN_PRICE_FLOOR, "Price too low");
        buyOrders.push(Order(msg.sender, amount, price));
        emit BuyOrderPlaced(msg.sender, amount, price);
    }

    /// @notice Places a sell order by locking tokens in the contract.
    function placeSellOrder(uint256 amount, uint256 price) external {
        require(price >= MIN_PRICE_FLOOR, "Price too low");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        _transfer(msg.sender, address(this), amount); // Lock tokens
        sellOrders.push(Order(msg.sender, amount, price));
        emit SellOrderPlaced(msg.sender, amount, price);
    }

    /// @notice Matches queued buy and sell orders in a FIFO manner.
    function matchOrders() external onlyOwner {
        while (buyOrders.length > 0 && sellOrders.length > 0) {
            Order storage buy = buyOrders[0];
            Order storage sell = sellOrders[0];

            // Only match orders if sell price meets the buyer's offer.
            if (sell.price > buy.price) break;

            // Determine trade amount (the lesser of the two order amounts).
            uint256 tradeAmount = (buy.amount < sell.amount) ? buy.amount : sell.amount;
            if (tradeAmount == 0) {
                if (buy.amount == 0) shiftOrder(buyOrders);
                if (sell.amount == 0) shiftOrder(sellOrders);
                continue;
            }

            uint256 taxRate = getTaxRate();
            uint256 taxAmount = (tradeAmount * taxRate) / 100;
            uint256 burnAmount = (taxAmount * burnTax) / 100;
            uint256 buyerReceived = tradeAmount - taxAmount;

            require(balanceOf(address(this)) >= tradeAmount, "Insufficient locked tokens");
            _transfer(address(this), buy.user, buyerReceived);
            _burn(address(this), burnAmount);
            emit TokensBurned(burnAmount);

            // Adjust sell order.
            if (tradeAmount < sell.amount) {
                uint256 unsold = sell.amount - tradeAmount;
                _transfer(address(this), sell.user, unsold);
                shiftOrder(sellOrders);
            } else {
                shiftOrder(sellOrders);
            }

            // Adjust buy order.
            if (tradeAmount < buy.amount) {
                buy.amount -= tradeAmount;
            } else {
                shiftOrder(buyOrders);
            }

            // Increase adoption progress.
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

    /// @notice Internal helper to remove the first order in an array.
    function shiftOrder(Order[] storage orders) internal {
        require(orders.length > 0, "No orders to shift");
        for (uint256 i = 0; i < orders.length - 1; i++) {
            orders[i] = orders[i + 1];
        }
        orders.pop();
    }

    // *************************************************************
    // ** Liquidity Functions **
    // *************************************************************
    /// @notice Checks if the reserve is below threshold and, if so, injects liquidity.
    function checkAndInjectLiquidity() external onlyOwner nonReentrant {
        require(reserveUSDT < liquidityThreshold, "Reserve is sufficient");
        uint256 injectionAmount = liquidityInjectionAmount + (adoptionProgress / 10_000);
        require(injectionAmount + reserveUSDT <= TOTAL_SUPPLY_GLOBAL, "Exceeds total supply");
        _mint(address(this), injectionAmount);
        reserveUSDT += injectionAmount;
        emit LiquidityInjected(injectionAmount);
    }

    // *************************************************************
    // ** Governance Functions **
    // *************************************************************
    /// @notice Allows eligible token holders (minimum 1000 GBT) to vote on proposals.
    function voteOnProposal(string memory proposal, bool decision) external {
        require(balanceOf(msg.sender) >= 1000 * 10**18, "Minimum 1000 GBT required to vote");
        require(!hasVoted[msg.sender], "You have already voted");
        votes.push(Vote(msg.sender, proposal, decision));
        hasVoted[msg.sender] = true;
        emit GovernanceVote(msg.sender, proposal, decision);
    }

    /// @notice Returns all governance votes.
    function getVotes() external view returns (Vote[] memory) {
        return votes;
    }

    /// @notice Allows the owner to adjust the maximum tax rate.
    function adjustTaxRate(uint256 newTaxRate) external onlyOwner {
        require(newTaxRate >= minTax && newTaxRate <= maxTax, "Invalid tax rate");
        maxTax = newTaxRate;
        emit TaxAdjusted(newTaxRate);
    }

    // *************************************************************
    // ** Emergency & Administrative Functions **
    // *************************************************************
    /// @notice Allows the owner to withdraw tokens from the contract in emergencies.
    function emergencyWithdraw(address to, uint256 amount) external onlyOwner nonReentrant {
        require(balanceOf(address(this)) >= amount, "Not enough tokens");
        _transfer(address(this), to, amount);
    }

    /// @notice Allows the owner to manually set the USDT reserve.
    function setReserveUSDT(uint256 amount) external onlyOwner {
        reserveUSDT = amount;
    }
}
