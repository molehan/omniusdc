# Withdraw Intents (V1) — EIP-712

## Purpose

Withdrawals from the L1 vault are initiated by an offchain user signature and executed onchain by a relayer via `L1WithdrawRouter.execute(...)`.

## EIP-712 Domain (V1)

- `name`: `OmniUSDC Withdraw Router`
- `version`: `1`
- `chainId`: `1`
- `verifyingContract`: `L1WithdrawRouter`

## WithdrawIntent (V1) — Solidity Struct

```solidity
struct WithdrawIntent {
    address owner;        // L1 shares owner
    address receiver;     // L2 recipient of USDC
    uint256 shares;       // shares to redeem
    uint256 minAssetsOut; // slippage guard (0 = disabled)
    uint32  dstDomain;    // Circle domain id for destination L2
    uint8   mode;         // 0=STANDARD, 1=FAST (FAST may fallback to STANDARD)
    uint256 maxFee;       // max CCTP fee user accepts
    uint256 deadline;     // unix timestamp
    uint256 nonce;        // per-owner sequential nonce
}
```

## Replay Protection (V1 Decision)

**Sequential per-owner nonce (single stream):**

- Storage: `mapping(address => uint256) public nonces;`
- Execution rule:
  - `require(intent.nonce == nonces[intent.owner], "BAD_NONCE");`
  - increment `nonces[intent.owner]++` only after successful execution

This prevents replay and simplifies relayer operations.

## Deadline Policy

- `require(block.timestamp <= intent.deadline, "EXPIRED");`

## Signature Verification

- EOA signatures via ECDSA are required.
- **Recommended (V1):** support EIP-1271 for smart wallets.

## Shares Authorization

Two supported paths:

1. **Permit path (preferred):** provide `permitSig` to authorize the router to transfer shares (EIP-2612).
2. **Approve path:** user pre-approves the router for shares.

## Slippage Guard (minAssetsOut)

- After redeeming shares:
  - `require(assets >= intent.minAssetsOut, "SLIPPAGE");`
- `minAssetsOut = 0` disables the guard (not recommended).

## Fee Semantics (V1)

- No solver spread.
- Only allowed fees in V1:
  - CCTP fee (must be ≤ `maxFee`)
  - Protocol fees, if ever enabled, must be explicitly defined in `PARAMETERS_V1.md` (V1 default is 0)

## Fast Mode Semantics (V1)

- `mode=FAST` means “attempt Fast” within policy limits.
- **V1 decision:** router may fallback to Standard if Fast fails due to allowance/threshold constraints.
- `mode=STANDARD` never attempts Fast.

## Address Packing for CCTP

If CCTP requires `bytes32` recipients:
- Pack as left-padded:
  - `bytes32(uint256(uint160(receiver)))`
