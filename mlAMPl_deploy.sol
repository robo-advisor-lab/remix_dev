// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MLAMPL is ERC20, ERC20Burnable, Ownable, ERC20Permit {
    event Rebase(int256 rebaseRate, uint256 newTotalSupply);

    bool private initialized = false;

    constructor(address initialOwner)
        ERC20("ML AMPL", "mlAMPL")
        Ownable(initialOwner)
        ERC20Permit("ML AMPL")
    {}

    /**
     * @dev Initializes the token supply by minting tokens to the owner.
     * Can only be called once.
     * @param amount The initial amount of tokens to mint.
     * Amount is in WEI
     */
    function initializeSupply(uint256 amount) external onlyOwner {
        require(!initialized, "Supply already initialized");
        _mint(msg.sender, amount);
        initialized = true;
    }

    /**
     * @dev Adjust the total supply of the token by minting or burning directly in the contract.
     * @param rebaseRate The percentage change in supply, scaled by 1e6 (e.g., 100000 = 10% increase, -100000 = 10% decrease).
     */
    function rebase(int256 rebaseRate) external onlyOwner {
        require(rebaseRate != 0, "Rebase rate cannot be zero");

        uint256 currentTotalSupply = totalSupply();
        int256 supplyDelta = (int256(currentTotalSupply) * rebaseRate) / 1e6;

        if (supplyDelta > 0) {
            _mint(address(this), uint256(supplyDelta));
        } else {
            _burn(address(this), uint256(-supplyDelta));
        }

        uint256 newTotalSupply = totalSupply();
        emit Rebase(rebaseRate, newTotalSupply);
    }

    /**
     * @dev Distribute minted tokens to specific addresses.
     * @param recipients The list of addresses to receive tokens.
     * @param amounts The list of amounts to distribute (must match recipients length).
     */
    function distribute(address[] calldata recipients, uint256[] calldata amounts) external onlyOwner {
        require(recipients.length == amounts.length, "Mismatched inputs");

        for (uint256 i = 0; i < recipients.length; i++) {
            _transfer(address(this), recipients[i], amounts[i]);
        }
    }
}
