// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ✅ Import Uniswap v4 BaseHook (Handles Hook Logic)
import "https://raw.githubusercontent.com/Uniswap/v4-periphery/main/src/utils/BaseHook.sol";
import {} from "https://raw.githubusercontent.com/Uniswap/v4-core/main/src/libraries/Hooks.sol";

/**
 * @title Liquidity Target Hook
 * @dev A Uniswap v4 Hook that forces liquidity to concentrate at a target tick.
 */
contract LiquidityTargetHook is BaseHook {
    int24 public targetTick;  // The tick where liquidity should be concentrated
    address public owner;

    event TargetTickUpdated(int24 newTargetTick);

    /**
     * @dev Constructor to initialize the hook.
     * @param _poolManager Address of the Uniswap v4 PoolManager contract.
     * @param _initialTick Initial tick where liquidity should be concentrated.
     */
    constructor(address _poolManager, int24 _initialTick) BaseHook(IPoolManager(_poolManager)) {
        targetTick = _initialTick;
        owner = msg.sender;
    }

    /**
     * @dev Implements required function from BaseHook to define Hook permissions.
     * @return permissions The permissions for this hook.
     */
    function getHookPermissions() public pure override returns (Hooks.Permissions memory permissions) {
        // ✅ Define the permissions for this hook (example: allowing swaps & liquidity updates)
        permissions = Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeModifyPosition: true,  // Hook will enforce liquidity concentration
            afterModifyPosition: false,
            beforeSwap: false,
            afterSwap: false
        });
    }

    /**
     * @dev Allows the owner to update the target tick.
     * @param _newTick The new target tick value.
     */
    function setTargetTick(int24 _newTick) external {
        require(msg.sender == owner, "Not authorized");
        targetTick = _newTick;
        emit TargetTickUpdated(_newTick);
    }
}
