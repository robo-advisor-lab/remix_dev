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
    function rebase(int256 rebaseRate) external;
    function initializeSupply(uint256 amount) external;
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );
}

contract Bonding {
    address public owner;
    address public weth;
    address public mlAMPL;
    address public positionManager;
    uint24 public poolFee = 3000;

    uint256 public discountRate = 5;
    uint256 public targetPrice = 367377597059803;

    event BondPurchased(address indexed user, uint256 wethAmount, uint256 mlAMPLAmount);
    event LiquidityProvided(uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    constructor(address _weth, address _mlAMPL, address _positionManager) {
        owner = msg.sender;
        weth = _weth;
        mlAMPL = _mlAMPL;
        positionManager = _positionManager;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }

    function setTargetPrice(uint256 _targetPrice) external onlyOwner {
        targetPrice = _targetPrice;
    }

    function bond(uint256 wethAmount) external {
        require(wethAmount > 0, "Must deposit WETH");
        uint256 allowance = IWETH(weth).allowance(msg.sender, address(this));
        require(allowance >= wethAmount, "Allowance not sufficient");

        IWETH(weth).transferFrom(msg.sender, address(this), wethAmount);

        uint256 discountedPrice = (targetPrice * (100 - discountRate)) / 100;
        uint256 mlAMPLAmount = (wethAmount * 1e18) / discountedPrice;

        uint256 currentBalance = IMLAMPL(mlAMPL).balanceOf(address(this));
        if (currentBalance < mlAMPLAmount) {
            uint256 mintAmount = mlAMPLAmount - currentBalance;
            uint256 totalSupply = IMLAMPL(mlAMPL).totalSupply();

            if (totalSupply == 0) {
                IMLAMPL(mlAMPL).initializeSupply(mintAmount);
            } else {
                int256 rebaseRate = int256((mintAmount * 1e6) / totalSupply);
                IMLAMPL(mlAMPL).rebase(rebaseRate);
            }
        }

        IMLAMPL(mlAMPL).transfer(msg.sender, mlAMPLAmount);

        emit BondPurchased(msg.sender, wethAmount, mlAMPLAmount);
    }

    function provideLiquidity(uint256 amount0Desired) external onlyOwner {
        uint256 amount1Desired = (amount0Desired * 1e18) / targetPrice;

        uint256 lowerPrice = (targetPrice * 95) / 100;
        uint256 upperPrice = (targetPrice * 105) / 100;

        int24 tickLower = getTickFromPrice(lowerPrice);
        int24 tickUpper = getTickFromPrice(upperPrice);

        IERC20(weth).approve(positionManager, amount0Desired);
        IERC20(mlAMPL).approve(positionManager, amount1Desired);

        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = 
            INonfungiblePositionManager(positionManager).mint(
                INonfungiblePositionManager.MintParams({
                    token0: weth,
                    token1: mlAMPL,
                    fee: poolFee,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    amount0Desired: amount0Desired,
                    amount1Desired: amount1Desired,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: owner,
                    deadline: block.timestamp + 300
                })
            );

        emit LiquidityProvided(tokenId, liquidity, amount0, amount1);
    }

    function getTickFromPrice(uint256 price) public pure returns (int24) {
        uint256 sqrtPrice = sqrt(price);
        uint256 sqrtPriceX96 = sqrtPrice * (2**96);

        // Calculate log base 1.0001
        uint256 logResult = logBase(sqrtPriceX96, 10001, 10000);

        // Ensure the result fits into int24 range
        require(
            int256(logResult) >= type(int24).min && int256(logResult) <= type(int24).max,
            "Tick value out of range"
        );

        return int24(int256(logResult));
    }

    function logBase(uint256 value, uint256 baseNumerator, uint256 baseDenominator) internal pure returns (uint256) {
        uint256 result = 0;
        while (value >= (baseNumerator * 1e18) / baseDenominator) {
            value = (value * baseDenominator) / baseNumerator;
            result++;
        }
        return result;
    }

    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }
}
