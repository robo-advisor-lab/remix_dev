// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {LiquidityTargetHook} from "./LiquidityTargetHook.sol"; // Ensure the Hook contract is properly imported

contract HookDeployer {
    using PoolIdLibrary for PoolKey;

    IPoolManager public immutable poolManager;

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

        // ✅ 2️⃣ Define the PoolKey with Hook
        PoolKey memory key = PoolKey({
            currency0: token0,
            currency1: token1,
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: hookAddress // Assign the new Hook
        });

        // ✅ 3️⃣ Attach Hook to Pool
        poolManager.updatePoolKey(poolId, key);

        emit HookDeployedAndAttached(hookAddress, poolId);
    }

    event HookDeployedAndAttached(address hookAddress, bytes32 poolId);
}
