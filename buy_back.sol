// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IWETH {
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

interface IMLAMPL {
    function initializeSupply(uint256 amount) external;
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

contract BuyBack {
    address public owner;
    address public weth; // WETH contract address
    address public mlAMPL; // mlAMPL contract address

    uint256 public discountRate; // Discount rate in percentage (e.g., 5 means 5%)
    uint256 public targetPrice; // Example target price (e.g., 1 mlAMPL = 1 WETH in wei)

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event BuyBackExecuted(address indexed buyer, uint256 mlAMPLAmount, uint256 wethSpent);

    constructor(
        address _weth,
        address _mlAMPL,
        uint256 _discountRate,
        uint256 _targetPrice
    ) {
        owner = msg.sender;
        weth = _weth;
        mlAMPL = _mlAMPL;
        discountRate = _discountRate;
        targetPrice = _targetPrice;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }

    function setDiscountRate(uint256 _discountRate) external onlyOwner {
        require(_discountRate <= 100, "Invalid discount rate");
        discountRate = _discountRate;
    }

    function setTargetPrice(uint256 _targetPrice) external onlyOwner {
        targetPrice = _targetPrice;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner cannot be zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function buyback(uint256 mlAMPLAmount) external {
        require(mlAMPLAmount > 0, "Must deposit mlAMPL");

        // Ensure allowance is sufficient
        uint256 allowance = IMLAMPL(mlAMPL).allowance(msg.sender, address(this));
        require(allowance >= mlAMPLAmount, "Allowance not sufficient");

        // Transfer mlAMPL from the user to the contract
        require(IMLAMPL(mlAMPL).transferFrom(msg.sender, address(this), mlAMPLAmount), "Transfer failed");

        // Calculate the discounted WETH amount
        uint256 discountedPrice = (targetPrice * (100 - discountRate)) / 100;
        uint256 wethAmount = (mlAMPLAmount * discountedPrice) / 1e18;

        // Ensure the contract has enough WETH to pay
        uint256 contractWethBalance = IWETH(weth).balanceOf(address(this));
        require(contractWethBalance >= wethAmount, "Not enough WETH in contract");

        // Transfer WETH to the user
        require(IWETH(weth).transfer(msg.sender, wethAmount), "WETH transfer failed");

        // Burn the mlAMPL tokens
        IMLAMPL(mlAMPL).burn(address(this), mlAMPLAmount);

        emit BuyBackExecuted(msg.sender, mlAMPLAmount, wethAmount);
    }

    function depositWETH(uint256 amount) external onlyOwner {
        // Allow the owner to deposit WETH into the contract
        require(amount > 0, "Amount must be greater than 0");
        require(IWETH(weth).transferFrom(msg.sender, address(this), amount), "WETH deposit failed");
    }

    function withdrawWETH(uint256 amount) external onlyOwner {
        // Allow the owner to withdraw WETH from the contract
        require(amount > 0, "Amount must be greater than 0");
        uint256 contractWethBalance = IWETH(weth).balanceOf(address(this));
        require(amount <= contractWethBalance, "Not enough WETH in contract");
        require(IWETH(weth).transfer(owner, amount), "WETH withdrawal failed");
    }

    function contractWETHBalance() external view returns (uint256) {
        return IWETH(weth).balanceOf(address(this));
    }

    function canExecuteBuyback(uint256 mlAMPLAmount) external view returns (bool) {
        uint256 discountedPrice = (targetPrice * (100 - discountRate)) / 100;
        uint256 wethAmount = (mlAMPLAmount * discountedPrice) / 1e18;
        uint256 contractWethBalance = IWETH(weth).balanceOf(address(this));
        return contractWethBalance >= wethAmount;
    }
}
