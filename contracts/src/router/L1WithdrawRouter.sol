// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {USDCVault} from "../vault/USDCVault.sol";
import {ITokenMessengerV2} from "../l2/interfaces/ITokenMessengerV2.sol";
import {CCTPMessageV2} from "../cctp/CCTPMessageV2.sol"; // فيه addressToBytes32()

contract L1WithdrawRouter is EIP712, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    // Confirmed (Fast)=1000, Finalized(Standard)=2000 :contentReference[oaicite:6]{index=6}
    uint32 public constant FINALITY_FAST = 1000;
    uint32 public constant FINALITY_STANDARD = 2000;

    enum TransferMode {
        Standard, // 0
        Fast // 1
    }

    struct WithdrawIntent {
        address owner; // shares owner on L1
        address receiver; // receives USDC on L2
        uint256 shares; // shares to redeem
        uint256 minAssetsOut; // minimum net-out (after worst-case fee)
        uint32 dstDomain; // CCTP domain for destination chain
        uint8 mode; // 0=Standard, 1=Fast
        uint256 maxFee; // max fee (units of USDC)
        uint256 deadline; // unix timestamp
        uint256 nonce; // must equal nonces[owner]
    }

    bytes32 public constant WITHDRAW_INTENT_TYPEHASH = keccak256(
        "WithdrawIntent(address owner,address receiver,uint256 shares,uint256 minAssetsOut,uint32 dstDomain,uint8 mode,uint256 maxFee,uint256 deadline,uint256 nonce)"
    );

    error Paused();
    error DomainNotAllowed(uint32 domain);
    error Expired(uint256 deadline, uint256 nowTs);
    error InvalidMode(uint8 mode);
    error InvalidNonce(uint256 expected, uint256 got);
    error InvalidSignature();
    error MaxFeeTooHigh(uint256 assets, uint256 maxFee);
    error MinAssetsOutNotMet(uint256 worstCaseNet, uint256 minAssetsOut);

    event PausedSet(bool paused);
    event DestinationDomainAllowed(uint32 indexed domain, bool allowed);
    event DestinationCallerSet(bytes32 destinationCaller);

    event WithdrawExecuted(
        bytes32 indexed intentDigest,
        address indexed owner,
        address indexed receiver,
        uint256 shares,
        uint256 assetsBurnedGross,
        uint256 maxFee,
        uint256 minAssetsOut,
        uint32 dstDomain,
        uint32 minFinalityThreshold,
        bytes32 destinationCaller
    );

    USDCVault public immutable vault;
    IERC20 public immutable usdc;
    ITokenMessengerV2 public immutable tokenMessenger;

    // Replay protection
    mapping(address => uint256) public nonces;

    // V1: نسمح فقط بدومينات L2 المعتمدة
    mapping(uint32 => bool) public allowedDestinationDomain;

    // If bytes32(0), anyone can call receiveMessage on destination. :contentReference[oaicite:7]{index=7}
    bytes32 public destinationCaller;

    bool public paused;

    constructor(address vault_, address tokenMessenger_) EIP712("OmniUSDC Withdraw Router", "1") {
        vault = USDCVault(vault_);
        usdc = IERC20(USDCVault(vault_).asset());
        tokenMessenger = ITokenMessengerV2(tokenMessenger_);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function setPaused(bool p) external {
        if (p) _checkRole(GUARDIAN_ROLE);
        else _checkRole(DEFAULT_ADMIN_ROLE);
        paused = p;
        emit PausedSet(p);
    }

    function setDestinationCaller(bytes32 dc) external onlyRole(DEFAULT_ADMIN_ROLE) {
        destinationCaller = dc;
        emit DestinationCallerSet(dc);
    }

    function setAllowedDestinationDomain(uint32 domain, bool allowed) external onlyRole(DEFAULT_ADMIN_ROLE) {
        allowedDestinationDomain[domain] = allowed;
        emit DestinationDomainAllowed(domain, allowed);
    }

    function hashWithdrawIntent(WithdrawIntent calldata intent) public view returns (bytes32 digest) {
        bytes32 structHash = keccak256(
            abi.encode(
                WITHDRAW_INTENT_TYPEHASH,
                intent.owner,
                intent.receiver,
                intent.shares,
                intent.minAssetsOut,
                intent.dstDomain,
                intent.mode,
                intent.maxFee,
                intent.deadline,
                intent.nonce
            )
        );
        digest = _hashTypedDataV4(structHash);
    }

    /// @notice permitSig optional: abi.encode(uint256 permitDeadline, uint8 v, bytes32 r, bytes32 s)
    function execute(WithdrawIntent calldata intent, bytes calldata signature, bytes calldata permitSig)
        external
        nonReentrant
        returns (uint256 assetsBurnedGross)
    {
        if (paused) revert Paused();
        if (!allowedDestinationDomain[intent.dstDomain]) revert DomainNotAllowed(intent.dstDomain);

        if (block.timestamp > intent.deadline) revert Expired(intent.deadline, block.timestamp);

        if (intent.mode > uint8(TransferMode.Fast)) revert InvalidMode(intent.mode);

        // nonce check (strictly sequential)
        uint256 expected = nonces[intent.owner];
        if (intent.nonce != expected) revert InvalidNonce(expected, intent.nonce);
        nonces[intent.owner] = expected + 1;

        // signature check
        bytes32 digest = hashWithdrawIntent(intent);
        address signer = ECDSA.recover(digest, signature);
        if (signer != intent.owner) revert InvalidSignature();

        // optional permit for shares (vault shares are ERC20Permit in USDCVault)
        if (permitSig.length != 0) {
            (uint256 permitDeadline, uint8 v, bytes32 r, bytes32 s) =
                abi.decode(permitSig, (uint256, uint8, bytes32, bytes32));

            vault.permit(intent.owner, address(this), intent.shares, permitDeadline, v, r, s);
        }

        // redeem shares -> USDC held by router
        uint256 assets = vault.redeem(intent.shares, address(this), intent.owner);

        // Worst-case net out after fee cap
        if (assets <= intent.maxFee) revert MaxFeeTooHigh(assets, intent.maxFee);
        uint256 worstCaseNet = assets - intent.maxFee;
        if (worstCaseNet < intent.minAssetsOut) revert MinAssetsOutNotMet(worstCaseNet, intent.minAssetsOut);

        // burn via CCTP (without hooks)
        uint32 minFinalityThreshold = (intent.mode == uint8(TransferMode.Fast)) ? FINALITY_FAST : FINALITY_STANDARD;

        usdc.forceApprove(address(tokenMessenger), assets);

        tokenMessenger.depositForBurn(
            assets,
            intent.dstDomain,
            CCTPMessageV2.addressToBytes32(intent.receiver),
            address(usdc),
            destinationCaller, // bytes32(0) => permissionless receiveMessage on dst :contentReference[oaicite:8]{index=8}
            intent.maxFee,
            minFinalityThreshold
        );

        usdc.forceApprove(address(tokenMessenger), 0);

        emit WithdrawExecuted(
            digest,
            intent.owner,
            intent.receiver,
            intent.shares,
            assets,
            intent.maxFee,
            intent.minAssetsOut,
            intent.dstDomain,
            minFinalityThreshold,
            destinationCaller
        );

        return assets;
    }
}

