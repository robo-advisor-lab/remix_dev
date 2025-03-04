// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

function attachHook(address hookAddress, bytes32 poolId) external {
    PoolKey memory key = PoolKey({
        currency0: token0,
        currency1: token1,
        fee: fee,
        tickSpacing: tickSpacing,
        hooks: hookAddress // Assign the hook to the pool
    });

    poolManager.updatePoolKey(poolId, key);
}
