// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

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
contract Bonding is Pausable {
    address public owner;
    address public paymentToken;  // ERC20 token used to purchase RoboMoney
    address public roboMoney;     // RoboMoney token address

    uint256 public discountRate;  // e.g., 5 => 5% discount
    uint256 public targetPrice;   // e.g., 1e18 => 1 token per 1 RoboMoney in "wei" terms

    event BondPurchased(address indexed user, uint256 tokenAmount, uint256 roboMoneyAmount);
    event Debug(string message, uint256 value);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event Withdrawn(address indexed token, address indexed recipient, uint256 amount);

    /**
     * @param _paymentToken  Address of the ERC20 token used for bonding (DAI, USDC, etc.).
     * @param _roboMoney     Address of the RoboMoney token (replaces mlAMPL).
     * @param _discountRate  Discount in percent (0–100).
     * @param _targetPrice   Base price ratio for RoboMoney vs. payment token.
     */
    constructor(
        address _paymentToken,
        address _roboMoney,
        uint256 _discountRate,
        uint256 _targetPrice
    ) {
        owner = msg.sender;
        paymentToken = _paymentToken;
        roboMoney = _roboMoney;
        discountRate = _discountRate;
        targetPrice = _targetPrice;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }

    // -------------------------------------------------------------------------
    // Pausable controls (owner-only)
    // -------------------------------------------------------------------------

    /**
     * @dev Owner can pause contract functions protected by `whenNotPaused`.
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
     * @notice The main bonding function: user deposits `paymentToken`
     * to receive RoboMoney at a discount.
     * @param tokenAmount The amount of `paymentToken` the user is depositing.
     *
     * @dev Marked `whenNotPaused`. If the contract is paused, this function
     *      will revert. The owner can call `pause()`/`unpause()` as needed.
     */
    function bond(uint256 tokenAmount) external whenNotPaused {
        require(tokenAmount > 0, "Must deposit tokenAmount > 0");

        // Check allowance on payment token
        uint256 allowed = IERC20(paymentToken).allowance(msg.sender, address(this));
        require(allowed >= tokenAmount, "Allowance not sufficient");

        // Transfer paymentToken from the user to this contract
        bool success = IERC20(paymentToken).transferFrom(msg.sender, address(this), tokenAmount);
        require(success, "Payment token transfer failed");

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
                emit Debug("Initialized Supply", mintAmount);
            } else {
                // Otherwise, mint directly to this contract
                IRoboMoney(roboMoney).mint(address(this), mintAmount);
                emit Debug("Minted Tokens", mintAmount);
            }
        }

        // Transfer the RoboMoney to the user
        IRoboMoney(roboMoney).transfer(msg.sender, roboMoneyAmount);

        emit BondPurchased(msg.sender, tokenAmount, roboMoneyAmount);
    }

    // -------------------------------------------------------------------------
    // Owner Withdrawal
    // -------------------------------------------------------------------------

    /**
     * @dev Owner can withdraw any ERC20 tokens (e.g. leftover paymentToken or minted RoboMoney).
     * @param token     Address of the ERC20 token to withdraw.
     * @param amount    Amount to withdraw.
     * @param recipient Recipient address to receive the tokens.
     *
     * @dev Not protected by `whenNotPaused`, since an owner might need 
     *      to withdraw tokens even if contract is paused for bonding.
     */
    function withdraw(address token, uint256 amount, address recipient) external onlyOwner {
        require(recipient != address(0), "Invalid recipient address");
        require(amount > 0, "Amount must be greater than zero");

        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance >= amount, "Insufficient balance");

        IERC20(token).transfer(recipient, amount);
        emit Withdrawn(token, recipient, amount);
    }

    // -------------------------------------------------------------------------
    // Ownership
    // -------------------------------------------------------------------------

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner cannot be zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
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
}
