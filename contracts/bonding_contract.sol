// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";  // Import OpenZeppelin's IERC20


using SafeERC20 for IERC20;

/**
 * @dev Import the OpenZeppelin Pausable contract.
 * Make sure your import path matches the version you're using. 
 * For example, if you're on OZ 4.x:
 */
// import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @dev For demonstration, let's define our own basic Pausable interface (if you didn't want a direct import).
 * But in a production setting, you'd import from OpenZeppelin.
 */
abstract contract Pausable {
    bool private _paused;

    event Paused(address account);
    event Unpaused(address account);

    constructor() {
        _paused = false;
    }

    modifier whenNotPaused() {
        require(!paused(), "Pausable: paused");
        _;
    }

    modifier whenPaused() {
        require(paused(), "Pausable: not paused");
        _;
    }

    function paused() public view virtual returns (bool) {
        return _paused;
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
 * @dev Generic ERC20 interface (used for the payment token).
 */
// interface IERC20 {
//     function totalSupply() external view returns (uint256);
//     function balanceOf(address account) external view returns (uint256);
//     function allowance(address owner, address spender) external view returns (uint256);

//     function approve(address spender, uint256 amount) external returns (bool);
//     function transfer(address recipient, uint256 amount) external returns (bool);
//     function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

//     event Transfer(address indexed from, address indexed to, uint256 value);
//     event Approval(address indexed owner, address indexed spender, uint256 value);
// }

/**
 * @dev RoboMoney interface (formerly mlAMPL).
 */
interface IRoboMoney {
    function initializeSupply(uint256 amount) external;
    function mint(address to, uint256 amount) external; 
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

/**
 * @title Bonding
 * @dev Demonstrates how to add pausing to the Bonding contract.
 */
contract Bonding is Pausable, ReentrancyGuard {
    address public owner;
    address public paymentToken;  // ERC20 token used to purchase RoboMoney
    address public roboMoney;     // RoboMoney token address
    address public bondReceiver;
    address public gasReserve;

    uint256 public discountRate;  // e.g., 5 => 5% discount
    uint256 public targetPrice;   // e.g., 1e18 => 1 token per 1 RoboMoney in "wei" terms
    uint256 public taxRate;

    event BondPurchased(address indexed user, uint256 tokenAmount, uint256 roboMoneyAmount);
    event GasReserveUpdated(address indexed oldGasReserve, address indexed newGasReserve);
    event TaxRateUpdated(uint256 oldTaxRate, uint256 newTaxRate);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event BondReceiverUpdated(address indexed oldBondReceiver, address indexed newBondReceiver);


    /**
     * @param _paymentToken  Address of the ERC20 token used for bonding (DAI, USDC, etc.).
     * @param _roboMoney     Address of the RoboMoney token (replaces mlAMPL).
     * @param _bondReceiver  Address of the receiver of bonded payments.
     * @param _discountRate  Discount in percent (0–100).
     * @param _targetPrice   Base price ratio for RoboMoney vs. payment token.
     */
    constructor(
        address _paymentToken,
        address _roboMoney,
        address _bondReceiver,
        address _gasReserve,
        uint256 _discountRate,
        uint256 _targetPrice,
        uint256 _taxRate
    ) {
        require(_paymentToken != address(0), "Invalid payment token address");
        require(_roboMoney != address(0), "Invalid RoboMoney token address");
        require(_bondReceiver != address(0), "Invalid bond receiver address");
        require(_gasReserve != address(0), "Invalid gas reserve address");
        require(_discountRate < 100, "Discount rate must be < 100%");
        require(_targetPrice > 0, "Target price must be > 0");
        require(_taxRate <= 1000, "Tax rate too high");
        
        owner = msg.sender;
        paymentToken = _paymentToken;
        roboMoney = _roboMoney;
        bondReceiver = _bondReceiver;
        gasReserve = _gasReserve;
        discountRate = _discountRate;
        targetPrice = _targetPrice;
        taxRate = _taxRate;
        
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }

    // -------------------------------------------------------------------------
    // Pausable controls (owner-only)
    // -------------------------------------------------------------------------

    /**
     * @dev Owner can pause contract functions protected by whenNotPaused.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Owner can unpause contract functions.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // -------------------------------------------------------------------------
    // Main Bonding Logic
    // -------------------------------------------------------------------------

    /**
     * @notice The main bonding function: user deposits paymentToken
     * to receive RoboMoney at a discount.
     * @param tokenAmount The amount of paymentToken the user is depositing.
     *
     * @dev Marked whenNotPaused. If the contract is paused, this function
     *      will revert. The owner can call pause()/unpause() as needed.
     */

    
    
    function bond(uint256 tokenAmount) external whenNotPaused nonReentrant  {
        require(tokenAmount > 0, "Must deposit tokenAmount > 0");

        uint256 taxAmount = (tokenAmount * taxRate) / 10000;
        uint256 netAmount = tokenAmount - taxAmount;

        // Check allowance on payment token
        uint256 allowed = IERC20(paymentToken).allowance(msg.sender, address(this));
        require(allowed >= tokenAmount, "Allowance not sufficient");

        // Transfer paymentToken from the user to this contract
        IERC20(paymentToken).safeTransferFrom(msg.sender, gasReserve, taxAmount);
        IERC20(paymentToken).safeTransferFrom(msg.sender, bondReceiver, netAmount);

        // Calculate discounted RoboMoney amount
        uint256 discountedPrice = (targetPrice * (100 - discountRate)) / 100;
        uint256 roboMoneyAmount = (tokenAmount * 1e18) / discountedPrice;  // base ratio

        // Check if the contract has enough RoboMoney; mint if needed
        uint256 currentBalance = IRoboMoney(roboMoney).balanceOf(address(this));
        if (currentBalance < roboMoneyAmount) {
            uint256 mintAmount = roboMoneyAmount - currentBalance;

            // If total supply is zero, initialize supply
            uint256 totalSupply = IRoboMoney(roboMoney).totalSupply();
            if (totalSupply == 0) {
                // Initialize supply
                IRoboMoney(roboMoney).initializeSupply(mintAmount);
            } else {
                // Otherwise, mint directly to this contract
                IRoboMoney(roboMoney).mint(address(this), mintAmount);
            }
        }

        // Transfer the RoboMoney to the user
        IRoboMoney(roboMoney).transfer(msg.sender, roboMoneyAmount);

        emit BondPurchased(msg.sender, tokenAmount, roboMoneyAmount);
    }

    // -------------------------------------------------------------------------
    // Owner Withdrawal
    // -------------------------------------------------------------------------

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

    // -------------------------------------------------------------------------
    // Ownership
    // -------------------------------------------------------------------------

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner cannot be zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setBondReceiver(address _newBondReceiver) external onlyOwner {
        require(_newBondReceiver != address(0), "Invalid bond receiver address");
        emit BondReceiverUpdated(bondReceiver, _newBondReceiver);
        bondReceiver = _newBondReceiver;
    }

    // -------------------------------------------------------------------------
    // View/Debug functions
    // -------------------------------------------------------------------------

    function checkTokenAllowance(address user) external view returns (uint256) {
        return IERC20(paymentToken).allowance(user, address(this));
    }

    function checkTokenBalance(address user) external view returns (uint256) {
        return IERC20(paymentToken).balanceOf(user);
    }

    function checkRoboMoneyBalance(address user) external view returns (uint256) {
        return IRoboMoney(roboMoney).balanceOf(user);
    }

    function checkContractRoboMoneyBalance() external view returns (uint256) {
        return IRoboMoney(roboMoney).balanceOf(address(this));
    }
    
    function setTargetPrice(uint256 _targetPrice) external onlyOwner {
        targetPrice = _targetPrice;
    }
}