// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {PoolIdLibrary} from "v4-core/src/types/PoolId.sol";

contract LiquidityTargetHook is BaseHook {
    using PoolIdLibrary for PoolId;

    int24 public targetTick;
    PoolId public poolId;
    address public owner;

    constructor(IPoolManager _poolManager, int24 _initialTick, PoolId _poolId)
        BaseHook(_poolManager)
    {
        targetTick = _initialTick;
        poolId = _poolId;
        owner = msg.sender;
    }

    function setTargetTick(int24 _newTick) external {
        require(msg.sender == owner, "Not authorized");
        targetTick = _newTick;
    }
}
