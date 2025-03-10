// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ✅ Correct Uniswap v4 Imports
import "https://raw.githubusercontent.com/Uniswap/v4-core/main/src/interfaces/IPoolManager.sol";
import "https://raw.githubusercontent.com/Uniswap/v4-core/main/src/types/PoolKey.sol";
import "https://raw.githubusercontent.com/Uniswap/v4-core/main/src/types/PoolId.sol";

import "./LiquidityTargetHook.sol"; // Your local hook contract

contract HookDeployer {
    IPoolManager public immutable poolManager;

    event HookDeployedAndAttached(address hookAddress, bytes32 poolId);

    constructor(address _poolManager) {
        poolManager = IPoolManager(_poolManager);
    }

    function deployAndAttachHook(
        address token0,
        address token1,
        uint24 fee,
        int24 tickSpacing,
        bytes32 poolId,
        int24 initialTargetTick
    ) external returns (address hookAddress) {
        // ✅ 1️⃣ Deploy the Hook Contract
        LiquidityTargetHook hook = new LiquidityTargetHook(address(poolManager), initialTargetTick, poolId);
        hookAddress = address(hook);

        // ✅ 2️⃣ Define the PoolKey (without `PoolIdLibrary`)
        PoolKey memory key = PoolKey({
            currency0: token0,
            currency1: token1,
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: hookAddress // Assign the new Hook
        });

        // ✅ 3️⃣ Compute Pool ID manually (since we can't import `PoolIdLibrary`)
        bytes32 computedPoolId = keccak256(abi.encode(key));

        require(computedPoolId == poolId, "Computed Pool ID does not match provided ID");

        // ✅ 4️⃣ Attach Hook to Pool
        poolManager.updatePoolKey(poolId, key);

        emit HookDeployedAndAttached(hookAddress, poolId);
    }
}
