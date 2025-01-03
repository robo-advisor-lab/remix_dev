// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IWETH {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IUniswapV2Router {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
}

contract Bonding {
    address public owner;
    address public weth; // WETH contract address
    address public mlAMPL; // mlAMPL contract address
    address public uniswapRouter; // Uniswap V2 Router address

    uint256 public discountRate = 5; // 5% discount
    uint256 public targetPrice = 1e18; // Example target price (1 mlAMPL = 1 WETH in wei)

    event BondPurchased(address indexed user, uint256 wethAmount, uint256 mlAMPLAmount);

    constructor(address _weth, address _mlAMPL, address _uniswapRouter) {
        owner = msg.sender;
        weth = _weth;
        mlAMPL = _mlAMPL;
        uniswapRouter = _uniswapRouter;
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

    function bond(uint256 wethAmount) external {
        require(wethAmount > 0, "Must deposit WETH");

        // Transfer WETH from the user to this contract
        IWETH(weth).transferFrom(msg.sender, address(this), wethAmount);

        // Calculate the discounted mlAMPL amount
        uint256 discountedPrice = (targetPrice * (100 - discountRate)) / 100;
        uint256 mlAMPLAmount = (wethAmount * 1e18) / discountedPrice;

        // Transfer discounted mlAMPL to the user
        IERC20(mlAMPL).transfer(msg.sender, mlAMPLAmount);

        // Approve Uniswap Router to spend mlAMPL and WETH
        IERC20(mlAMPL).approve(uniswapRouter, mlAMPLAmount);
        IWETH(weth).approve(uniswapRouter, wethAmount);

        // Add liquidity to Uniswap pool
        IUniswapV2Router(uniswapRouter).addLiquidity(
            weth,
            mlAMPL,
            wethAmount,
            mlAMPLAmount,
            0, // Accept any slippage
            0, // Accept any slippage
            address(this), // Send liquidity tokens to the protocol
            block.timestamp
        );

        emit BondPurchased(msg.sender, wethAmount, mlAMPLAmount);
    }
}
