// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {L2Gateway} from "../src/l2/L2Gateway.sol";
import {HookDataV1} from "../src/l2/HookDataV1.sol";
import {MockTokenMessengerV2} from "./mocks/MockTokenMessengerV2.sol";

// استخدم Mock USDC الموجود عندك من الخطوات السابقة.
// إذا لا يوجد، استبدله بأي ERC20 مع decimals=6.
import {MockUSDC} from "./mocks/MockUSDC.sol";

contract L2GatewayTest is Test {
    MockUSDC usdc;
    MockTokenMessengerV2 messenger;
    L2Gateway gateway;

    address user = address(0x1111);
    address l1Executor = address(0xBEEF);
    address ownerL1 = address(0x2222);

    function setUp() public {
        usdc = new MockUSDC();
        messenger = new MockTokenMessengerV2();

        // destinationDomain = 0 (Ethereum) :contentReference[oaicite:12]{index=12}
        gateway = new L2Gateway(address(usdc), address(messenger), 0, l1Executor);

        usdc.mint(user, 1_000_000e6);
        vm.prank(user);
        IERC20(address(usdc)).approve(address(gateway), type(uint256).max);
    }

    function testDepositFastEncodesHookAndCallsMessenger() public {
        uint256 amount = 100e6;
        uint256 maxFee = 1_000; // مثال: 0.001 USDC
        uint64 clientNonce = 42;
        bytes32 referral = bytes32(uint256(123));

        bytes memory expectedHook = HookDataV1.encodeDeposit(ownerL1, clientNonce, referral);
        bytes32 execB32 = bytes32(uint256(uint160(l1Executor)));

        uint256 userBefore = usdc.balanceOf(user);

        vm.prank(user);
        gateway.deposit(amount, ownerL1, L2Gateway.TransferMode.Fast, maxFee, clientNonce, referral);

        assertEq(usdc.balanceOf(user), userBefore - amount);

        assertEq(messenger.lastCaller(), address(gateway));
        assertEq(messenger.lastAmount(), amount);
        assertEq(messenger.lastDestinationDomain(), uint32(0));
        assertEq(messenger.lastMintRecipient(), execB32);
        assertEq(messenger.lastDestinationCaller(), execB32);
        assertEq(messenger.lastMaxFee(), maxFee);
        assertEq(messenger.lastMinFinalityThreshold(), uint32(1000)); // Fast :contentReference[oaicite:13]{index=13}
        assertEq(keccak256(messenger.lastHookData()), keccak256(expectedHook));

        // Mock messenger أخذ التوكنات
        assertEq(usdc.balanceOf(address(messenger)), amount);
    }

    function testDepositStandardUses2000() public {
        uint256 amount = 10e6;

        vm.prank(user);
        gateway.deposit(amount, ownerL1, L2Gateway.TransferMode.Standard, 0, 1, bytes32(0));

        assertEq(messenger.lastMinFinalityThreshold(), uint32(2000)); // Standard :contentReference[oaicite:14]{index=14}
    }

    function testDepositRevertsOnZeroAmount() public {
        vm.prank(user);
        vm.expectRevert(L2Gateway.ZeroAmount.selector);
        gateway.deposit(0, ownerL1, L2Gateway.TransferMode.Standard, 0, 0, bytes32(0));
    }

    function testDepositRevertsOnZeroOwner() public {
        vm.prank(user);
        vm.expectRevert(L2Gateway.InvalidOwner.selector);
        gateway.deposit(1e6, address(0), L2Gateway.TransferMode.Standard, 0, 0, bytes32(0));
    }
}
