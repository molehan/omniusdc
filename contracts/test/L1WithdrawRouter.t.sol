// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {MockUSDC} from "./mocks/MockUSDC.sol";
import {USDCVault} from "../src/vault/USDCVault.sol";
import {MockTokenMessengerV2} from "./mocks/MockTokenMessengerV2.sol";
import {L1WithdrawRouter} from "../src/router/L1WithdrawRouter.sol";
import {ITokenMessengerV2} from "../src/l2/interfaces/ITokenMessengerV2.sol";

contract L1WithdrawRouterTest is Test {
    MockUSDC usdc;
    USDCVault vault;
    MockTokenMessengerV2 messenger;
    L1WithdrawRouter router;

    uint256 ownerPk;
    address owner;
    address receiverL2 = address(0xB0B);
    address relayer = address(0x9999);

    uint32 dstDomain = 6; // مثال (ضعوا domain الحقيقي لاحقًا في بيئة النشر)

    function setUp() public {
        usdc = new MockUSDC();
        vault = new USDCVault(usdc, "Omni USDC Vault", "ovUSDC");

        messenger = new MockTokenMessengerV2();
        router = new L1WithdrawRouter(address(vault), address(messenger));

        // allow domain (V1 single L2)
        router.setAllowedDestinationDomain(dstDomain, true);

        // owner key
        ownerPk = 0xA11CE;
        owner = vm.addr(ownerPk);

        // fund + deposit to mint shares
        usdc.mint(owner, 1_000e6);

        vm.startPrank(owner);
        usdc.approve(address(vault), type(uint256).max);
        vault.deposit(1_000e6, owner); // shares ~ 1_000e6 (mUSDC decimals=6)
        vm.stopPrank();
    }

    function _sign(L1WithdrawRouter.WithdrawIntent memory intent) internal view returns (bytes memory sig) {
        bytes32 digest = router.hashWithdrawIntent(intent);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);
        sig = abi.encodePacked(r, s, v);
    }

    function testExecuteStandardWithApprove() public {
        // approve router to spend shares
        vm.prank(owner);
        vault.approve(address(router), type(uint256).max);

        L1WithdrawRouter.WithdrawIntent memory intent = L1WithdrawRouter.WithdrawIntent({
            owner: owner,
            receiver: receiverL2,
            shares: 500e6,
            minAssetsOut: 498e6, // net worst-case
            dstDomain: dstDomain,
            mode: 0, // Standard
            maxFee: 2e6,
            deadline: block.timestamp + 1 hours,
            nonce: 0
        });

        bytes memory sig = _sign(intent);

        vm.prank(relayer);
        uint256 burned = router.execute(intent, sig, "");

        assertEq(burned, 500e6);

        // messenger should have pulled USDC from router
        assertEq(usdc.balanceOf(address(messenger)), 500e6);

        // ensure router used depositForBurn (no hook)
        assertEq(messenger.lastSelector(), ITokenMessengerV2.depositForBurn.selector);
        assertEq(messenger.lastDestinationDomain(), dstDomain);
        assertEq(messenger.lastMintRecipient(), bytes32(uint256(uint160(receiverL2))));
        assertEq(messenger.lastMinFinalityThreshold(), uint32(2000));
    }

    function testExecuteFastWithPermit() public {
        // build permit signature for shares = intent.shares
        uint256 shares = 100e6;
        uint256 permitDeadline = block.timestamp + 1 hours;

        bytes32 PERMIT_TYPEHASH =
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

        uint256 permitNonce = vault.nonces(owner);
        bytes32 structHash =
            keccak256(abi.encode(PERMIT_TYPEHASH, owner, address(router), shares, permitNonce, permitDeadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", vault.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);
        bytes memory permitSig = abi.encode(permitDeadline, v, r, s);

        L1WithdrawRouter.WithdrawIntent memory intent = L1WithdrawRouter.WithdrawIntent({
            owner: owner,
            receiver: receiverL2,
            shares: shares,
            minAssetsOut: 99e6,
            dstDomain: dstDomain,
            mode: 1, // Fast
            maxFee: 1e6,
            deadline: block.timestamp + 1 hours,
            nonce: 0
        });

        bytes memory sig = _sign(intent);

        vm.prank(relayer);
        router.execute(intent, sig, permitSig);

        assertEq(messenger.lastMinFinalityThreshold(), uint32(1000));
        assertEq(messenger.lastSelector(), ITokenMessengerV2.depositForBurn.selector);
    }

    function testReplayNonceReverts() public {
        vm.prank(owner);
        vault.approve(address(router), type(uint256).max);

        L1WithdrawRouter.WithdrawIntent memory intent = L1WithdrawRouter.WithdrawIntent({
            owner: owner,
            receiver: receiverL2,
            shares: 10e6,
            minAssetsOut: 9e6,
            dstDomain: dstDomain,
            mode: 0,
            maxFee: 1e6,
            deadline: block.timestamp + 1 hours,
            nonce: 0
        });

        bytes memory sig = _sign(intent);

        vm.prank(relayer);
        router.execute(intent, sig, "");

        vm.prank(relayer);
        vm.expectRevert(); // InvalidNonce
        router.execute(intent, sig, "");
    }
}
