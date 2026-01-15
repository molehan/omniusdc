// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {MockUSDC} from "./mocks/MockUSDC.sol";
import {USDCVault} from "../src/vault/USDCVault.sol";

import {MockMessageTransmitterV2} from "./mocks/MockMessageTransmitterV2.sol";
import {L1CCTPExecutor} from "../src/cctp/L1CCTPExecutor.sol";
import {HookDataV1} from "../src/common/HookDataV1.sol";
import {CCTPMessageV2} from "../src/cctp/CCTPMessageV2.sol";

contract L1CCTPExecutorTest is Test {
    MockUSDC usdc;
    USDCVault vault;
    MockMessageTransmitterV2 mt;
    L1CCTPExecutor exec;

    address ownerL1 = address(0xA11CE);
    address feeRecipient = address(0xFEE);

    function setUp() public {
        usdc = new MockUSDC();
        vault = new USDCVault(usdc, "Omni USDC Vault", "ovUSDC");

        mt = new MockMessageTransmitterV2(address(usdc), feeRecipient);

        // localDomain = 0 (Ethereum)
        exec = new L1CCTPExecutor(address(usdc), address(vault), address(mt), 0);
    }

    function _makeMessage(
        uint32 sourceDomain,
        uint32 destDomain,
        address destinationCaller,
        address mintRecipient,
        uint256 amount,
        uint256 feeExecuted,
        uint32 finalityExecuted,
        bytes memory hookData
    ) internal pure returns (bytes memory) {
        bytes memory burn = abi.encodePacked(
            uint32(1), // burn version
            bytes32(0), // burnToken (unused in our test)
            CCTPMessageV2.addressToBytes32(mintRecipient),
            uint256(amount),
            bytes32(0), // messageSender
            uint256(0), // maxFee
            uint256(feeExecuted),
            uint256(0), // expirationBlock
            hookData
        );

        return abi.encodePacked(
            uint32(1), // message version
            uint32(sourceDomain),
            uint32(destDomain),
            bytes32(uint256(123)), // nonce
            bytes32(0), // sender
            bytes32(0), // recipient
            CCTPMessageV2.addressToBytes32(destinationCaller),
            uint32(2000), // minFinalityThreshold (standard)
            uint32(finalityExecuted),
            burn
        );
    }

    function testFinalizeDepositsNetMinted() public {
        uint256 amount = 100e6;
        uint256 fee = 1e6; // 1 USDC
        uint64 clientNonce = 42;

        bytes memory hookData = HookDataV1.encodeDeposit(ownerL1, clientNonce, bytes32(0));

        bytes memory message = _makeMessage(
            6, // e.g. Base domain id (example)
            0, // Ethereum
            address(exec),
            address(exec),
            amount,
            fee,
            2000,
            hookData
        );

        // net minted to exec = amount - fee
        uint256 net = amount - fee;

        uint256 shares = exec.finalize(message, hex"");
        assertEq(shares, net);
        assertEq(vault.balanceOf(ownerL1), net);
        assertEq(vault.totalAssets(), net);

        // fee minted separately in mock
        assertEq(usdc.balanceOf(feeRecipient), fee);
    }

    function testRevertsOnWrongMintRecipient() public {
        bytes memory hookData = HookDataV1.encodeDeposit(ownerL1, 1, bytes32(0));

        bytes memory message = _makeMessage(
            6,
            0,
            address(exec),
            address(0xBEEF), // wrong
            10e6,
            0,
            2000,
            hookData
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                L1CCTPExecutor.InvalidMintRecipient.selector, CCTPMessageV2.addressToBytes32(address(0xBEEF))
            )
        );
        exec.finalize(message, hex"");
    }

    function testRevertsOnWrongDestinationDomain() public {
        bytes memory hookData = HookDataV1.encodeDeposit(ownerL1, 1, bytes32(0));
        bytes memory message = _makeMessage(
            6,
            999, // wrong dest domain
            address(exec),
            address(exec),
            10e6,
            0,
            2000,
            hookData
        );

        vm.expectRevert(abi.encodeWithSelector(L1CCTPExecutor.InvalidDestinationDomain.selector, uint32(999)));
        exec.finalize(message, hex"");
    }
}
