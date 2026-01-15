// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IMessageTransmitterV2} from "./interfaces/IMessageTransmitterV2.sol";
import {CCTPMessageV2} from "./CCTPMessageV2.sol";
import {HookDataV1} from "../common/HookDataV1.sol";

import {USDCVault} from "../vault/USDCVault.sol";

contract L1CCTPExecutor is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error InvalidDestinationDomain(uint32 got);
    error InvalidDestinationCaller(bytes32 got);
    error InvalidMintRecipient(bytes32 got);
    error ReceiveMessageFailed();
    error ZeroMinted();

    IERC20 public immutable usdc;
    USDCVault public immutable vault;
    IMessageTransmitterV2 public immutable messageTransmitter;

    uint32 public immutable localDomain; // Ethereum = 0
    bytes32 public immutable selfBytes32;

    event DepositFinalized(
        bytes32 indexed messageHash,
        uint32 indexed sourceDomain,
        uint32 finalityExecuted,
        address indexed ownerL1,
        uint64 clientNonce,
        uint256 amountBurned,
        uint256 feeExecuted,
        uint256 assetsMintedNet,
        uint256 sharesMinted
    );

    constructor(address usdc_, address vault_, address messageTransmitter_, uint32 localDomain_) {
        usdc = IERC20(usdc_);
        vault = USDCVault(vault_);
        messageTransmitter = IMessageTransmitterV2(messageTransmitter_);
        localDomain = localDomain_;
        selfBytes32 = CCTPMessageV2.addressToBytes32(address(this));
    }

    function finalize(bytes calldata message, bytes calldata attestation)
        external
        nonReentrant
        returns (uint256 shares)
    {
        // -------- Defensive parsing (before consuming message) --------
        uint32 destDomain = CCTPMessageV2.destinationDomain(message);
        if (destDomain != localDomain) revert InvalidDestinationDomain(destDomain);

        // destinationCaller is in message header: if nonzero, must be caller of receiveMessage.
        bytes32 destCaller = CCTPMessageV2.destinationCaller(message);
        if (destCaller != bytes32(0) && destCaller != selfBytes32) {
            revert InvalidDestinationCaller(destCaller);
        }

        bytes calldata body = CCTPMessageV2.messageBody(message);

        // mintRecipient must be this Executor (we set it كذلك في L2Gateway)
        bytes32 mintRecipient = CCTPMessageV2.burnMintRecipient(body);
        if (mintRecipient != selfBytes32) revert InvalidMintRecipient(mintRecipient);

        bytes calldata hookData = CCTPMessageV2.burnHookData(body);
        (address ownerL1, uint64 clientNonce,) = HookDataV1.decodeDeposit(hookData);

        uint256 amountBurned = CCTPMessageV2.burnAmount(body);
        uint256 feeExecuted = CCTPMessageV2.burnFeeExecuted(body);
        uint32 finalityExec = CCTPMessageV2.finalityThresholdExecuted(message);

        // -------- Consume CCTP message (mint USDC to this contract) --------
        uint256 balBefore = usdc.balanceOf(address(this));
        bool ok = messageTransmitter.receiveMessage(message, attestation);
        if (!ok) revert ReceiveMessageFailed();
        uint256 balAfter = usdc.balanceOf(address(this));

        uint256 mintedNet = balAfter - balBefore;
        if (mintedNet == 0) revert ZeroMinted();

        // -------- Deposit net minted into Vault --------
        usdc.forceApprove(address(vault), mintedNet);
        shares = vault.deposit(mintedNet, ownerL1);
        usdc.forceApprove(address(vault), 0);

        emit DepositFinalized(
            keccak256(message),
            CCTPMessageV2.sourceDomain(message),
            finalityExec,
            ownerL1,
            clientNonce,
            amountBurned,
            feeExecuted,
            mintedNet,
            shares
        );
    }
}

