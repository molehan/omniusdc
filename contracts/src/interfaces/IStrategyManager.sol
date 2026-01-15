// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IStrategyManager {
    function isStrategyEnabled(address strategy) external view returns (bool);

    /// @notice Principal tracked for cap checks (does not include yield).
    function principalAllocated(address strategy) external view returns (uint256);

    /// @notice Sum of `strategy.totalAssets()` across enabled strategies.
    function totalStrategyAssets() external view returns (uint256);

    /// @dev Called by Vault after successful allocation.
    function recordAllocation(address strategy, uint256 assets) external;

    /// @dev Called by Vault to pull liquidity from a specific strategy.
    function withdrawFromStrategy(address strategy, uint256 assets) external returns (uint256 withdrawn);

    /// @dev Called by Vault to pull liquidity across strategies.
    function withdrawToVault(uint256 assets) external returns (uint256 withdrawn);
}
