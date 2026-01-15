// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {MockUSDC} from "./mocks/MockUSDC.sol";
import {MockStrategy} from "./mocks/MockStrategy.sol";

import {USDCVault} from "../src/vault/USDCVault.sol";
import {RiskManager} from "../src/manager/RiskManager.sol";
import {StrategyManager} from "../src/manager/StrategyManager.sol";

contract USDCVaultTest is Test {
    MockUSDC usdc;
    USDCVault vault;
    RiskManager risk;
    StrategyManager stratMgr;
    MockStrategy strategy;

    address guardian = address(0xBEEF);
    address strategist = address(0xCAFE);
    address user = address(0xA11CE);

    function setUp() public {
        usdc = new MockUSDC();

        vault = new USDCVault(usdc, "Omni USDC Vault", "ovUSDC");
        risk = new RiskManager();
        stratMgr = new StrategyManager(address(vault), address(usdc));
        strategy = new MockStrategy(address(usdc));

        // roles on vault
        vault.grantRole(vault.GUARDIAN_ROLE(), guardian);
        vault.grantRole(vault.STRATEGIST_ROLE(), strategist);

        // wire managers
        vault.setManagers(address(stratMgr), address(risk));

        // add strategy + caps
        stratMgr.addStrategy(address(strategy));
        risk.setTVLCap(1_000_000e6);
        risk.setBufferTargetBps(1000); // 10%
        risk.setStrategyCap(address(strategy), 1_000_000e6);

        // fund user
        usdc.mint(user, 2_000e6);
    }

    function test_deposit_and_withdraw_basic() public {
        vm.startPrank(user);
        usdc.approve(address(vault), type(uint256).max);

        vault.deposit(1_000e6, user);
        assertEq(vault.totalAssets(), 1_000e6);
        assertEq(vault.balanceOf(user), 1_000e6);

        vault.withdraw(200e6, user, user);
        assertEq(vault.totalAssets(), 800e6);
        assertEq(vault.balanceOf(user), 800e6);
        vm.stopPrank();
    }

    function test_allocate_respects_buffer() public {
        vm.startPrank(user);
        usdc.approve(address(vault), type(uint256).max);
        vault.deposit(1_000e6, user);
        vm.stopPrank();

        // buffer target 10% => must keep >= 100e6 in vault
        vm.prank(strategist);
        vm.expectRevert(); // BufferTooLow
        vault.allocateToStrategy(address(strategy), 950e6);
    }

    function test_withdraw_pulls_from_strategy() public {
        vm.startPrank(user);
        usdc.approve(address(vault), type(uint256).max);
        vault.deposit(1_000e6, user);
        vm.stopPrank();

        vm.prank(strategist);
        vault.allocateToStrategy(address(strategy), 850e6);

        // vault buffer now ~150e6, withdraw 400e6 => should pull from strategy
        vm.startPrank(user);
        vault.withdraw(400e6, user, user);
        vm.stopPrank();

        assertEq(vault.totalAssets(), 600e6);
    }

    function test_tvl_cap_enforced() public {
        risk.setTVLCap(500e6);

        vm.startPrank(user);
        usdc.approve(address(vault), type(uint256).max);
        vm.expectRevert(); // TVLCapExceeded
        vault.deposit(600e6, user);
        vm.stopPrank();
    }

    function test_pause_deposits_only() public {
        vm.prank(guardian);
        vault.setDepositsPaused(true);

        vm.startPrank(user);
        usdc.approve(address(vault), type(uint256).max);
        vm.expectRevert(USDCVault.DepositsPaused.selector);
        vault.deposit(100e6, user);
        vm.stopPrank();
    }
}
