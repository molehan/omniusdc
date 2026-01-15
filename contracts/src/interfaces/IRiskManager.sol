// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IRiskManager {
    function tvlCap() external view returns (uint256);
    function bufferTargetBps() external view returns (uint16);
    function strategyCap(address strategy) external view returns (uint256);

    function validateDeposit(uint256 currentTotalAssets, uint256 depositAssets) external view;

    function validateAllocate(
        address strategy,
        uint256 vaultAssetBalance,
        uint256 totalAssets,
        uint256 currentPrincipal,
        uint256 allocateAssets
    ) external view;
}
