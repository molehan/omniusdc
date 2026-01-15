# Architecture (V1)

## High-Level Overview

- All settlement, liquidity, and yield strategies live on **Ethereum Mainnet (L1)**.
- Users interact from **one L2**:
  - Deposits: user burns USDC on L2 via CCTP V2; USDC is minted on L1 and deposited into the vault.
  - Withdrawals: user signs an intent offchain; a relayer executes it on L1; USDC is burned on L1 via CCTP V2 and minted on the L2.

## Components

### L1 (Ethereum Mainnet)

- **USDCVault (ERC-4626)**
  USDC vault that mints shares and allocates capital into strategies while maintaining an L1 buffer.
- **StrategyManager**
  Owns the set of whitelisted strategies and performs allocate/deallocate actions.
- **RiskManager**
  Enforces hard risk constraints: TVL cap, per-strategy caps, buffer target, optional daily withdraw limits, and Fast-mode policy.
- **L1CCTPExecutor**
  Receives and finalizes CCTP messages on L1, parses hookData, and deposits minted USDC into `USDCVault`.
- **L1WithdrawRouter**
  Verifies EIP-712 withdraw intents, redeems vault shares, and initiates CCTP V2 burns to the destination L2.

### L2 (Source)

- **L2Gateway**
  User entry point for deposits; collects USDC and calls CCTP V2 `depositForBurn(...)` to L1 with hookData.
- **(Optional) L2Receiver**
  Used only if we decide L2 minting must go to a contract first (instead of the user address).

## Deposit Flow (L2 → L1)

### Sequence

1. **User → L2Gateway**
   User calls:
   `L2Gateway.deposit(amount, ownerL1, mode)`
   where `ownerL1` is the final L1 share owner.

2. **L2Gateway → CCTP V2 (source chain)**
   `L2Gateway` calls `TokenMessengerV2.depositForBurn(...)`:
   - `amount` = USDC amount
   - `dstDomain` = Ethereum Mainnet domain id
   - `mintRecipient` = `L1CCTPExecutor` (L1 address)
   - `minFinalityThreshold` determined by `mode` (Standard default; Fast limited)
   - `hookData` = `DEPOSIT(ownerL1, clientNonce, referral, ...)`

3. **Relayer → L1CCTPExecutor.finalize(...)** (permissionless)
   Any relayer can finalize:
   `L1CCTPExecutor.finalize(message, attestation)`

4. **L1CCTPExecutor (destination)**
   - Calls `MessageTransmitterV2.receiveMessage(message, attestation)` (verification + mint).
   - Parses `hookData` and extracts `ownerL1`.
   - Deposits USDC into the vault:
     `USDCVault.deposit(assets, ownerL1)`

5. **Indexing Events**
   - L2: `DepositBurned(...)` includes `messageHash` for UI correlation.
   - L1: `DepositFinalized(...)` includes owner/assets/shares/srcDomain/messageHash.

## Withdraw Flow (L1 → L2) via Intent

### Sequence

1. **User signs WithdrawIntent (offchain, from L2 UI)**
   User signs EIP-712 intent including:
   - shares to redeem
   - L2 receiver address
   - destination domain
   - mode (Standard/Fast)
   - maxFee, deadline, nonce, minAssetsOut, etc.

2. **Relayer → L1WithdrawRouter.execute(...)**
   `L1WithdrawRouter.execute(intent, sig, permitSig?)`

3. **L1WithdrawRouter**
   - Verifies EIP-712 signature and checks `nonce/deadline`.
   - Optionally uses `permitSig` (EIP-2612) to pull shares without prior approval.
   - Redeems shares:
     `USDCVault.redeem(intent.shares, address(this), intent.owner)`
   - Enforces `assets >= minAssetsOut` if enabled.
   - Initiates CCTP V2 burn to L2 recipient:
     `TokenMessengerV2.depositForBurn(...)`

4. **Relayer finalizes on L2**
   Relayer calls `MessageTransmitterV2.receiveMessage(message, attestation)` on L2 to mint USDC to the recipient (or `L2Receiver`).

5. **Events**
   - L1: `WithdrawInitiated(owner, shares, assets, dstDomain, recipient, mode)`

## UX / Latency Notes

- **Standard transfers** on some OP Stack L2s may take ~**15–19 minutes**, primarily due to batch finality / L1 finalization requirements.
- **Fast transfers** are typically seconds, but depend on **global allowance** and may be intermittently unavailable.
- The system must support **fallback to Standard** when Fast cannot be used (allowance/threshold constraints).

## Failure & Recovery (V1)

- Finalization is permissionless: any party can submit `finalize(...)` if another relayer fails.
- Withdrawals rely on a relayer to submit `execute(...)` on L1:
  - If a tx fails/reverts, nonce is not consumed and the same intent can be retried (until deadline).
  - Intent consumption is atomic with successful execution.
- No path allows arbitrary external calls through finalize/execute; flows are strictly constrained.
