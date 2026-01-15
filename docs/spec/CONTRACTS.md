# Contracts (V1)

## Contract List (V1)

### L1 (Ethereum Mainnet)

1. `USDCVault` (ERC-4626)
2. `StrategyManager`
3. `RiskManager`
4. `L1CCTPExecutor`
5. `L1WithdrawRouter`

### L2 (Source)

6. `L2Gateway`
7. `(Optional) L2Receiver`

## Global V1 Decisions

- **Single asset:** USDC only (canonical USDC supported by CCTP).
- **CCTP V2 only:** no third-party bridges.
- **No leverage:** no borrowing, looping, or derivative hedging.
- **Non-upgradeable contracts (V1):** deploy as immutable logic. Configuration changes occur via timelock-controlled parameters (caps/whitelists). If a breaking fix is needed, deploy V2 and migrate with a clear public process.

## Roles & Permissions (V1)

- `DEFAULT_ADMIN` = **Timelock**
  - Modify caps/limits/fees (if enabled)
  - Add/remove strategies from whitelists
  - Assign/revoke roles
- `GUARDIAN`
  - Pause-only authority (no asset transfer authority)
- `STRATEGIST`
  - Allocate/deallocate within caps and only when permitted by `RiskManager`

**Invariant:** No privileged role can arbitrarily withdraw user funds. There is no admin “sweep” path from the vault.

---

## 1) USDCVault (L1) — ERC-4626

### Purpose

ERC-4626 vault for USDC on L1 with:
- an L1 liquidity buffer
- strategy allocation via `StrategyManager`

### Asset / Shares

- `asset()` = USDC
- shares = ERC20
- **V1 decision:** support **EIP-2612 Permit** for vault shares to enable intent-based withdrawals without a prior onchain approve.

### Required Behavior

- Implement ERC-4626: `deposit`, `mint`, `withdraw`, `redeem`
- `totalAssets()` equals buffer + strategy assets (via `StrategyManager`)
- Pausing controls:
  - `pauseDeposits`
  - `pauseWithdraws` (or a unified pause with internal gating)

### Safety Requirements

- SafeERC20 everywhere
- Reentrancy guards on state-changing entry points
- Clear event emission for deposits/withdraws (ERC-4626 standard events + protocol-specific where necessary)

---

## 2) StrategyManager (L1)

### Purpose

Own and manage whitelisted strategies and move assets between the vault and strategies under risk constraints.

### State

- Whitelisted strategy list (address → bool)
- Strategy accounting (via explicit `report()` calls or view-based queries, depending on strategy design)

### Functions

- `allocate(strategy, assets)`
  - `onlyRole(STRATEGIST)`
  - must pass `RiskManager` checks (TVL, per-strategy, buffer constraints)
- `deallocate(strategy, assets)`
  - `onlyRole(STRATEGIST)` (and/or Timelock)
- `totalStrategyAssets()` / `report()`

### Controls

- Strategy whitelist changes only by Timelock.
- Events must be emitted for allocate/deallocate and strategy list updates.

---

## 3) RiskManager (L1)

### Purpose

Enforce hard risk rules and provide policy values for Router/Gateway.

### Enforces

- TVL cap
- Per-strategy caps
- Buffer target/min/max
- Optional max daily withdraw (0 = disabled)
- Fast-mode policy:
  - per-tx and per-day limits
  - allowed `minFinalityThreshold` bounds
  - fee constraints and other operational limits

### Expected Interface (Conceptual)

- `checkDeposit(assets)` (revert on violation)
- `checkWithdraw(owner, shares, assets, mode)` (revert on violation)
- `checkAllocate(strategy, assets)` (revert on violation)
- `getCCTPPolicy(mode)` returns thresholds and mode-specific parameters

---

## 4) L1CCTPExecutor (L1)

### Entry Point

- `finalize(bytes message, bytes attestation)` — **permissionless**

### Responsibilities

1. Call CCTP receive:
   - `MessageTransmitterV2.receiveMessage(message, attestation)`
2. Parse `hookData` from `message`:
   - must be `version=1`, `action=DEPOSIT`
   - extract `ownerL1`
3. Deposit minted USDC into the vault:
   - `USDCVault.deposit(assets, ownerL1)`
4. Emit indexing events

### Must Emit

- `DepositFinalized(owner, assets, shares, srcDomain, messageHash)`

### Safety Constraints

- Strictly limited execution path: `receiveMessage` → parse → `vault.deposit`
- No arbitrary calls
- NonReentrant

---

## 5) L1WithdrawRouter (L1)

### Entry Point

- `execute(WithdrawIntent intent, bytes sig, bytes permitSig?)`

### Responsibilities

- Verify EIP-712 signature (EOA and optionally EIP-1271)
- Enforce nonce and deadline
- If `permitSig` provided, call share permit to authorize share pull
- Redeem shares from the vault:
  - `USDCVault.redeem(intent.shares, address(this), intent.owner)`
- Enforce `assets >= intent.minAssetsOut` if enabled
- Initiate CCTP V2 burn to destination L2 recipient
- Emit events

### Must Emit

- `WithdrawInitiated(owner, shares, assets, dstDomain, recipient, mode)`

### Safety Constraints

- Funds move only as a consequence of redeeming the owner’s shares.
- Recipient/destination are fixed by the signed intent.
- Nonce consumption is atomic with successful execution.

---

## 6) L2Gateway (L2)

### Functionality

- `deposit(amount, ownerL1, mode)`
  - enforce basic limits (min deposit, max per-tx)
  - take USDC from user (transferFrom)
  - call CCTP V2 `depositForBurn(...)` to Ethereum with hookData

### Must Emit

- `DepositBurned(sender, amount, ownerL1, mode, messageHash)`

### Notes

- Gateway should not hold assets long-term.
- Standard is default; Fast only when allowed by policy and available.

---

## 7) (Optional) L2Receiver (L2)

Only required if minted USDC must be delivered to a contract first:
- Receives mint via CCTP, then forwards USDC to `intent.receiver`.
- V1 default is direct mint to `receiver` when feasible.
