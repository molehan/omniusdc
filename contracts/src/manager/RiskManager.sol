// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IRiskManager} from "../interfaces/IRiskManager.sol";

contract RiskManager is AccessControl, IRiskManager {
    uint16 public constant MAX_BPS = 10_000;

    error TVLCapExceeded(uint256 cap, uint256 newTotalAssets);
    error InvalidBps(uint16 bps);
    error StrategyCapNotSet(address strategy);
    error StrategyCapExceeded(address strategy, uint256 cap, uint256 newPrincipal);
    error BufferTooLow(uint256 minBuffer, uint256 remainingBuffer);
    error InsufficientVaultBalance(uint256 balance, uint256 required);

    uint256 public tvlCap; // 0 => no cap
    uint16 public bufferTargetBps; // e.g. 1000 = 10%

    mapping(address => uint256) public strategyCap; // 0 => not allowed in V1

    event TVLCapSet(uint256 cap);
    event BufferTargetBpsSet(uint16 bps);
    event StrategyCapSet(address indexed strategy, uint256 cap);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        bufferTargetBps = 1000; // sane default (10%) for local tests
    }

    function setTVLCap(uint256 cap) external onlyRole(DEFAULT_ADMIN_ROLE) {
        tvlCap = cap;
        emit TVLCapSet(cap);
    }

    function setBufferTargetBps(uint16 bps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (bps > MAX_BPS) revert InvalidBps(bps);
        bufferTargetBps = bps;
        emit BufferTargetBpsSet(bps);
    }

    function setStrategyCap(address strategy, uint256 cap) external onlyRole(DEFAULT_ADMIN_ROLE) {
        strategyCap[strategy] = cap;
        emit StrategyCapSet(strategy, cap);
    }

    function validateDeposit(uint256 currentTotalAssets, uint256 depositAssets) external view {
        uint256 cap = tvlCap;
        if (cap == 0) return;

        unchecked {
            uint256 newTotal = currentTotalAssets + depositAssets;
            if (newTotal > cap) revert TVLCapExceeded(cap, newTotal);
        }
    }

    function validateAllocate(
        address strategy,
        uint256 vaultAssetBalance,
        uint256 totalAssets,
        uint256 currentPrincipal,
        uint256 allocateAssets
    ) external view {
        if (vaultAssetBalance < allocateAssets) {
            revert InsufficientVaultBalance(vaultAssetBalance, allocateAssets);
        }

        uint256 cap = strategyCap[strategy];
        if (cap == 0) revert StrategyCapNotSet(strategy);

        unchecked {
            uint256 newPrincipal = currentPrincipal + allocateAssets;
            if (newPrincipal > cap) revert StrategyCapExceeded(strategy, cap, newPrincipal);
        }

        // Buffer constraint: keep at least totalAssets * bufferTargetBps in the vault after allocation.
        uint256 minBuffer = (totalAssets * bufferTargetBps) / MAX_BPS;
        uint256 remaining = vaultAssetBalance - allocateAssets;
        if (remaining < minBuffer) revert BufferTooLow(minBuffer, remaining);
    }
}
