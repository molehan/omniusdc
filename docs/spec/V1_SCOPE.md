# V1 Scope

## V1 Summary

**Product:** OmniUSDC — a USDC vault on Ethereum Mainnet (liquidity hub) with a single L2 as the user source in V1.

- **Settlement / Liquidity Hub:** Ethereum Mainnet (L1)
- **User Source (Frontend + User TX):** One L2 in V1 (expandable later)
- **Asset:** USDC only
- **Cross-chain rail:** Circle CCTP V2 only
  - **Standard** is the default
  - **Fast** is optional, within strict limits
- **Core Value:** Stable, safety-first USDC yield (no leverage in V1)

## Goals (V1)

1. Enable USDC deposits from the L2 source into an L1 ERC-4626 vault using CCTP V2.
2. Enable withdrawals from the L1 vault to the L2 via signed intent (EIP-712) plus CCTP V2.
3. Provide a clear, auditable risk framework: caps, buffer, and emergency pause controls.

## In-Scope (V1)

- Deposit from L2 → L1 vault via **CCTP V2**.
- Withdraw from L1 vault → L2 via:
  - user-signed **WithdrawIntent (EIP-712)** from the L2 UI
  - execution on L1 by relayers through **L1WithdrawRouter**
  - **CCTP V2** burn/mint to the destination L2
- **ERC-4626 vault on L1** (`USDCVault`)
- **Single strategy** (or at most two) plus an L1 **buffer**
- Minimal role system: **Timelock + Guardian + Strategist**, with no arbitrary fund movement

## Out-of-Scope (V1)

- Governance token (no token in V1)
- Multi-asset vault
- Leverage / looping / delta-neutral strategies
- Onchain governance voting (use multisig + timelock only)
- Bridging via any third-party bridge (non-CCTP)
- Multiple L2 sources (V1 supports exactly one L2)

## Key Trust Assumptions

1. **Attestation correctness** and verification via official CCTP V2 contracts.
2. **USDC issuer risk** is out of scope (freeze/issuer insolvency/contract upgrades not covered).
3. Strategy risk is limited by strict onboarding criteria and caps/buffer/pause controls.
4. Timelock/multisig operators act as designed; sensitive changes are delayed and publicly visible.

## Non-Goals (Explicit)

- “Marketing APY” at the expense of safety.
- Hidden fees or solver spreads.
- Excessive complexity (many strategies, complex oracle dependencies, opaque execution).

## Step 2 Checklist (Definition of Done)

Step 2 is considered complete when:

- All seven files exist under `docs/spec/` and are fully populated (not just headings).
- Deposit/withdraw flows are clearly defined with event sequencing.
- WithdrawIntent + nonce/replay policy is fully specified.
- Standard vs Fast policy is documented (thresholds, allowance dependence, fallback behavior).
- “CCTP V2 only” is explicit, with rationale.
- A strict Out-of-Scope section prevents uncontrolled V1 expansion.
- Risk policy explicitly states: **no leverage + caps + buffer + pause**, with explanation.
