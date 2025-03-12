// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";  // Import OpenZeppelin's IERC20

using SafeERC20 for IERC20;

/**
 * @dev Import the OpenZeppelin Pausable contract.
 * Make sure your import path matches your OpenZeppelin version.
 */
// import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @dev For demonstration, here is a minimal Pausable definition inlined.
 * In a real project, just import from OpenZeppelin as shown above.
 */
abstract contract Pausable {
    bool private _paused;

    event Paused(address account);
    event Unpaused(address account);

    constructor() {
        _paused = false;
    }

    function paused() public view virtual returns (bool) {
        return _paused;
    }

    modifier whenNotPaused() {
        require(!paused(), "Pausable: paused");
        _;
    }

    modifier whenPaused() {
        require(paused(), "Pausable: not paused");
        _;
    }

    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);
    }

    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }
}

/**
 * @dev Generic ERC20 interface
 */
// interface IERC20 {
//     function approve(address spender, uint256 amount) external returns (bool);
//     function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
//     function transfer(address recipient, uint256 amount) external returns (bool);
//     function balanceOf(address account) external view returns (uint256);
//     function allowance(address owner, address spender) external view returns (uint256);
// }

/**
 * @dev RoboMoney (or RoboMoneyAlpha) interface
 */
interface IRoboMoney {
    function initializeSupply(uint256 amount) external;
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

/**
 * @title BuyBack
 * @dev A contract that lets users sell (buy back) RoboMoney tokens for a paymentToken,
 *      and then burns the RoboMoney tokens.
 *      Now includes Pausable functionality so the owner can temporarily halt deposits or buybacks.
 */
contract BuyBack is Pausable, ReentrancyGuard {
    address public owner;
    address public paymentToken;   // ERC20 token used to buy back RoboMoney
    address public roboMoney;      // Address of the RoboMoney (or RoboMoneyAlpha) token
    address public gasReserve;

    // e.g., premiumRate = 5 => 5% premium
    // e.g., targetPrice = 1e18 => 1 RoboMoney per 1 paymentToken in Wei
    uint256 public premiumRate;    // Premium in %
    uint256 public targetPrice;    // Exchange ratio (RoboMoney -> paymentToken)
    uint256 public taxRate;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event BuyBackExecuted(address indexed buyer, uint256 roboMoneyAmount, uint256 tokenSpent);
    event GasReserveUpdated(address indexed oldGasReserve, address indexed newGasReserve);
    event TaxRateUpdated(uint256 oldTaxRate, uint256 newTaxRate);

    constructor(
        address _paymentToken,
        address _roboMoney,
        address _gasReserve,
        uint256 _premiumRate,
        uint256 _targetPrice,
        uint256 _taxRate
    ) {
        owner = msg.sender;
        paymentToken = _paymentToken;
        gasReserve = _gasReserve;
        roboMoney = _roboMoney;
        premiumRate = _premiumRate;
        targetPrice = _targetPrice;
        taxRate = _taxRate;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }

    /**
     * @dev Owner can pause the contract (disables buyback & deposit).
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Owner can unpause the contract (re-enables buyback & deposit).
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Sets the premium rate (in %). e.g., 5 => 5% premium.
     */
    function setPremiumRate(uint256 _premiumRate) external onlyOwner {
        // Typically 0-100 for a simple percentage
        require(_premiumRate <= 100, "Invalid premium rate");
        premiumRate = _premiumRate;
    }

    /**
     * @dev Sets the base price ratio for RoboMoney vs. payment token.
     */
    function setTargetPrice(uint256 _targetPrice) external onlyOwner {
        targetPrice = _targetPrice;
    }

    /**
     * @dev Owner can transfer ownership.
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner cannot be zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    /**
     * @notice Buys back RoboMoney from msg.sender at the configured premium rate,
     * paying out the specified ERC20 paymentToken, and then burns the RoboMoney.
     * @param roboMoneyAmount Amount of RoboMoney tokens to sell/buy back.
     *
     * @dev whenNotPaused ensures no buybacks are processed if contract is paused.
     */
    function buyback(uint256 roboMoneyAmount) external whenNotPaused nonReentrant {
        require(roboMoneyAmount > 0, "Must deposit RoboMoney");

        // Check allowance for RoboMoney
        uint256 allowed = IRoboMoney(roboMoney).allowance(msg.sender, address(this));
        require(allowed >= roboMoneyAmount, "Insufficient RoboMoney allowance");

        // Transfer RoboMoney from user to contract
        IERC20(roboMoney).safeTransferFrom(msg.sender, address(this), roboMoneyAmount);

        // Calculate the paymentToken amount with the premium applied
        // premiumPrice = targetPrice * (100 + premiumRate) / 100
        uint256 premiumPrice = (targetPrice * (100 + premiumRate)) / 100;
        uint256 tokenAmount = (roboMoneyAmount * premiumPrice) / 1e18;

        // Check the contract’s paymentToken balance
        uint256 currentBalance = IERC20(paymentToken).balanceOf(address(this));
        require(currentBalance >= tokenAmount, "Not enough paymentToken in contract");

        // Transfer paymentToken to the 
        uint256 taxAmount = (tokenAmount * taxRate) / 10000;
        uint256 userAmount = tokenAmount - taxAmount;

        IERC20(paymentToken).safeTransfer(gasReserve, taxAmount);
        IERC20(paymentToken).safeTransfer(msg.sender, userAmount);

        // Burn the RoboMoney tokens in the contract
        IRoboMoney(roboMoney).burn(address(this), roboMoneyAmount);

        emit BuyBackExecuted(msg.sender, roboMoneyAmount, tokenAmount);
    }

    /**
     * @dev Owner can deposit payment tokens into the contract to fund future buybacks.
     * @dev Protected by whenNotPaused so you can prevent deposits if needed.
     */
    function depositPaymentToken(uint256 amount) external onlyOwner whenNotPaused {
        require(amount > 0, "Deposit must be > 0");
        bool success = IERC20(paymentToken).transferFrom(msg.sender, address(this), amount);
        require(success, "Payment token deposit failed");
    }

    function setGasReserve(address _newGasReserve) external onlyOwner {
        require(_newGasReserve != address(0), "Invalid address");
        emit GasReserveUpdated(gasReserve, _newGasReserve);
        gasReserve = _newGasReserve;
    }

    function setTaxRate(uint256 _newTaxRate) external onlyOwner {
        require(_newTaxRate <= 1000, "Tax too high");
        emit TaxRateUpdated(taxRate, _newTaxRate);
        taxRate = _newTaxRate;
    }

    /**
     * @dev Owner can withdraw payment tokens from the contract (for leftover tokens, etc.).
     *      This is still allowed even if paused, in case you need to remove funds in an emergency.
     */
    function withdrawPaymentToken(uint256 amount) external onlyOwner {
        require(amount > 0, "Withdraw must be > 0");
        uint256 currentBalance = IERC20(paymentToken).balanceOf(address(this));
        require(amount <= currentBalance, "Not enough tokens in contract");
        bool success = IERC20(paymentToken).transfer(owner, amount);
        require(success, "Payment token withdrawal failed");
    }

    /**
     * @dev Returns the current contract balance of the payment token.
     */
    function contractTokenBalance() external view returns (uint256) {
        return IERC20(paymentToken).balanceOf(address(this));
    }

    /**
     * @dev Returns the maximum amount of RoboMoney the contract can buy back
     * given its current payment token balance and the premium rate.
     */
    function maxBuyableRoboMoney() external view returns (uint256) {
        uint256 currentBalance = IERC20(paymentToken).balanceOf(address(this));
        uint256 premiumPrice = (targetPrice * (100 + premiumRate)) / 100;

        if (premiumPrice == 0) {
            return 0;
        }
        // Convert the payment token balance into RoboMoney tokens at the premium price
        return (currentBalance * 1e18) / premiumPrice;
    }

    /**
     * @dev Checks if the contract has enough payment tokens to buy back roboMoneyAmount
     *      at the current premium rate.
     */
    function canExecuteBuyback(uint256 roboMoneyAmount) external view returns (bool) {
        uint256 premiumPrice = (targetPrice * (100 + premiumRate)) / 100;
        uint256 tokenAmount = (roboMoneyAmount * premiumPrice) / 1e18;
        uint256 currentBalance = IERC20(paymentToken).balanceOf(address(this));
        return (currentBalance >= tokenAmount);
    }
}