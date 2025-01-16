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
    function mint(address to, uint256 amount) external; // Add this line
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract Bonding {
    address public owner;
    address public weth; // WETH contract address
    address public mlAMPL; // mlAMPL contract address

    uint256 public discountRate;
    uint256 public targetPrice;

    event BondPurchased(address indexed user, uint256 wethAmount, uint256 mlAMPLAmount);
    event Debug(string message, uint256 value);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event Withdrawn(address indexed token, address indexed recipient, uint256 amount);

    constructor(address _weth, address _mlAMPL, uint256 _discountRate, uint256 _targetPrice) {
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

    function bond(uint256 wethAmount) external {
        require(wethAmount > 0, "Must deposit WETH");

        // Ensure allowance is sufficient
        uint256 allowance = IWETH(weth).allowance(msg.sender, address(this));
        require(allowance >= wethAmount, "Allowance not sufficient");

        // Transfer WETH from the user to this contract
        IWETH(weth).transferFrom(msg.sender, address(this), wethAmount);

        // Calculate the discounted mlAMPL amount
        uint256 discountedPrice = (targetPrice * (100 - discountRate)) / 100;
        uint256 mlAMPLAmount = (wethAmount * 1e18) / discountedPrice;

        // Ensure sufficient mlAMPL in the contract
        uint256 currentBalance = IMLAMPL(mlAMPL).balanceOf(address(this));
        if (currentBalance < mlAMPLAmount) {
            uint256 mintAmount = mlAMPLAmount - currentBalance;

            // If total supply is zero, initialize supply
            uint256 totalSupply = IMLAMPL(mlAMPL).totalSupply();
            if (totalSupply == 0) {
                // Initialize supply
                IMLAMPL(mlAMPL).initializeSupply(mintAmount);
                emit Debug("Initialized Supply", mintAmount);
            } else {
                // Directly mint the required amount to the contract
                IMLAMPL(mlAMPL).mint(address(this), mintAmount);
                emit Debug("Minted Tokens", mintAmount);
            }
        }

        // Transfer mlAMPL to the user
        IMLAMPL(mlAMPL).transfer(msg.sender, mlAMPLAmount);

        emit BondPurchased(msg.sender, wethAmount, mlAMPLAmount);
    }

    function withdraw(address token, uint256 amount, address recipient) external onlyOwner {
        require(recipient != address(0), "Invalid recipient address");
        require(amount > 0, "Amount must be greater than zero");

        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance >= amount, "Insufficient balance");

        IERC20(token).transfer(recipient, amount);
        emit Withdrawn(token, recipient, amount);
    }

    // Debug functions
    function checkWETHAllowance(address user) external view returns (uint256) {
        return IWETH(weth).allowance(user, address(this));
    }

    function checkWETHBalance(address user) external view returns (uint256) {
        return IWETH(weth).balanceOf(user);
    }

    function checkMLAMPLBalance(address user) external view returns (uint256) {
        return IMLAMPL(mlAMPL).balanceOf(user);
    }

    function checkContractMLAMPLBalance() external view returns (uint256) {
        return IMLAMPL(mlAMPL).balanceOf(address(this));
    }
}
