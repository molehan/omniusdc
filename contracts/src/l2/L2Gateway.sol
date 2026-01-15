// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {ITokenMessengerV2} from "./interfaces/ITokenMessengerV2.sol";
import {HookDataV1} from "../common/HookDataV1.sol";

contract L2Gateway is ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum TransferMode {
        Standard, // 2000
        Fast // 1000
    }

    // CCTP V2 finality thresholds (Confirmed=1000, Finalized=2000)
    // (CCTP يقيّد القيم فعليًا لهذين المستويين) :contentReference[oaicite:8]{index=8}
    uint32 public constant FINALITY_FAST = 1000;
    uint32 public constant FINALITY_STANDARD = 2000;

    IERC20 public immutable usdc;
    ITokenMessengerV2 public immutable tokenMessenger;

    // Destination = Ethereum (domain 0) في حالتنا. :contentReference[oaicite:9]{index=9}
    uint32 public immutable destinationDomain;

    // نستخدم نفس العنوان كـ mintRecipient و destinationCaller (L1 Executor)
    bytes32 public immutable l1ExecutorBytes32;

    event DepositInitiated(
        address indexed depositorL2,
        uint256 amount,
        address indexed ownerL1,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        bytes32 destinationCaller,
        uint32 minFinalityThreshold,
        uint256 maxFee,
        uint64 clientNonce,
        bytes32 referralCode
    );

    error ZeroAddress();
    error ZeroAmount();
    error InvalidOwner();

    constructor(address usdc_, address tokenMessenger_, uint32 destinationDomain_, address l1Executor_) {
        if (usdc_ == address(0) || tokenMessenger_ == address(0) || l1Executor_ == address(0)) {
            revert ZeroAddress();
        }

        usdc = IERC20(usdc_);
        tokenMessenger = ITokenMessengerV2(tokenMessenger_);
        destinationDomain = destinationDomain_;
        l1ExecutorBytes32 = _addressToBytes32(l1Executor_);
    }

    function deposit(
        uint256 amount,
        address ownerL1,
        TransferMode mode,
        uint256 maxFee,
        uint64 clientNonce,
        bytes32 referralCode
    ) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (ownerL1 == address(0)) revert InvalidOwner();

        // 1) Pull USDC from user
        usdc.safeTransferFrom(msg.sender, address(this), amount);

        // 2) Approve TokenMessenger to take/burn
        usdc.forceApprove(address(tokenMessenger), amount);

        // 3) Build HookData
        bytes memory hookData = HookDataV1.encodeDeposit(ownerL1, clientNonce, referralCode);

        // 4) Choose finality
        uint32 minFinalityThreshold = (mode == TransferMode.Fast) ? FINALITY_FAST : FINALITY_STANDARD;

        // 5) CCTP burn + message (hookData appended) :contentReference[oaicite:10]{index=10}
        tokenMessenger.depositForBurnWithHook(
            amount,
            destinationDomain,
            l1ExecutorBytes32, // mintRecipient on L1
            address(usdc), // burnToken on L2
            l1ExecutorBytes32, // destinationCaller on L1 (only executor can call receiveMessage)
            maxFee,
            minFinalityThreshold,
            hookData
        );

        // 6) (Optional hardening) reset approval
        usdc.forceApprove(address(tokenMessenger), 0);

        emit DepositInitiated(
            msg.sender,
            amount,
            ownerL1,
            destinationDomain,
            l1ExecutorBytes32,
            l1ExecutorBytes32,
            minFinalityThreshold,
            maxFee,
            clientNonce,
            referralCode
        );
    }

    function _addressToBytes32(address a) internal pure returns (bytes32) {
        // Circle docs تشير لتحويل العنوان إلى bytes32 عبر padding أصفار (prefix zeros). :contentReference[oaicite:11]{index=11}
        return bytes32(uint256(uint160(a)));
    }
}
