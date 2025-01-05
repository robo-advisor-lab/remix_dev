// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MLAMPL is ERC20, ERC20Burnable, Ownable, ERC20Permit {
    event Rebase(int256 rebaseRate, uint256 newTotalSupply);
    event StakingRewardUpdated(uint256 rewardRate, uint256 newRewardPool);
    event RebaseRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event Stake(address indexed user, uint256 amount);
    event Unstake(address indexed user, uint256 amount);
    event ClaimRewards(address indexed user, uint256 amount);
    
    bool private initialized = false;
    address public rebaseRecipient;

    uint256 public totalStaked;
    uint256 public rewardRate;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public stakes;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    constructor(address initialOwner)
        ERC20("ML AMPL", "mlAMPL")
        ERC20Permit("ML AMPL")
        Ownable(initialOwner)
    {
        rebaseRecipient = initialOwner;
    }

    modifier onlyRebaseRecipientOrOwner() {
        require(msg.sender == owner() || msg.sender == rebaseRecipient, "Caller is not authorized");
        _;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;

        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function initializeSupply(uint256 amount) external onlyRebaseRecipientOrOwner {
        require(!initialized, "Supply already initialized");
        _mint(rebaseRecipient, amount);
        initialized = true;
        rewardPerTokenStored = 0; // Ensure no stale rewards are distributed
        lastUpdateTime = block.timestamp; // Set the initial update time
    }


    function stake(uint256 amount) external updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        require(amount <= balanceOf(msg.sender), "Insufficient balance");
        _transfer(msg.sender, address(this), amount);
        stakes[msg.sender] += amount;
        totalStaked += amount;

        emit Stake(msg.sender, amount);
    }

    function unstake(uint256 amount) external updateReward(msg.sender) {
        require(amount > 0, "Cannot unstake 0");
        require(stakes[msg.sender] >= amount, "Cannot unstake more than staked");

        stakes[msg.sender] -= amount;
        totalStaked -= amount;

        _transfer(address(this), msg.sender, amount);
        emit Unstake(msg.sender, amount);
    }

    function claimRewards() external updateReward(msg.sender) {
        updateRewardPool(); // Ensure the reward rate reflects the latest contract balance
        uint256 reward = rewards[msg.sender];
        require(reward > 0, "No rewards to claim");
        rewards[msg.sender] = 0;
        _transfer(address(this), msg.sender, reward);

        emit ClaimRewards(msg.sender, reward);
    }

    function earned(address account) public view returns (uint256) {
        return
            (stakes[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) /
            1e18 +
            rewards[account];
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }

        // Calculate additional reward per token since the last update
        uint256 timeElapsed = block.timestamp - lastUpdateTime;
        uint256 additionalRewardPerToken = (timeElapsed * rewardRate * 1e18) / totalStaked;

        return rewardPerTokenStored + additionalRewardPerToken;
    }

    function availableRewards_view() public view returns (uint256) {
        uint256 contractBalance = balanceOf(address(this));
        uint256 reservedBalance = totalStaked; // Tokens reserved for unstaking
        if (contractBalance > reservedBalance) {
            return contractBalance - reservedBalance;
        }
        return 0;
    }

    function updateRewardPool() internal {
        uint256 availableRewards = availableRewards_view();

        // Calculate the reward rate per second for one year
        rewardRate = availableRewards / 31536000;

        emit StakingRewardUpdated(rewardRate, availableRewards);
    }

    function rebase(int256 rebaseRate) external onlyOwner updateReward(address(0)) {
        require(rebaseRate != 0, "Rebase rate cannot be zero");

        uint256 currentTotalSupply = totalSupply();
        uint256 newTotalSupply;

        if (rebaseRate > 0) {
            // Positive rebase: Mint tokens as a percentage of total supply
            uint256 mintAmount = (currentTotalSupply * uint256(rebaseRate)) / 1e6; // Assuming rebaseRate is in ppm
            newTotalSupply = currentTotalSupply + mintAmount;
            _mint(address(this), mintAmount);
        } else {
            // Negative rebase: Burn tokens as a percentage of total supply
            uint256 burnAmount = (currentTotalSupply * uint256(-rebaseRate)) / 1e6; // Convert negative rebaseRate to positive
            uint256 availableRewards = availableRewards_view();
            require(availableRewards >= burnAmount, "Insufficient rewards to burn");

            newTotalSupply = currentTotalSupply > burnAmount ? currentTotalSupply - burnAmount : 0;
            require(newTotalSupply > 0, "Total supply must remain positive");
            _burn(address(this), burnAmount);
        }

        // Update reward pool after rebase
        updateRewardPool();

        emit Rebase(rebaseRate, newTotalSupply);
    }

     function mint(address to, uint256 amount) external onlyRebaseRecipientOrOwner {
        require(amount > 0, "Mint amount must be greater than zero");
        _mint(to, amount);
    }


    function setRebaseRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), "Invalid recipient address");
        address oldRecipient = rebaseRecipient;
        rebaseRecipient = newRecipient;
        emit RebaseRecipientUpdated(oldRecipient, newRecipient);
    }
}