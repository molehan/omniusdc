// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IStrategy {
    /// @notice Underlying asset (USDC) this strategy accepts.
    function asset() external view returns (address);

    /// @notice Total USDC controlled by the strategy, net of losses.
    function totalAssets() external view returns (uint256);

    /// @dev Vault already transferred `assets` to strategy before calling this.
    function deposit(uint256 assets) external;

    /// @notice Withdraw up to `assets` to `recipient`.
    /// @dev MUST NOT revert on partial liquidity; should return actual withdrawn amount.
    function withdraw(uint256 assets, address recipient) external returns (uint256 withdrawn);
}
