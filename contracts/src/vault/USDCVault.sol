// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IStrategy} from "../interfaces/IStrategy.sol";
import {IStrategyManager} from "../interfaces/IStrategyManager.sol";
import {IRiskManager} from "../interfaces/IRiskManager.sol";

contract USDCVault is ERC4626, ERC20Permit, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 public constant STRATEGIST_ROLE = keccak256("STRATEGIST_ROLE");

    error ZeroAddress();
    error ManagersNotSet();
    error DepositsPaused();
    error WithdrawalsPaused();
    error AllocationsPaused();
    error StrategyNotEnabled(address strategy);
    error InsufficientLiquidity(uint256 needed, uint256 available);

    event ManagersSet(address indexed strategyManager, address indexed riskManager);
    event DepositsPausedSet(bool paused);
    event WithdrawalsPausedSet(bool paused);
    event AllocationsPausedSet(bool paused);

    event StrategyAllocated(address indexed strategy, uint256 assets);
    event StrategyDeallocated(address indexed strategy, uint256 withdrawn);

    IStrategyManager public strategyManager;
    IRiskManager public riskManager;

    bool public depositsPaused;
    bool public withdrawalsPaused;
    bool public allocationsPaused;

    constructor(IERC20Metadata usdc, string memory name_, string memory symbol_)
        ERC20(name_, symbol_)
        ERC4626(usdc)
        ERC20Permit(name_)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // -----------------------------
    // Admin / Guardian controls
    // -----------------------------

    function setManagers(address strategyManager_, address riskManager_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (strategyManager_ == address(0) || riskManager_ == address(0)) revert ZeroAddress();
        strategyManager = IStrategyManager(strategyManager_);
        riskManager = IRiskManager(riskManager_);
        emit ManagersSet(strategyManager_, riskManager_);
    }

    /// @notice Guardian can pause; only admin (timelock) can unpause.
    function setDepositsPaused(bool paused) external {
        if (paused) _checkRole(GUARDIAN_ROLE);
        else _checkRole(DEFAULT_ADMIN_ROLE);
        depositsPaused = paused;
        emit DepositsPausedSet(paused);
    }

    function setWithdrawalsPaused(bool paused) external {
        if (paused) _checkRole(GUARDIAN_ROLE);
        else _checkRole(DEFAULT_ADMIN_ROLE);
        withdrawalsPaused = paused;
        emit WithdrawalsPausedSet(paused);
    }

    function setAllocationsPaused(bool paused) external {
        if (paused) _checkRole(GUARDIAN_ROLE);
        else _checkRole(DEFAULT_ADMIN_ROLE);
        allocationsPaused = paused;
        emit AllocationsPausedSet(paused);
    }

    // -----------------------------
    // ERC-4626 overrides
    // -----------------------------

    function totalAssets() public view override returns (uint256) {
        uint256 bal = IERC20(asset()).balanceOf(address(this));
        address sm = address(strategyManager);
        if (sm == address(0)) return bal;
        return bal + IStrategyManager(sm).totalStrategyAssets();
    }

    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256 shares) {
        if (depositsPaused) revert DepositsPaused();
        address rm = address(riskManager);
        if (rm != address(0)) {
            IRiskManager(rm).validateDeposit(totalAssets(), assets);
        }
        shares = super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver) public override nonReentrant returns (uint256 assets) {
        if (depositsPaused) revert DepositsPaused();
        assets = previewMint(shares);
        address rm = address(riskManager);
        if (rm != address(0)) {
            IRiskManager(rm).validateDeposit(totalAssets(), assets);
        }
        assets = super.mint(shares, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256 shares)
    {
        if (withdrawalsPaused) revert WithdrawalsPaused();
        _ensureLiquidity(assets);
        shares = super.withdraw(assets, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256 assets)
    {
        if (withdrawalsPaused) revert WithdrawalsPaused();
        assets = previewRedeem(shares);
        _ensureLiquidity(assets);
        assets = super.redeem(shares, receiver, owner);
    }

    // -----------------------------
    // Strategy allocation (V1)
    // -----------------------------

    function allocateToStrategy(address strategy, uint256 assets) external nonReentrant onlyRole(STRATEGIST_ROLE) {
        if (allocationsPaused) revert AllocationsPaused();

        address sm = address(strategyManager);
        address rm = address(riskManager);
        if (sm == address(0) || rm == address(0)) revert ManagersNotSet();

        if (!IStrategyManager(sm).isStrategyEnabled(strategy)) revert StrategyNotEnabled(strategy);

        uint256 vaultBal = IERC20(asset()).balanceOf(address(this));
        uint256 tot = totalAssets();
        uint256 currentPrincipal = IStrategyManager(sm).principalAllocated(strategy);

        IRiskManager(rm).validateAllocate(strategy, vaultBal, tot, currentPrincipal, assets);

        // Transfer to strategy, then call deposit hook
        IERC20(asset()).safeTransfer(strategy, assets);
        IStrategy(strategy).deposit(assets);

        IStrategyManager(sm).recordAllocation(strategy, assets);
        emit StrategyAllocated(strategy, assets);
    }

    function deallocateFromStrategy(address strategy, uint256 assets)
        external
        nonReentrant
        onlyRole(STRATEGIST_ROLE)
        returns (uint256 withdrawn)
    {
        address sm = address(strategyManager);
        if (sm == address(0)) revert ManagersNotSet();

        withdrawn = IStrategyManager(sm).withdrawFromStrategy(strategy, assets);
        emit StrategyDeallocated(strategy, withdrawn);
    }

    // -----------------------------
    // Internal liquidity
    // -----------------------------

    function _ensureLiquidity(uint256 needed) internal {
        uint256 bal = IERC20(asset()).balanceOf(address(this));
        if (bal >= needed) return;

        address sm = address(strategyManager);
        if (sm != address(0)) {
            uint256 missing = needed - bal;
            IStrategyManager(sm).withdrawToVault(missing);
        }

        uint256 balAfter = IERC20(asset()).balanceOf(address(this));
        if (balAfter < needed) revert InsufficientLiquidity(needed, balAfter);
    }

    // Resolve diamond inheritance of ERC20.decimals() via ERC4626 and ERC20Permit
    function decimals() public view override(ERC4626, ERC20) returns (uint8) {
        return ERC4626.decimals();
        // أو: return super.decimals();
    }
}
